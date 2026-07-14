import Foundation

extension CachingConcertRepository {
  func createPrivateConcert(_ input: ConcertCreationInput) async throws -> Concert {
    try await mutation {
      try await remote.createPrivateConcert(input)
    } reconcile: { _ in
      await invalidateArchiveAndFeed()
    }
  }

  func updateConcert(_ input: ConcertUpdateInput) async throws -> Concert {
    try await concertMutation {
      try await remote.updateConcert(input)
    }
  }

  func setConcertPhoto(_ jpegData: Data, concertID: UUID) async throws -> Concert {
    try await concertMutation {
      try await remote.setConcertPhoto(jpegData, concertID: concertID)
    }
  }

  func removeConcertPhoto(concertID: UUID) async throws -> Concert {
    try await concertMutation {
      try await remote.removeConcertPhoto(concertID: concertID)
    }
  }

  func reserveAlbumPhoto(concertID: UUID, photoID: UUID) async throws -> ConcertPhotoReservation {
    try await protectingPermissionCache {
      try await remote.reserveAlbumPhoto(concertID: concertID, photoID: photoID)
    }
  }

  func uploadReservedAlbumPhoto(
    _ jpegData: Data,
    reservation: ConcertPhotoReservation
  ) async throws -> ConcertAlbumPhoto {
    try await mutation {
      try await remote.uploadReservedAlbumPhoto(jpegData, reservation: reservation)
    } reconcile: { photo in
      await patchAlbum(photo, action: .insert)
      await invalidateDetail(concertID: photo.concertID)
      await invalidateArchiveAndFeed()
    }
  }

  func updateAlbumPhotoCaption(photoID: UUID, caption: String?) async throws -> ConcertAlbumPhoto {
    try await mutation {
      try await remote.updateAlbumPhotoCaption(photoID: photoID, caption: caption)
    } reconcile: { photo in
      await patchAlbum(photo, action: .replace)
    }
  }

  func deleteAlbumPhoto(photoID: UUID) async throws {
    try await mutation {
      try await remote.deleteAlbumPhoto(photoID: photoID)
    } reconcile: { _ in
      await cache.invalidate(resourcesNamed: [AppCacheResources.concertAlbumPhotosName])
      await cache.invalidate(AppCacheResources.friendsActivity)
    }
  }

  func deleteAlbumPhoto(photoID: UUID, concertID: UUID) async throws {
    try await mutation {
      try await remote.deleteAlbumPhoto(photoID: photoID)
    } reconcile: { _ in
      await patchAlbumDeletion(photoID: photoID, concertID: concertID)
      await cache.invalidate(AppCacheResources.friendsActivity)
    }
  }

  func tagCollaborator(
    concertID: UUID,
    profileID: UUID,
    expectedVersion: Int64
  ) async throws -> Concert {
    try await concertMutation {
      try await remote.tagCollaborator(
        concertID: concertID,
        profileID: profileID,
        expectedVersion: expectedVersion
      )
    }
  }

  func removeCollaborator(
    concertID: UUID,
    profileID: UUID,
    expectedVersion: Int64
  ) async throws -> Concert {
    try await concertMutation {
      try await remote.removeCollaborator(
        concertID: concertID,
        profileID: profileID,
        expectedVersion: expectedVersion
      )
    }
  }

  func transferOwnership(
    concertID: UUID,
    newOwnerID: UUID,
    expectedVersion: Int64
  ) async throws -> Concert {
    try await concertMutation {
      try await remote.transferOwnership(
        concertID: concertID,
        newOwnerID: newOwnerID,
        expectedVersion: expectedVersion
      )
    }
  }

  func deleteConcert(id: UUID) async throws {
    try await mutation {
      try await remote.deleteConcert(id: id)
    } reconcile: { _ in
      await removeConcertSnapshots(concertID: id)
      await invalidateArchiveAndFeed()
    }
  }

  func createComment(concertID: UUID, body: String) async throws -> ConcertComment {
    try await mutation {
      try await remote.createComment(concertID: concertID, body: body)
    } reconcile: { comment in
      await patchComment(comment, action: .insert)
      await invalidateDetail(concertID: comment.concertID)
      await invalidateArchiveAndFeed()
    }
  }

  func updateComment(commentID: UUID, body: String) async throws -> ConcertComment {
    try await mutation {
      try await remote.updateComment(commentID: commentID, body: body)
    } reconcile: { comment in
      await patchComment(comment, action: .replace)
      await invalidateDetail(concertID: comment.concertID)
      await invalidateArchiveAndFeed()
    }
  }

  func deleteComment(commentID: UUID) async throws {
    try await mutation {
      try await remote.deleteComment(commentID: commentID)
    } reconcile: { _ in
      await cache.invalidate(resourcesNamed: [
        AppCacheResources.concertCommentsName,
        AppCacheResources.concertDetailName
      ])
      await invalidateArchiveAndFeed()
    }
  }

  func deleteComment(commentID: UUID, concertID: UUID) async throws {
    try await mutation {
      try await remote.deleteComment(commentID: commentID)
    } reconcile: { _ in
      await patchCommentDeletion(commentID: commentID, concertID: concertID)
      await invalidateDetail(concertID: concertID)
      await invalidateArchiveAndFeed()
    }
  }

  private func concertMutation(
    _ operation: @escaping @Sendable () async throws -> Concert
  ) async throws -> Concert {
    try await mutation(operation) { concert in
      await patchDetail(with: concert)
      await invalidateArchiveAndFeed()
    }
  }

  private func mutation<Value: Sendable>(
    _ operation: @escaping @Sendable () async throws -> Value,
    reconcile: @escaping @Sendable (Value) async -> Void
  ) async throws -> Value {
    do {
      let value = try await operation()
      await reconcile(value)
      return value
    } catch {
      await purgeIfAccessWasLost(error)
      throw error
    }
  }
}

private extension CachingConcertRepository {
  enum ListPatchAction: Sendable {
    case insert
    case replace
  }

  func patchDetail(with concert: Concert) async {
    guard let scope = await cache.currentScope() else { return }
    await cache.patch(
      ConcertDetail.self,
      for: AppCacheResources.concertDetail(concertID: concert.id, viewerID: scope.viewerID),
      markInvalidated: true
    ) { detail in
      ConcertDetail(
        concert: concert,
        artists: detail.artists,
        setlist: detail.setlist,
        history: detail.history,
        collaborators: detail.collaborators
      )
    }
  }

  func patchComment(_ comment: ConcertComment, action: ListPatchAction) async {
    await cache.patch(
      [ConcertComment].self,
      for: AppCacheResources.concertComments(concertID: comment.concertID)
    ) { cached in
      var comments = cached.filter { $0.id != comment.id }
      switch action {
      case .insert:
        comments.insert(comment, at: 0)
      case .replace:
        if let insertionIndex = cached.firstIndex(where: { $0.id == comment.id }) {
          comments.insert(comment, at: min(insertionIndex, comments.count))
        }
      }
      return Array(comments.prefix(30))
    }
  }

  func patchCommentDeletion(commentID: UUID, concertID: UUID) async {
    let deletedAt = Date()
    await cache.patch(
      [ConcertComment].self,
      for: AppCacheResources.concertComments(concertID: concertID)
    ) { cached in
      cached.map { comment in
        guard comment.id == commentID else { return comment }
        return ConcertComment(
          id: comment.id,
          concertID: comment.concertID,
          authorID: comment.authorID,
          username: comment.username,
          displayName: comment.displayName,
          body: nil,
          createdAt: comment.createdAt,
          updatedAt: deletedAt,
          deletedAt: deletedAt
        )
      }
    }
  }

  func patchAlbum(_ photo: ConcertAlbumPhoto, action: ListPatchAction) async {
    await cache.patch(
      [ConcertAlbumPhoto].self,
      for: AppCacheResources.concertAlbumPhotos(concertID: photo.concertID)
    ) { cached in
      var photos = cached.filter { $0.id != photo.id }
      switch action {
      case .insert:
        photos.insert(photo, at: 0)
      case .replace:
        if let insertionIndex = cached.firstIndex(where: { $0.id == photo.id }) {
          photos.insert(photo, at: min(insertionIndex, photos.count))
        }
      }
      return Array(photos.prefix(30))
    }
  }

  func patchAlbumDeletion(photoID: UUID, concertID: UUID) async {
    await cache.patch(
      [ConcertAlbumPhoto].self,
      for: AppCacheResources.concertAlbumPhotos(concertID: concertID)
    ) { cached in
      cached.filter { $0.id != photoID }
    }
  }

  func removeConcertSnapshots(concertID: UUID) async {
    if let scope = await cache.currentScope() {
      await cache.remove(
        AppCacheResources.concertDetail(concertID: concertID, viewerID: scope.viewerID)
      )
    }
    await cache.remove(AppCacheResources.concertComments(concertID: concertID))
    await cache.remove(AppCacheResources.concertAlbumPhotos(concertID: concertID))
  }
}
