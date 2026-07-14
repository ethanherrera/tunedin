import Testing
@testable import tunedIn

extension ConcertCacheTestHarness {
  static func expectFirstPageValues(
    _ repository: CachingConcertRepository
  ) async throws {
    #expect(try await repository.friendsActivity(cursor: nil) == [ConcertCacheFixtures.activity()])
    #expect(
      try await repository.profileConcertHistory(
        profileID: ConcertCacheFixtures.profileID,
        query: ConcertCacheFixtures.query,
        cursor: nil
      ) == [ConcertCacheFixtures.preview()]
    )
    #expect(
      try await repository.fetchConcertDetail(
        id: ConcertCacheFixtures.concertID,
        viewerID: ConcertCacheFixtures.viewerID
      ) == ConcertCacheFixtures.detail()
    )
    #expect(
      try await repository.comments(concertID: ConcertCacheFixtures.concertID, cursor: nil)
        == [ConcertCacheFixtures.comment()]
    )
    #expect(
      try await repository.albumPhotos(concertID: ConcertCacheFixtures.concertID, cursor: nil)
        == [ConcertCacheFixtures.photo()]
    )
    #expect(try await repository.albumPolicy() == ConcertCacheFixtures.policy)
  }

  static func expectRefreshedFirstPageValues(
    _ repository: CachingConcertRepository
  ) async throws {
    #expect(
      try await repository.friendsActivity(cursor: nil, policy: .refresh)
        == [ConcertCacheFixtures.activity(version: 2)]
    )
    #expect(
      try await repository.profileConcertHistory(
        profileID: ConcertCacheFixtures.profileID,
        query: ConcertCacheFixtures.query,
        cursor: nil,
        policy: .refresh
      ) == [ConcertCacheFixtures.preview(version: 2)]
    )
    #expect(
      try await repository.fetchConcertDetail(
        id: ConcertCacheFixtures.concertID,
        viewerID: ConcertCacheFixtures.viewerID,
        policy: .refresh
      ) == ConcertCacheFixtures.detail(version: 2)
    )
    #expect(
      try await repository.comments(
        concertID: ConcertCacheFixtures.concertID,
        cursor: nil,
        policy: .refresh
      ) == [ConcertCacheFixtures.comment(body: "Updated from server")]
    )
    #expect(
      try await repository.albumPhotos(
        concertID: ConcertCacheFixtures.concertID,
        cursor: nil,
        policy: .refresh
      ) == [ConcertCacheFixtures.photo(caption: "Updated from server", version: 2)]
    )
    #expect(try await repository.albumPolicy(policy: .refresh) == ConcertCacheFixtures.policy)
  }

  static func expectReadCounts(
    _ remote: ConcertCacheRepositorySpy,
    expected: Int
  ) async {
    for read in ConcertRepositoryRead.allCacheableReads {
      #expect(await remote.readCount(read) == expected)
    }
  }

  static func failNextRefreshes(_ remote: ConcertCacheRepositorySpy) async {
    await remote.failNextRead(.archive, with: .offline)
    await remote.failNextRead(.detail, with: .offline)
    await remote.failNextRead(.comments, with: .offline)
    await remote.failNextRead(.album, with: .offline)
  }

  static func expectRefreshFailures(
    _ repository: CachingConcertRepository
  ) async {
    await #expect(throws: AppFailure.self) {
      _ = try await repository.profileConcertHistory(
        profileID: ConcertCacheFixtures.profileID,
        query: ConcertCacheFixtures.query,
        cursor: nil,
        policy: .refresh
      )
    }
    await #expect(throws: AppFailure.self) {
      _ = try await repository.fetchConcertDetail(
        id: ConcertCacheFixtures.concertID,
        viewerID: ConcertCacheFixtures.viewerID,
        policy: .refresh
      )
    }
    await #expect(throws: AppFailure.self) {
      _ = try await repository.comments(
        concertID: ConcertCacheFixtures.concertID,
        cursor: nil,
        policy: .refresh
      )
    }
    await #expect(throws: AppFailure.self) {
      _ = try await repository.albumPhotos(
        concertID: ConcertCacheFixtures.concertID,
        cursor: nil,
        policy: .refresh
      )
    }
  }
}
