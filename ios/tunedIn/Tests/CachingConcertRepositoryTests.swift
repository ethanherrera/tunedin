import Foundation
import Testing
@testable import tunedIn

struct CachingConcertRepositoryTests {
  private let viewerID = UUID(uuidString: "30000000-0000-0000-0000-000000000003")!

  @Test
  func firstFeedPageIsCachedWhileLaterPagesStayAuthoritative() async throws {
    let firstPage = [activity(id: "31000000-0000-0000-0000-000000000001")]
    let remote = FeedConcertRepositorySpy(responses: [firstPage, []])
    let cache = try AppDataCache.inMemory()
    let repository = CachingConcertRepository(remote: remote, cache: cache)
    await cache.transition(to: viewerID)

    #expect(try await repository.friendsActivity(cursor: nil) == firstPage)
    #expect(try await repository.friendsActivity(cursor: nil) == firstPage)
    #expect(await remote.fetchCount == 1)

    let cursor = FriendsActivityCursor(
      occurredAt: firstPage[0].occurredAt,
      eventID: firstPage[0].id
    )
    #expect(try await repository.friendsActivity(cursor: cursor).isEmpty)
    #expect(await remote.fetchCount == 2)
  }

  @Test
  func realtimeMarksFeedStaleWithoutRefetchingUntilUserRefresh() async throws {
    let firstPage = [activity(id: "32000000-0000-0000-0000-000000000001")]
    let refreshed = [activity(id: "32000000-0000-0000-0000-000000000002")]
    let remote = FeedConcertRepositorySpy(responses: [firstPage, refreshed])
    let cache = try AppDataCache.inMemory()
    let repository = CachingConcertRepository(remote: remote, cache: cache)
    await cache.transition(to: viewerID)

    #expect(try await repository.friendsActivity(cursor: nil) == firstPage)
    var changes = repository.observeFriendsActivity().makeAsyncIterator()
    await remote.emitActivityChange()
    _ = await changes.next()

    #expect(await remote.fetchCount == 1)
    #expect(
      await cache.state(for: AppCacheResources.friendsActivity, freshness: .friendsActivity)
        == .invalidated
    )
    #expect(try await repository.friendsActivity(cursor: nil) == firstPage)
    #expect(await remote.fetchCount == 1)

    #expect(
      try await repository.friendsActivity(cursor: nil, policy: .refresh) == refreshed
    )
    #expect(await remote.fetchCount == 2)
  }

  private func activity(id: String) -> FriendActivity {
    FriendActivity(
      id: UUID(uuidString: id)!,
      concertID: UUID(uuidString: "33000000-0000-0000-0000-000000000003")!,
      actorID: UUID(uuidString: "34000000-0000-0000-0000-000000000004")!,
      actorUsername: "friend",
      actorDisplayName: "A Friend",
      eventKind: .concertCreated,
      occurredAt: Date(timeIntervalSince1970: 100),
      primaryArtistName: "Artist",
      venueName: "Venue",
      concertDate: "2026-01-01"
    )
  }
}

private actor FeedConcertRepositorySpy: ConcertRepository {
  private let responses: [[FriendActivity]]
  private let changes = TestChangeStream()
  private var fetchIndex = 0

  init(responses: [[FriendActivity]]) {
    self.responses = responses
  }

  var fetchCount: Int {
    fetchIndex
  }

  func emitActivityChange() {
    changes.send()
  }

  func friendsActivity(cursor _: FriendsActivityCursor?) async throws -> [FriendActivity] {
    let response = responses[min(fetchIndex, responses.count - 1)]
    fetchIndex += 1
    return response
  }

  nonisolated func observeFriendsActivity() -> AsyncStream<Void> {
    changes.stream
  }

  nonisolated func observeConcert(id _: UUID) -> AsyncStream<Void> {
    AsyncStream { continuation in continuation.finish() }
  }

  func createPrivateConcert(_: ConcertCreationInput) async throws -> Concert {
    throw Failure.unimplemented
  }

  func updateConcert(_: ConcertUpdateInput) async throws -> Concert {
    throw Failure.unimplemented
  }

  func setConcertPhoto(_: Data, concertID _: UUID) async throws -> Concert {
    throw Failure.unimplemented
  }

  func removeConcertPhoto(concertID _: UUID) async throws -> Concert {
    throw Failure.unimplemented
  }

  func concertPhotoURL(concertID _: UUID, objectPath _: String, version _: Int64) async throws -> URL {
    throw Failure.unimplemented
  }

  func albumPolicy() async throws -> ConcertAlbumPolicy {
    throw Failure.unimplemented
  }

  func reserveAlbumPhoto(concertID _: UUID, photoID _: UUID) async throws -> ConcertPhotoReservation {
    throw Failure.unimplemented
  }

  func uploadReservedAlbumPhoto(
    _: Data,
    reservation _: ConcertPhotoReservation
  ) async throws -> ConcertAlbumPhoto {
    throw Failure.unimplemented
  }

  func albumPhotos(concertID _: UUID, cursor _: ConcertAlbumPhotoCursor?) async throws -> [ConcertAlbumPhoto] {
    throw Failure.unimplemented
  }

  func albumPhotoURL(photoID _: UUID, objectPath _: String, version _: Int64) async throws -> URL {
    throw Failure.unimplemented
  }

  func updateAlbumPhotoCaption(photoID _: UUID, caption _: String?) async throws -> ConcertAlbumPhoto {
    throw Failure.unimplemented
  }

  func deleteAlbumPhoto(photoID _: UUID) async throws {
    throw Failure.unimplemented
  }

  func tagCollaborator(concertID _: UUID, profileID _: UUID, expectedVersion _: Int64) async throws -> Concert {
    throw Failure.unimplemented
  }

  func removeCollaborator(
    concertID _: UUID,
    profileID _: UUID,
    expectedVersion _: Int64
  ) async throws -> Concert {
    throw Failure.unimplemented
  }

  func transferOwnership(
    concertID _: UUID,
    newOwnerID _: UUID,
    expectedVersion _: Int64
  ) async throws -> Concert {
    throw Failure.unimplemented
  }

  func deleteConcert(id _: UUID) async throws {
    throw Failure.unimplemented
  }

  func collaborators(concertID _: UUID) async throws -> [ConcertCollaborator] {
    throw Failure.unimplemented
  }

  func comments(concertID _: UUID, cursor _: ConcertCommentCursor?) async throws -> [ConcertComment] {
    throw Failure.unimplemented
  }

  func createComment(concertID _: UUID, body _: String) async throws -> ConcertComment {
    throw Failure.unimplemented
  }

  func updateComment(commentID _: UUID, body _: String) async throws -> ConcertComment {
    throw Failure.unimplemented
  }

  func deleteComment(commentID _: UUID) async throws {
    throw Failure.unimplemented
  }

  func profileConcertHistory(
    profileID _: UUID,
    query _: ConcertHistoryQuery,
    cursor _: ConcertHistoryCursor?
  ) async throws -> [ConcertPreview] {
    throw Failure.unimplemented
  }

  func fetchConcertDetail(id _: UUID, viewerID _: UUID) async throws -> ConcertDetail {
    throw Failure.unimplemented
  }

  enum Failure: Error {
    case unimplemented
  }
}

private final class TestChangeStream: @unchecked Sendable {
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
