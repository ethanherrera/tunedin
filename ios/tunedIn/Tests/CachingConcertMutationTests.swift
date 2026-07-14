import Testing
@testable import tunedIn

struct CachingConcertMutationTests {
  @Test(arguments: ConcertMutationScenario.allCases)
  func successfulMutationsReconcileEveryDependentSnapshot(
    scenario: ConcertMutationScenario
  ) async throws {
    let context = try await ConcertCacheTestHarness.makeRepository()
    try await ConcertCacheTestHarness.prime(context.repository)

    try await ConcertMutationTestHarness.perform(scenario, repository: context.repository)

    #expect(await context.remote.mutations == [scenario])
    try await ConcertMutationTestHarness.assertReconciliation(
      scenario,
      context: context
    )
  }

  @Test
  func failedMutationLeavesEveryUsableSnapshotUntouched() async throws {
    let context = try await ConcertCacheTestHarness.makeRepository()
    try await ConcertCacheTestHarness.prime(context.repository)
    await context.remote.failNextMutation(with: .offline)

    await #expect(throws: AppFailure.self) {
      _ = try await context.repository.updateConcert(ConcertCacheFixtures.updateInput)
    }

    for read in ConcertRepositoryRead.permissionSensitiveReads {
      #expect(await ConcertCacheTestHarness.state(read, cache: context.cache) == .fresh)
    }
    #expect(
      try await context.repository.fetchConcertDetail(
        id: ConcertCacheFixtures.concertID,
        viewerID: ConcertCacheFixtures.viewerID
      ).concert.version == 1
    )
    #expect(await context.remote.mutations.isEmpty)
  }
}
