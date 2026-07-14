import Foundation
import Testing
@testable import tunedIn

struct CachingSocialRepositoryTests {
  private let viewerID = UUID(uuidString: "40000000-0000-0000-0000-000000000004")!
  private let secondViewerID = UUID(uuidString: "40000000-0000-0000-0000-000000000005")!

  @Test
  func persistentSocialReadsUseSnapshotsAndRefreshReplacesThem() async throws {
    let first = profile(displayName: "First")
    let refreshed = profile(displayName: "Refreshed")
    let remote = SocialRepositorySpy(
      profiles: [.success(first), .success(refreshed)],
      friends: [.success([first]), .success([refreshed])],
      incoming: [.success([first]), .success([refreshed])]
    )
    let cache = try AppDataCache.inMemory()
    let repository = CachingSocialRepository(remote: remote, cache: cache)
    await cache.transition(to: viewerID)

    #expect(try await repository.profile(username: "target") == first)
    #expect(try await repository.friends(username: "viewer") == [first])
    #expect(try await repository.incomingFriendRequests() == [first])

    await cache.clearMemory()
    #expect(try await repository.profile(username: "TARGET") == first)
    #expect(try await repository.friends(username: " VIEWER ") == [first])
    #expect(try await repository.incomingFriendRequests() == [first])
    #expect(await remote.readCounts == SocialReadCounts(profile: 1, friends: 1, incoming: 1, search: 0))

    #expect(try await repository.profile(username: "target", policy: .refresh) == refreshed)
    #expect(try await repository.friends(username: "viewer", policy: .refresh) == [refreshed])
    #expect(try await repository.incomingFriendRequests(policy: .refresh) == [refreshed])
    #expect(await remote.readCounts == SocialReadCounts(profile: 2, friends: 2, incoming: 2, search: 0))
  }

  @Test
  func failedRefreshPreservesTheLastUsableFriendsSnapshot() async throws {
    let first = profile(displayName: "First")
    let remote = SocialRepositorySpy(
      friends: [.success([first]), .failure(.unavailable)]
    )
    let cache = try AppDataCache.inMemory()
    let repository = CachingSocialRepository(remote: remote, cache: cache)
    await cache.transition(to: viewerID)

    #expect(try await repository.friends(username: "viewer") == [first])
    await #expect(throws: SocialRepositoryTestFailure.self) {
      try await repository.friends(username: "viewer", policy: .refresh)
    }
    #expect(try await repository.friends(username: "viewer") == [first])
    #expect(await remote.readCounts.friends == 2)
  }

  @Test
  func permissionDeniedRefreshPurgesAllPermissionSensitiveSnapshots() async throws {
    let target = profile(displayName: "Target")
    let remote = SocialRepositorySpy(
      profiles: [.success(target)],
      friends: [.success([target])],
      incoming: [.success([target])],
      searchResults: [target],
      deniesFriendRefresh: true
    )
    let cache = try AppDataCache.inMemory()
    let repository = CachingSocialRepository(remote: remote, cache: cache)
    await cache.transition(to: viewerID)

    _ = try await repository.profile(username: target.username)
    _ = try await repository.friends(username: "viewer")
    _ = try await repository.incomingFriendRequests()
    _ = try await repository.searchProfiles(usernamePrefix: "tar")
    try await cache.store(1, for: AppCacheResources.friendsActivity)

    await #expect(throws: AppFailure.permissionDenied) {
      try await repository.friends(username: "viewer", policy: .refresh)
    }

    #expect(
      await cache.state(
        for: AppCacheResources.socialProfile(username: target.username),
        freshness: .socialRelationship
      ) == .missing
    )
    #expect(
      await cache.state(
        for: AppCacheResources.socialFriends(username: "viewer"),
        freshness: .socialRelationship
      ) == .missing
    )
    #expect(
      await cache.state(
        for: AppCacheResources.incomingFriendRequests,
        freshness: .socialRelationship
      ) == .missing
    )
    #expect(
      await cache.state(
        for: AppCacheResources.friendsActivity,
        freshness: .friendsActivity
      ) == .missing
    )

    _ = try await repository.searchProfiles(usernamePrefix: "tar")
    #expect(await remote.readCounts.search == 2)
  }

  @Test
  func unavailableProfileResponsePurgesPreviouslyVisibleData() async throws {
    let target = profile(displayName: "Target")
    let remote = SocialRepositorySpy(
      profiles: [.success(target), .success(nil)],
      friends: [.success([target])]
    )
    let cache = try AppDataCache.inMemory()
    let repository = CachingSocialRepository(remote: remote, cache: cache)
    await cache.transition(to: viewerID)

    _ = try await repository.profile(username: target.username)
    _ = try await repository.friends(username: "viewer")
    try await cache.store(1, for: AppCacheResources.friendsActivity)

    #expect(try await repository.profile(username: target.username, policy: .refresh) == nil)
    #expect(
      await cache.state(
        for: AppCacheResources.socialProfile(username: target.username),
        freshness: .socialRelationship
      ) == .missing
    )
    #expect(
      await cache.state(
        for: AppCacheResources.socialFriends(username: "viewer"),
        freshness: .socialRelationship
      ) == .missing
    )
    #expect(
      await cache.state(
        for: AppCacheResources.friendsActivity,
        freshness: .friendsActivity
      ) == .missing
    )
  }

  @Test
  func normalizedSearchPrefixesReuseOnlyTheBoundedMemoryCache() async throws {
    let target = profile(displayName: "Target")
    let remote = SocialRepositorySpy(searchResults: [target])
    let cache = try AppDataCache.inMemory()
    let searchCache = SocialProfileSearchCache(capacity: 2)
    let repository = CachingSocialRepository(
      remote: remote,
      cache: cache,
      searchCache: searchCache
    )
    await cache.transition(to: viewerID)

    #expect(try await repository.searchProfiles(usernamePrefix: " TaR ") == [target])
    #expect(try await repository.searchProfiles(usernamePrefix: "tar") == [target])
    #expect(await remote.searchedPrefixes == ["tar"])

    _ = try await repository.searchProfiles(usernamePrefix: "other")
    _ = try await repository.searchProfiles(usernamePrefix: "tar")
    _ = try await repository.searchProfiles(usernamePrefix: "third")
    _ = try await repository.searchProfiles(usernamePrefix: "other")
    #expect(await remote.readCounts.search == 4)

    let relaunchedRepository = CachingSocialRepository(
      remote: remote,
      cache: cache,
      searchCache: SocialProfileSearchCache(capacity: 2)
    )
    #expect(try await relaunchedRepository.searchProfiles(usernamePrefix: "tar") == [target])
    #expect(await remote.readCounts.search == 5)
  }

  @Test
  func searchCacheIsIsolatedAcrossAccountTransitions() async throws {
    let target = profile(displayName: "Target")
    let remote = SocialRepositorySpy(searchResults: [target])
    let cache = try AppDataCache.inMemory()
    let repository = CachingSocialRepository(remote: remote, cache: cache)

    await cache.transition(to: viewerID)
    _ = try await repository.searchProfiles(usernamePrefix: "target")
    _ = try await repository.searchProfiles(usernamePrefix: "target")
    await cache.transition(to: secondViewerID)
    _ = try await repository.searchProfiles(usernamePrefix: "target")

    #expect(await remote.readCounts.search == 2)
  }

  @Test(arguments: SocialMutation.allCases)
  func successfulRelationshipMutationReconcilesEveryDependentCache(
    mutation: SocialMutation
  ) async throws {
    let target = profile(displayName: "Target")
    let remote = SocialRepositorySpy(
      profiles: [.success(target)],
      friends: [.success([target])],
      incoming: [.success([target])],
      searchResults: [target]
    )
    let cache = try AppDataCache.inMemory()
    let repository = CachingSocialRepository(remote: remote, cache: cache)
    await cache.transition(to: viewerID)

    _ = try await repository.profile(username: target.username)
    _ = try await repository.friends(username: "viewer")
    _ = try await repository.incomingFriendRequests()
    _ = try await repository.searchProfiles(usernamePrefix: "tar")
    try await cache.store(1, for: AppCacheResources.friendsActivity)
    await cache.clearMemory()

    try await mutation.perform(on: repository, profileID: target.id)

    #expect(await remote.mutations == [mutation])
    #expect(
      await cache.state(
        for: AppCacheResources.socialProfile(username: target.username),
        freshness: .socialRelationship
      ) == .missing
    )
    #expect(
      await cache.state(
        for: AppCacheResources.socialFriends(username: "viewer"),
        freshness: .socialRelationship
      ) == .missing
    )
    #expect(
      await cache.state(
        for: AppCacheResources.incomingFriendRequests,
        freshness: .socialRelationship
      ) == .missing
    )
    #expect(
      await cache.state(
        for: AppCacheResources.friendsActivity,
        freshness: .friendsActivity
      ) == mutation.expectedFeedState
    )

    _ = try await repository.searchProfiles(usernamePrefix: "tar")
    #expect(await remote.readCounts.search == 2)
  }

  @Test
  func failedMutationLeavesUsableSnapshotsUntouched() async throws {
    let target = profile(displayName: "Target")
    let remote = SocialRepositorySpy(
      profiles: [.success(target)],
      searchResults: [target],
      mutationFailure: .unavailable
    )
    let cache = try AppDataCache.inMemory()
    let repository = CachingSocialRepository(remote: remote, cache: cache)
    await cache.transition(to: viewerID)

    _ = try await repository.profile(username: target.username)
    _ = try await repository.searchProfiles(usernamePrefix: "tar")
    await #expect(throws: SocialRepositoryTestFailure.self) {
      try await repository.block(target.id)
    }

    #expect(
      await cache.state(
        for: AppCacheResources.socialProfile(username: target.username),
        freshness: .socialRelationship
      ) == .fresh
    )
    _ = try await repository.searchProfiles(usernamePrefix: "tar")
    #expect(await remote.readCounts.search == 1)
  }

  private func profile(displayName: String) -> SocialProfile {
    SocialProfile(
      id: UUID(uuidString: "41000000-0000-0000-0000-000000000001")!,
      username: "target",
      displayName: displayName,
      relationship: .incoming,
      avatarObjectPath: "avatars/target/profile.jpg",
      avatarVersion: 2
    )
  }
}
