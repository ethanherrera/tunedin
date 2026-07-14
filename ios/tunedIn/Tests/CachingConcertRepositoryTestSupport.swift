import Foundation
@testable import tunedIn

enum ConcertRepositoryRead: Hashable, Sendable {
  case activity
  case archive
  case detail
  case comments
  case album
  case policy
}

extension ConcertRepositoryRead {
  static let allCacheableReads: [Self] = [.activity, .archive, .detail, .comments, .album, .policy]
  static let permissionSensitiveReads: [Self] = [.activity, .archive, .detail, .comments, .album]
}

enum ConcertMutationScenario: CaseIterable, Sendable {
  case createConcert
  case updateConcert
  case setConcertPhoto
  case removeConcertPhoto
  case reserveAlbumPhoto
  case uploadAlbumPhoto
  case updateAlbumCaption
  case deleteAlbumPhoto
  case tagCollaborator
  case removeCollaborator
  case transferOwnership
  case deleteConcert
  case createComment
  case updateComment
  case deleteComment
}

actor ConcertCacheRepositorySpy: ConcertRepository {
  private let concertChanges = ConcertTestChangeStream()
  private let activityChanges = ConcertTestChangeStream()
  private var readAttempts: [ConcertRepositoryRead: Int] = [:]
  private var successfulReads: [ConcertRepositoryRead: Int] = [:]
  private var readFailures: [ConcertRepositoryRead: AppFailure] = [:]
  private var nextMutationFailure: AppFailure?
  private(set) var mutations: [ConcertMutationScenario] = []

  var activityResponses = [[ConcertCacheFixtures.activity()], [ConcertCacheFixtures.activity(version: 2)]]
  var archiveResponses = [[ConcertCacheFixtures.preview()], [ConcertCacheFixtures.preview(version: 2)]]
  var detailResponses = [ConcertCacheFixtures.detail(), ConcertCacheFixtures.detail(version: 2)]
  var commentResponses = [[ConcertCacheFixtures.comment()], [
    ConcertCacheFixtures.comment(body: "Updated from server")
  ]]
  var albumResponses = [[ConcertCacheFixtures.photo()], [
    ConcertCacheFixtures.photo(caption: "Updated from server", version: 2)
  ]]
  var policyResponses = [ConcertCacheFixtures.policy]

  func readCount(_ read: ConcertRepositoryRead) -> Int {
    readAttempts[read, default: 0]
  }

  func failNextRead(_ read: ConcertRepositoryRead, with failure: AppFailure) {
    readFailures[read] = failure
  }

  func failNextMutation(with failure: AppFailure) {
    nextMutationFailure = failure
  }

  func emitConcertChange() {
    concertChanges.send()
  }

  func emitActivityChange() {
    activityChanges.send()
  }

  func createPrivateConcert(_: ConcertCreationInput) async throws -> Concert {
    try record(.createConcert)
    return ConcertCacheFixtures.concert(version: 2)
  }

  func updateConcert(_: ConcertUpdateInput) async throws -> Concert {
    try record(.updateConcert)
    return ConcertCacheFixtures.concert(version: 2)
  }

  func setConcertPhoto(_: Data, concertID _: UUID) async throws -> Concert {
    try record(.setConcertPhoto)
    return ConcertCacheFixtures.concert(version: 2)
  }

  func removeConcertPhoto(concertID _: UUID) async throws -> Concert {
    try record(.removeConcertPhoto)
    return ConcertCacheFixtures.concert(version: 2)
  }

  func concertPhotoURL(concertID _: UUID, objectPath _: String, version _: Int64) async throws -> URL {
    URL(string: "https://example.com/concert.jpg")!
  }

  func albumPolicy() async throws -> ConcertAlbumPolicy {
    try response(.policy, from: policyResponses)
  }

  func reserveAlbumPhoto(concertID: UUID, photoID: UUID) async throws -> ConcertPhotoReservation {
    try record(.reserveAlbumPhoto)
    return ConcertPhotoReservation(
      photoID: photoID,
      concertID: concertID,
      objectPath: "concerts/album/reserved.jpg",
      expiresAt: Date(timeIntervalSince1970: 1_000)
    )
  }

  func uploadReservedAlbumPhoto(
    _: Data,
    reservation _: ConcertPhotoReservation
  ) async throws -> ConcertAlbumPhoto {
    try record(.uploadAlbumPhoto)
    return ConcertCacheFixtures.photo(
      id: UUID(uuidString: "44000000-0000-0000-0000-000000000002")!,
      caption: "New photo"
    )
  }

  func albumPhotos(concertID _: UUID, cursor _: ConcertAlbumPhotoCursor?) async throws -> [ConcertAlbumPhoto] {
    try response(.album, from: albumResponses)
  }

  func albumPhotoURL(photoID _: UUID, objectPath _: String, version _: Int64) async throws -> URL {
    URL(string: "https://example.com/album.jpg")!
  }

  func updateAlbumPhotoCaption(photoID _: UUID, caption _: String?) async throws -> ConcertAlbumPhoto {
    try record(.updateAlbumCaption)
    return ConcertCacheFixtures.photo(caption: "Changed caption", version: 2)
  }

  func deleteAlbumPhoto(photoID _: UUID) async throws {
    try record(.deleteAlbumPhoto)
  }

  func tagCollaborator(concertID _: UUID, profileID _: UUID, expectedVersion _: Int64) async throws -> Concert {
    try record(.tagCollaborator)
    return ConcertCacheFixtures.concert(version: 2)
  }

  func removeCollaborator(
    concertID _: UUID,
    profileID _: UUID,
    expectedVersion _: Int64
  ) async throws -> Concert {
    try record(.removeCollaborator)
    return ConcertCacheFixtures.concert(version: 2)
  }

  func transferOwnership(
    concertID _: UUID,
    newOwnerID _: UUID,
    expectedVersion _: Int64
  ) async throws -> Concert {
    try record(.transferOwnership)
    return ConcertCacheFixtures.concert(version: 2)
  }

  func deleteConcert(id _: UUID) async throws {
    try record(.deleteConcert)
  }

  func collaborators(concertID _: UUID) async throws -> [ConcertCollaborator] {
    []
  }

  func comments(concertID _: UUID, cursor _: ConcertCommentCursor?) async throws -> [ConcertComment] {
    try response(.comments, from: commentResponses)
  }

  func createComment(concertID _: UUID, body _: String) async throws -> ConcertComment {
    try record(.createComment)
    return ConcertCacheFixtures.comment(
      id: UUID(uuidString: "43000000-0000-0000-0000-000000000002")!,
      body: "New comment"
    )
  }

  func updateComment(commentID _: UUID, body _: String) async throws -> ConcertComment {
    try record(.updateComment)
    return ConcertCacheFixtures.comment(body: "Changed comment")
  }

  func deleteComment(commentID _: UUID) async throws {
    try record(.deleteComment)
  }

  func friendsActivity(cursor _: FriendsActivityCursor?) async throws -> [FriendActivity] {
    try response(.activity, from: activityResponses)
  }

  func profileConcertHistory(
    profileID _: UUID,
    query _: ConcertHistoryQuery,
    cursor _: ConcertHistoryCursor?
  ) async throws -> [ConcertPreview] {
    try response(.archive, from: archiveResponses)
  }

  func fetchConcertDetail(id _: UUID, viewerID _: UUID) async throws -> ConcertDetail {
    try response(.detail, from: detailResponses)
  }

  nonisolated func observeConcert(id _: UUID) -> AsyncStream<Void> {
    concertChanges.stream
  }

  nonisolated func observeFriendsActivity() -> AsyncStream<Void> {
    activityChanges.stream
  }

  private func response<Value>(
    _ read: ConcertRepositoryRead,
    from responses: [Value]
  ) throws -> Value {
    readAttempts[read, default: 0] += 1
    if let failure = readFailures.removeValue(forKey: read) {
      throw failure
    }
    let index = successfulReads[read, default: 0]
    successfulReads[read] = index + 1
    return responses[min(index, responses.count - 1)]
  }

  private func record(_ mutation: ConcertMutationScenario) throws {
    if let failure = nextMutationFailure {
      nextMutationFailure = nil
      throw failure
    }
    mutations.append(mutation)
  }
}

final class ConcertTestChangeStream: @unchecked Sendable {
  let stream: AsyncStream<Void>
  private let continuation: AsyncStream<Void>.Continuation

  init() {
    let pair = AsyncStream<Void>.makeStream()
    stream = pair.stream
    continuation = pair.continuation
  }

  func send() {
    continuation.yield()
  }
}

struct ConcertCacheTestContext {
  let repository: CachingConcertRepository
  let remote: ConcertCacheRepositorySpy
  let cache: AppDataCache
}

enum ConcertCacheTestHarness {
  static func makeRepository() async throws -> ConcertCacheTestContext {
    let remote = ConcertCacheRepositorySpy()
    let cache = try AppDataCache.inMemory()
    await cache.transition(to: ConcertCacheFixtures.viewerID)
    return ConcertCacheTestContext(
      repository: CachingConcertRepository(remote: remote, cache: cache),
      remote: remote,
      cache: cache
    )
  }

  static func prime(_ repository: CachingConcertRepository) async throws {
    _ = try await repository.friendsActivity(cursor: nil)
    _ = try await repository.profileConcertHistory(
      profileID: ConcertCacheFixtures.profileID,
      query: ConcertCacheFixtures.query,
      cursor: nil
    )
    _ = try await repository.fetchConcertDetail(
      id: ConcertCacheFixtures.concertID,
      viewerID: ConcertCacheFixtures.viewerID
    )
    _ = try await repository.comments(concertID: ConcertCacheFixtures.concertID, cursor: nil)
    _ = try await repository.albumPhotos(concertID: ConcertCacheFixtures.concertID, cursor: nil)
  }

  static func state(
    _ read: ConcertRepositoryRead,
    cache: AppDataCache
  ) async -> AppCacheEntryState {
    switch read {
    case .activity:
      await cache.state(for: AppCacheResources.friendsActivity, freshness: .friendsActivity)
    case .archive:
      await cache.state(
        for: AppCacheResources.concertArchive(
          profileID: ConcertCacheFixtures.profileID,
          query: ConcertCacheFixtures.query
        ),
        freshness: .concertArchive
      )
    case .detail:
      await cache.state(
        for: AppCacheResources.concertDetail(
          concertID: ConcertCacheFixtures.concertID,
          viewerID: ConcertCacheFixtures.viewerID
        ),
        freshness: .concertDetail
      )
    case .comments:
      await cache.state(
        for: AppCacheResources.concertComments(concertID: ConcertCacheFixtures.concertID),
        freshness: .concertComments
      )
    case .album:
      await cache.state(
        for: AppCacheResources.concertAlbumPhotos(concertID: ConcertCacheFixtures.concertID),
        freshness: .concertAlbum
      )
    case .policy:
      await cache.state(for: AppCacheResources.concertAlbumPolicy, freshness: .concertAlbumPolicy)
    }
  }
}
