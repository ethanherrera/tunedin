import Foundation

protocol CacheAwareConcertRepository: ConcertRepository {
  func albumPolicy(policy: CacheReadPolicy) async throws -> ConcertAlbumPolicy
  func albumPhotos(
    concertID: UUID,
    cursor: ConcertAlbumPhotoCursor?,
    policy: CacheReadPolicy
  ) async throws -> [ConcertAlbumPhoto]
  func comments(
    concertID: UUID,
    cursor: ConcertCommentCursor?,
    policy: CacheReadPolicy
  ) async throws -> [ConcertComment]
  func friendsActivity(
    cursor: FriendsActivityCursor?,
    policy: CacheReadPolicy
  ) async throws -> [FriendActivity]
  func profileConcertHistory(
    profileID: UUID,
    query: ConcertHistoryQuery,
    cursor: ConcertHistoryCursor?,
    policy: CacheReadPolicy
  ) async throws -> [ConcertPreview]
  func fetchConcertDetail(
    id: UUID,
    viewerID: UUID,
    policy: CacheReadPolicy
  ) async throws -> ConcertDetail
  func deleteComment(commentID: UUID, concertID: UUID) async throws
  func deleteAlbumPhoto(photoID: UUID, concertID: UUID) async throws
}

extension ConcertRepository {
  func albumPolicy(policy: CacheReadPolicy) async throws -> ConcertAlbumPolicy {
    if let repository = self as? any CacheAwareConcertRepository {
      return try await repository.albumPolicy(policy: policy)
    }
    return try await albumPolicy()
  }

  func albumPhotos(
    concertID: UUID,
    cursor: ConcertAlbumPhotoCursor?,
    policy: CacheReadPolicy
  ) async throws -> [ConcertAlbumPhoto] {
    if let repository = self as? any CacheAwareConcertRepository {
      return try await repository.albumPhotos(
        concertID: concertID,
        cursor: cursor,
        policy: policy
      )
    }
    return try await albumPhotos(concertID: concertID, cursor: cursor)
  }

  func comments(
    concertID: UUID,
    cursor: ConcertCommentCursor?,
    policy: CacheReadPolicy
  ) async throws -> [ConcertComment] {
    if let repository = self as? any CacheAwareConcertRepository {
      return try await repository.comments(concertID: concertID, cursor: cursor, policy: policy)
    }
    return try await comments(concertID: concertID, cursor: cursor)
  }

  func friendsActivity(
    cursor: FriendsActivityCursor?,
    policy: CacheReadPolicy
  ) async throws -> [FriendActivity] {
    if let repository = self as? any CacheAwareConcertRepository {
      return try await repository.friendsActivity(cursor: cursor, policy: policy)
    }
    return try await friendsActivity(cursor: cursor)
  }

  func profileConcertHistory(
    profileID: UUID,
    query: ConcertHistoryQuery,
    cursor: ConcertHistoryCursor?,
    policy: CacheReadPolicy
  ) async throws -> [ConcertPreview] {
    if let repository = self as? any CacheAwareConcertRepository {
      return try await repository.profileConcertHistory(
        profileID: profileID,
        query: query,
        cursor: cursor,
        policy: policy
      )
    }
    return try await profileConcertHistory(profileID: profileID, query: query, cursor: cursor)
  }

  func fetchConcertDetail(
    id: UUID,
    viewerID: UUID,
    policy: CacheReadPolicy
  ) async throws -> ConcertDetail {
    if let repository = self as? any CacheAwareConcertRepository {
      return try await repository.fetchConcertDetail(id: id, viewerID: viewerID, policy: policy)
    }
    return try await fetchConcertDetail(id: id, viewerID: viewerID)
  }

  func deleteComment(commentID: UUID, concertID: UUID) async throws {
    if let repository = self as? any CacheAwareConcertRepository {
      return try await repository.deleteComment(commentID: commentID, concertID: concertID)
    }
    return try await deleteComment(commentID: commentID)
  }

  func deleteAlbumPhoto(photoID: UUID, concertID: UUID) async throws {
    if let repository = self as? any CacheAwareConcertRepository {
      return try await repository.deleteAlbumPhoto(photoID: photoID, concertID: concertID)
    }
    return try await deleteAlbumPhoto(photoID: photoID)
  }
}

struct CachingConcertRepository: CacheAwareConcertRepository {
  let remote: any ConcertRepository
  let cache: AppDataCache

  func albumPolicy() async throws -> ConcertAlbumPolicy {
    try await albumPolicy(policy: .automatic)
  }

  func albumPolicy(policy: CacheReadPolicy) async throws -> ConcertAlbumPolicy {
    try await cache.value(
      for: AppCacheResources.concertAlbumPolicy,
      freshness: .concertAlbumPolicy,
      policy: policy
    ) {
      try await remote.albumPolicy()
    }
  }

  func albumPhotos(
    concertID: UUID,
    cursor: ConcertAlbumPhotoCursor?
  ) async throws -> [ConcertAlbumPhoto] {
    try await albumPhotos(concertID: concertID, cursor: cursor, policy: .automatic)
  }

  func albumPhotos(
    concertID: UUID,
    cursor: ConcertAlbumPhotoCursor?,
    policy: CacheReadPolicy
  ) async throws -> [ConcertAlbumPhoto] {
    try await protectingPermissionCache {
      guard cursor == nil else {
        return try await remote.albumPhotos(concertID: concertID, cursor: cursor)
      }
      return try await cache.value(
        for: AppCacheResources.concertAlbumPhotos(concertID: concertID),
        freshness: .concertAlbum,
        policy: policy
      ) {
        try await remote.albumPhotos(concertID: concertID, cursor: nil)
      }
    }
  }

  func collaborators(concertID: UUID) async throws -> [ConcertCollaborator] {
    try await protectingPermissionCache {
      try await remote.collaborators(concertID: concertID)
    }
  }

  func comments(
    concertID: UUID,
    cursor: ConcertCommentCursor?
  ) async throws -> [ConcertComment] {
    try await comments(concertID: concertID, cursor: cursor, policy: .automatic)
  }

  func comments(
    concertID: UUID,
    cursor: ConcertCommentCursor?,
    policy: CacheReadPolicy
  ) async throws -> [ConcertComment] {
    try await protectingPermissionCache {
      guard cursor == nil else {
        return try await remote.comments(concertID: concertID, cursor: cursor)
      }
      return try await cache.value(
        for: AppCacheResources.concertComments(concertID: concertID),
        freshness: .concertComments,
        policy: policy
      ) {
        try await remote.comments(concertID: concertID, cursor: nil)
      }
    }
  }

  func friendsActivity(cursor: FriendsActivityCursor?) async throws -> [FriendActivity] {
    try await friendsActivity(cursor: cursor, policy: .automatic)
  }

  func friendsActivity(
    cursor: FriendsActivityCursor?,
    policy: CacheReadPolicy
  ) async throws -> [FriendActivity] {
    try await protectingPermissionCache {
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
  }

  func profileConcertHistory(
    profileID: UUID,
    query: ConcertHistoryQuery,
    cursor: ConcertHistoryCursor?
  ) async throws -> [ConcertPreview] {
    try await profileConcertHistory(
      profileID: profileID,
      query: query,
      cursor: cursor,
      policy: .automatic
    )
  }

  func profileConcertHistory(
    profileID: UUID,
    query: ConcertHistoryQuery,
    cursor: ConcertHistoryCursor?,
    policy: CacheReadPolicy
  ) async throws -> [ConcertPreview] {
    try await protectingPermissionCache {
      guard cursor == nil else {
        return try await remote.profileConcertHistory(
          profileID: profileID,
          query: query,
          cursor: cursor
        )
      }
      return try await cache.value(
        for: AppCacheResources.concertArchive(profileID: profileID, query: query),
        freshness: .concertArchive,
        policy: policy
      ) {
        try await remote.profileConcertHistory(profileID: profileID, query: query, cursor: nil)
      }
    }
  }

  func fetchConcertDetail(id: UUID, viewerID: UUID) async throws -> ConcertDetail {
    try await fetchConcertDetail(id: id, viewerID: viewerID, policy: .automatic)
  }

  func fetchConcertDetail(
    id: UUID,
    viewerID: UUID,
    policy: CacheReadPolicy
  ) async throws -> ConcertDetail {
    try await protectingPermissionCache {
      try await cache.value(
        for: AppCacheResources.concertDetail(concertID: id, viewerID: viewerID),
        freshness: .concertDetail,
        policy: policy
      ) {
        try await remote.fetchConcertDetail(id: id, viewerID: viewerID)
      }
    }
  }

  func concertPhotoURL(concertID: UUID, objectPath: String, version: Int64) async throws -> URL {
    try await protectingPermissionCache {
      try await remote.concertPhotoURL(
        concertID: concertID,
        objectPath: objectPath,
        version: version
      )
    }
  }

  func albumPhotoURL(photoID: UUID, objectPath: String, version: Int64) async throws -> URL {
    try await protectingPermissionCache {
      try await remote.albumPhotoURL(photoID: photoID, objectPath: objectPath, version: version)
    }
  }

  func observeConcert(id: UUID) -> AsyncStream<Void> {
    let upstream = remote.observeConcert(id: id)
    let cache = cache
    return AsyncStream { continuation in
      let task = Task {
        for await _ in upstream {
          guard !Task.isCancelled else { break }
          await Self.markRemoteChanges(concertID: id, cache: cache)
          continuation.yield()
        }
        continuation.finish()
      }
      continuation.onTermination = { _ in task.cancel() }
    }
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
      continuation.onTermination = { _ in task.cancel() }
    }
  }

  func protectingPermissionCache<Value: Sendable>(
    _ operation: @escaping @Sendable () async throws -> Value
  ) async throws -> Value {
    do {
      return try await operation()
    } catch {
      await purgeIfAccessWasLost(error)
      throw error
    }
  }

  func purgeIfAccessWasLost(_ error: any Error) async {
    let failure = AppFailure(error)
    guard failure == .permissionDenied || failure == .unavailable else { return }
    await cache.remove(resourcesNamed: AppCacheResources.permissionSensitiveConcertNames)
    await cache.remove(AppCacheResources.friendsActivity)
  }

  func invalidateArchiveAndFeed() async {
    await cache.invalidate(resourcesNamed: AppCacheResources.concertArchiveNames)
    await cache.invalidate(AppCacheResources.friendsActivity)
  }

  func invalidateDetail(concertID: UUID) async {
    guard let scope = await cache.currentScope() else { return }
    await cache.invalidate(
      AppCacheResources.concertDetail(concertID: concertID, viewerID: scope.viewerID)
    )
  }

  private static func markRemoteChanges(concertID: UUID, cache: AppDataCache) async {
    if let scope = await cache.currentScope() {
      await cache.invalidate(
        AppCacheResources.concertDetail(concertID: concertID, viewerID: scope.viewerID)
      )
    }
    await cache.invalidate(AppCacheResources.concertComments(concertID: concertID))
    await cache.invalidate(AppCacheResources.concertAlbumPhotos(concertID: concertID))
    await cache.invalidate(resourcesNamed: AppCacheResources.concertArchiveNames)
    await cache.invalidate(AppCacheResources.friendsActivity)
  }
}
