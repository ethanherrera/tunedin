import Foundation

protocol CacheAwareConcertRepository: ConcertRepository {
  func friendsActivity(
    cursor: FriendsActivityCursor?,
    policy: CacheReadPolicy
  ) async throws -> [FriendActivity]
}

extension ConcertRepository {
  func friendsActivity(
    cursor: FriendsActivityCursor?,
    policy: CacheReadPolicy
  ) async throws -> [FriendActivity] {
    if let repository = self as? any CacheAwareConcertRepository {
      return try await repository.friendsActivity(cursor: cursor, policy: policy)
    }
    return try await friendsActivity(cursor: cursor)
  }
}

struct CachingConcertRepository: CacheAwareConcertRepository {
  let remote: any ConcertRepository
  let cache: AppDataCache

  func createPrivateConcert(_ input: ConcertCreationInput) async throws -> Concert {
    try await remote.createPrivateConcert(input)
  }

  func updateConcert(_ input: ConcertUpdateInput) async throws -> Concert {
    try await remote.updateConcert(input)
  }

  func setConcertPhoto(_ jpegData: Data, concertID: UUID) async throws -> Concert {
    try await remote.setConcertPhoto(jpegData, concertID: concertID)
  }

  func removeConcertPhoto(concertID: UUID) async throws -> Concert {
    try await remote.removeConcertPhoto(concertID: concertID)
  }

  func concertPhotoURL(concertID: UUID, objectPath: String, version: Int64) async throws -> URL {
    try await remote.concertPhotoURL(
      concertID: concertID,
      objectPath: objectPath,
      version: version
    )
  }

  func albumPolicy() async throws -> ConcertAlbumPolicy {
    try await remote.albumPolicy()
  }

  func reserveAlbumPhoto(concertID: UUID, photoID: UUID) async throws -> ConcertPhotoReservation {
    try await remote.reserveAlbumPhoto(concertID: concertID, photoID: photoID)
  }

  func uploadReservedAlbumPhoto(
    _ jpegData: Data,
    reservation: ConcertPhotoReservation
  ) async throws -> ConcertAlbumPhoto {
    try await remote.uploadReservedAlbumPhoto(jpegData, reservation: reservation)
  }

  func albumPhotos(
    concertID: UUID,
    cursor: ConcertAlbumPhotoCursor?
  ) async throws -> [ConcertAlbumPhoto] {
    try await remote.albumPhotos(concertID: concertID, cursor: cursor)
  }

  func albumPhotoURL(photoID: UUID, objectPath: String, version: Int64) async throws -> URL {
    try await remote.albumPhotoURL(photoID: photoID, objectPath: objectPath, version: version)
  }

  func updateAlbumPhotoCaption(photoID: UUID, caption: String?) async throws -> ConcertAlbumPhoto {
    try await remote.updateAlbumPhotoCaption(photoID: photoID, caption: caption)
  }

  func deleteAlbumPhoto(photoID: UUID) async throws {
    try await remote.deleteAlbumPhoto(photoID: photoID)
  }

  func tagCollaborator(
    concertID: UUID,
    profileID: UUID,
    expectedVersion: Int64
  ) async throws -> Concert {
    try await remote.tagCollaborator(
      concertID: concertID,
      profileID: profileID,
      expectedVersion: expectedVersion
    )
  }

  func removeCollaborator(
    concertID: UUID,
    profileID: UUID,
    expectedVersion: Int64
  ) async throws -> Concert {
    try await remote.removeCollaborator(
      concertID: concertID,
      profileID: profileID,
      expectedVersion: expectedVersion
    )
  }

  func transferOwnership(
    concertID: UUID,
    newOwnerID: UUID,
    expectedVersion: Int64
  ) async throws -> Concert {
    try await remote.transferOwnership(
      concertID: concertID,
      newOwnerID: newOwnerID,
      expectedVersion: expectedVersion
    )
  }

  func deleteConcert(id: UUID) async throws {
    try await remote.deleteConcert(id: id)
  }

  func collaborators(concertID: UUID) async throws -> [ConcertCollaborator] {
    try await remote.collaborators(concertID: concertID)
  }

  func comments(
    concertID: UUID,
    cursor: ConcertCommentCursor?
  ) async throws -> [ConcertComment] {
    try await remote.comments(concertID: concertID, cursor: cursor)
  }

  func createComment(concertID: UUID, body: String) async throws -> ConcertComment {
    try await remote.createComment(concertID: concertID, body: body)
  }

  func updateComment(commentID: UUID, body: String) async throws -> ConcertComment {
    try await remote.updateComment(commentID: commentID, body: body)
  }

  func deleteComment(commentID: UUID) async throws {
    try await remote.deleteComment(commentID: commentID)
  }

  func friendsActivity(cursor: FriendsActivityCursor?) async throws -> [FriendActivity] {
    try await friendsActivity(cursor: cursor, policy: .automatic)
  }

  func friendsActivity(
    cursor: FriendsActivityCursor?,
    policy: CacheReadPolicy
  ) async throws -> [FriendActivity] {
    guard cursor == nil else {
      return try await remote.friendsActivity(cursor: cursor)
    }
    return try await cache.value(
      for: AppCacheResources.friendsActivity,
      freshness: .friendsActivity,
      policy: policy
    ) {
      try await remote.friendsActivity(cursor: nil)
    }
  }

  func profileConcertHistory(
    profileID: UUID,
    query: ConcertHistoryQuery,
    cursor: ConcertHistoryCursor?
  ) async throws -> [ConcertPreview] {
    try await remote.profileConcertHistory(
      profileID: profileID,
      query: query,
      cursor: cursor
    )
  }

  func fetchConcertDetail(id: UUID, viewerID: UUID) async throws -> ConcertDetail {
    try await remote.fetchConcertDetail(id: id, viewerID: viewerID)
  }

  func observeConcert(id: UUID) -> AsyncStream<Void> {
    remote.observeConcert(id: id)
  }

  func observeFriendsActivity() -> AsyncStream<Void> {
    let upstream = remote.observeFriendsActivity()
    let cache = cache
    return AsyncStream { continuation in
      let task = Task {
        for await _ in upstream {
          guard !Task.isCancelled else { break }
          await cache.invalidate(AppCacheResources.friendsActivity)
          continuation.yield()
        }
        continuation.finish()
      }
      continuation.onTermination = { _ in
        task.cancel()
      }
    }
  }
}
