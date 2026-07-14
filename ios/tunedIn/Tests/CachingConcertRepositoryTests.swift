import Foundation
import Testing
@testable import tunedIn

struct CachingConcertRepositoryTests {
  @Test
  func firstPagesUseSnapshotsAndExplicitRefreshReplacesEachResource() async throws {
    let context = try await ConcertCacheTestHarness.makeRepository()

    try await ConcertCacheTestHarness.expectFirstPageValues(context.repository)
    try await ConcertCacheTestHarness.expectFirstPageValues(context.repository)
    await ConcertCacheTestHarness.expectReadCounts(context.remote, expected: 1)

    try await ConcertCacheTestHarness.expectRefreshedFirstPageValues(context.repository)
    await ConcertCacheTestHarness.expectReadCounts(context.remote, expected: 2)
    #expect(
      await context.cache.state(
        for: AppCacheResources.concertAlbumPolicy,
        freshness: .concertAlbumPolicy
      ) == .fresh
    )
  }

  @Test
  func archiveKeysNormalizeSearchAndSeparateFilterAndSortInputs() async throws {
    let context = try await ConcertCacheTestHarness.makeRepository()
    let repository = context.repository
    var first = ConcertCacheFixtures.query
    first.searchText = "  MITSKI   Live  "
    var equivalent = ConcertCacheFixtures.query
    equivalent.searchText = "mitski live"
    var differentYear = equivalent
    differentYear.year = 2025
    var differentSort = equivalent
    differentSort.sort = .artist

    _ = try await repository.profileConcertHistory(
      profileID: ConcertCacheFixtures.profileID,
      query: first,
      cursor: nil
    )
    _ = try await repository.profileConcertHistory(
      profileID: ConcertCacheFixtures.profileID,
      query: equivalent,
      cursor: nil
    )
    #expect(await context.remote.readCount(.archive) == 1)

    _ = try await repository.profileConcertHistory(
      profileID: ConcertCacheFixtures.profileID,
      query: differentYear,
      cursor: nil
    )
    _ = try await repository.profileConcertHistory(
      profileID: ConcertCacheFixtures.profileID,
      query: differentSort,
      cursor: nil
    )
    #expect(await context.remote.readCount(.archive) == 3)
  }

  @Test
  func laterPagesAlwaysUseTheServer() async throws {
    let context = try await ConcertCacheTestHarness.makeRepository()
    let repository = context.repository
    let preview = ConcertCacheFixtures.preview()
    let comment = ConcertCacheFixtures.comment()
    let photo = ConcertCacheFixtures.photo()
    let activity = ConcertCacheFixtures.activity()

    for _ in 0 ..< 2 {
      _ = try await repository.profileConcertHistory(
        profileID: ConcertCacheFixtures.profileID,
        query: ConcertCacheFixtures.query,
        cursor: ConcertHistoryCursor(preview: preview, sort: .newest)
      )
      _ = try await repository.comments(
        concertID: ConcertCacheFixtures.concertID,
        cursor: ConcertCommentCursor(createdAt: comment.createdAt, commentID: comment.id)
      )
      _ = try await repository.albumPhotos(
        concertID: ConcertCacheFixtures.concertID,
        cursor: ConcertAlbumPhotoCursor(attachedAt: photo.attachedAt, photoID: photo.id)
      )
      _ = try await repository.friendsActivity(
        cursor: FriendsActivityCursor(occurredAt: activity.occurredAt, eventID: activity.id)
      )
    }

    #expect(await context.remote.readCount(.archive) == 2)
    #expect(await context.remote.readCount(.comments) == 2)
    #expect(await context.remote.readCount(.album) == 2)
    #expect(await context.remote.readCount(.activity) == 2)
  }

  @Test
  func failedRefreshKeepsEveryPreviouslyUsableFirstPage() async throws {
    let context = try await ConcertCacheTestHarness.makeRepository()
    try await ConcertCacheTestHarness.prime(context.repository)
    await ConcertCacheTestHarness.failNextRefreshes(context.remote)

    await ConcertCacheTestHarness.expectRefreshFailures(context.repository)
    try await ConcertCacheTestHarness.expectFirstPageValues(context.repository)
  }

  @Test
  func realtimeInvalidatesVisibleConcertResourcesWithoutRefetching() async throws {
    let context = try await ConcertCacheTestHarness.makeRepository()
    let repository = context.repository
    try await ConcertCacheTestHarness.prime(repository)
    var changes = repository.observeConcert(id: ConcertCacheFixtures.concertID).makeAsyncIterator()

    await context.remote.emitConcertChange()
    _ = await changes.next()

    for read in ConcertRepositoryRead.permissionSensitiveReads {
      #expect(await context.remote.readCount(read) == 1)
    }
    #expect(await ConcertCacheTestHarness.state(.archive, cache: context.cache) == .invalidated)
    #expect(await ConcertCacheTestHarness.state(.detail, cache: context.cache) == .invalidated)
    #expect(await ConcertCacheTestHarness.state(.comments, cache: context.cache) == .invalidated)
    #expect(await ConcertCacheTestHarness.state(.album, cache: context.cache) == .invalidated)
    #expect(await ConcertCacheTestHarness.state(.activity, cache: context.cache) == .invalidated)
  }

  @Test
  func permissionLossPurgesConcertAndFeedSnapshots() async throws {
    let context = try await ConcertCacheTestHarness.makeRepository()
    let repository = context.repository
    try await ConcertCacheTestHarness.prime(repository)
    await context.remote.failNextRead(.detail, with: .permissionDenied)

    await #expect(throws: AppFailure.self) {
      _ = try await repository.fetchConcertDetail(
        id: ConcertCacheFixtures.concertID,
        viewerID: ConcertCacheFixtures.viewerID,
        policy: .refresh
      )
    }

    #expect(await ConcertCacheTestHarness.state(.archive, cache: context.cache) == .missing)
    #expect(await ConcertCacheTestHarness.state(.detail, cache: context.cache) == .missing)
    #expect(await ConcertCacheTestHarness.state(.comments, cache: context.cache) == .missing)
    #expect(await ConcertCacheTestHarness.state(.album, cache: context.cache) == .missing)
    #expect(await ConcertCacheTestHarness.state(.activity, cache: context.cache) == .missing)
  }

  @Test
  func accountTransitionsNeverReuseConcertSnapshots() async throws {
    let context = try await ConcertCacheTestHarness.makeRepository()
    let repository = context.repository
    _ = try await repository.fetchConcertDetail(
      id: ConcertCacheFixtures.concertID,
      viewerID: ConcertCacheFixtures.viewerID
    )
    await context.cache.transition(to: ConcertCacheFixtures.otherViewerID)
    _ = try await repository.fetchConcertDetail(
      id: ConcertCacheFixtures.concertID,
      viewerID: ConcertCacheFixtures.otherViewerID
    )

    #expect(await context.remote.readCount(.detail) == 2)
  }

}
