import Foundation

protocol CacheAwareSocialRepository: SocialRepository {
  func searchProfiles(
    usernamePrefix: String,
    policy: CacheReadPolicy
  ) async throws -> [SocialProfile]
  func profile(username: String, policy: CacheReadPolicy) async throws -> SocialProfile?
  func friends(username: String, policy: CacheReadPolicy) async throws -> [SocialProfile]
  func incomingFriendRequests(policy: CacheReadPolicy) async throws -> [SocialProfile]
}

extension SocialRepository {
  func searchProfiles(
    usernamePrefix: String,
    policy: CacheReadPolicy
  ) async throws -> [SocialProfile] {
    if let repository = self as? any CacheAwareSocialRepository {
      return try await repository.searchProfiles(usernamePrefix: usernamePrefix, policy: policy)
    }
    return try await searchProfiles(usernamePrefix: usernamePrefix)
  }

  func profile(username: String, policy: CacheReadPolicy) async throws -> SocialProfile? {
    if let repository = self as? any CacheAwareSocialRepository {
      return try await repository.profile(username: username, policy: policy)
    }
    return try await profile(username: username)
  }

  func friends(username: String, policy: CacheReadPolicy) async throws -> [SocialProfile] {
    if let repository = self as? any CacheAwareSocialRepository {
      return try await repository.friends(username: username, policy: policy)
    }
    return try await friends(username: username)
  }

  func incomingFriendRequests(policy: CacheReadPolicy) async throws -> [SocialProfile] {
    if let repository = self as? any CacheAwareSocialRepository {
      return try await repository.incomingFriendRequests(policy: policy)
    }
    return try await incomingFriendRequests()
  }
}

struct CachingSocialRepository: CacheAwareSocialRepository {
  private enum MutationImpact {
    case relationshipOnly
    case grantsAccess
    case revokesAccess
  }

  let remote: any SocialRepository
  let cache: AppDataCache
  let searchCache: SocialProfileSearchCache

  init(
    remote: any SocialRepository,
    cache: AppDataCache,
    searchCache: SocialProfileSearchCache = SocialProfileSearchCache()
  ) {
    self.remote = remote
    self.cache = cache
    self.searchCache = searchCache
  }

  func searchProfiles(usernamePrefix: String) async throws -> [SocialProfile] {
    try await searchProfiles(usernamePrefix: usernamePrefix, policy: .automatic)
  }

  func searchProfiles(
    usernamePrefix: String,
    policy: CacheReadPolicy
  ) async throws -> [SocialProfile] {
    let normalizedPrefix = ProfileInput.normalizedUsername(usernamePrefix)
    guard !normalizedPrefix.isEmpty else { return [] }
    let scope = await cache.currentScope()
    do {
      return try await searchCache.value(
        scope: scope,
        normalizedPrefix: normalizedPrefix,
        policy: policy
      ) {
        try await remote.searchProfiles(usernamePrefix: normalizedPrefix)
      }
    } catch {
      await purgeIfAccessWasLost(error)
      throw error
    }
  }

  func profile(username: String) async throws -> SocialProfile? {
    try await profile(username: username, policy: .automatic)
  }

  func profile(username: String, policy: CacheReadPolicy) async throws -> SocialProfile? {
    let normalizedUsername = ProfileInput.normalizedUsername(username)
    guard !normalizedUsername.isEmpty else { return nil }
    do {
      let profile: SocialProfile? = try await cache.value(
        for: AppCacheResources.socialProfile(username: normalizedUsername),
        freshness: .socialRelationship,
        policy: policy
      ) {
        try await remote.profile(username: normalizedUsername)
      }
      if profile == nil || profile?.relationship == .unavailable {
        await purgePermissionSensitiveSnapshots()
      }
      return profile
    } catch {
      await purgeIfAccessWasLost(error)
      throw error
    }
  }

  func friends(username: String) async throws -> [SocialProfile] {
    try await friends(username: username, policy: .automatic)
  }

  func friends(username: String, policy: CacheReadPolicy) async throws -> [SocialProfile] {
    let normalizedUsername = ProfileInput.normalizedUsername(username)
    guard !normalizedUsername.isEmpty else { return [] }
    do {
      return try await cache.value(
        for: AppCacheResources.socialFriends(username: normalizedUsername),
        freshness: .socialRelationship,
        policy: policy
      ) {
        try await remote.friends(username: normalizedUsername)
      }
    } catch {
      await purgeIfAccessWasLost(error)
      throw error
    }
  }

  func incomingFriendRequests() async throws -> [SocialProfile] {
    try await incomingFriendRequests(policy: .automatic)
  }

  func incomingFriendRequests(policy: CacheReadPolicy) async throws -> [SocialProfile] {
    do {
      return try await cache.value(
        for: AppCacheResources.incomingFriendRequests,
        freshness: .socialRelationship,
        policy: policy
      ) {
        try await remote.incomingFriendRequests()
      }
    } catch {
      await purgeIfAccessWasLost(error)
      throw error
    }
  }

  func sendFriendRequest(to profileID: UUID) async throws {
    try await performMutation(impact: .relationshipOnly) {
      try await remote.sendFriendRequest(to: profileID)
    }
  }

  func acceptFriendRequest(from profileID: UUID) async throws {
    try await performMutation(impact: .grantsAccess) {
      try await remote.acceptFriendRequest(from: profileID)
    }
  }

  func declineFriendRequest(from profileID: UUID) async throws {
    try await performMutation(impact: .relationshipOnly) {
      try await remote.declineFriendRequest(from: profileID)
    }
  }

  func withdrawFriendRequest(to profileID: UUID) async throws {
    try await performMutation(impact: .relationshipOnly) {
      try await remote.withdrawFriendRequest(to: profileID)
    }
  }

  func removeFriend(_ profileID: UUID) async throws {
    try await performMutation(impact: .revokesAccess) {
      try await remote.removeFriend(profileID)
    }
  }

  func block(_ profileID: UUID) async throws {
    try await performMutation(impact: .revokesAccess) {
      try await remote.block(profileID)
    }
  }

  func unblock(_ profileID: UUID) async throws {
    try await performMutation(impact: .relationshipOnly) {
      try await remote.unblock(profileID)
    }
  }

  private func performMutation(
    impact: MutationImpact,
    operation: @escaping @Sendable () async throws -> Void
  ) async throws {
    do {
      try await operation()
      await reconcileMutation(impact: impact)
    } catch {
      await purgeIfAccessWasLost(error)
      throw error
    }
  }

  private func reconcileMutation(impact: MutationImpact) async {
    let scope = await cache.currentScope()
    await searchCache.removeAll(scope: scope)
    await cache.remove(resourcesNamed: AppCacheResources.socialRelationshipNames)

    switch impact {
    case .relationshipOnly:
      break
    case .grantsAccess:
      await cache.invalidate(AppCacheResources.friendsActivity)
    case .revokesAccess:
      await cache.remove(AppCacheResources.friendsActivity)
    }
  }

  private func purgeIfAccessWasLost(_ error: any Error) async {
    let failure = AppFailure(error)
    guard failure == .permissionDenied || failure == .unavailable else { return }
    await purgePermissionSensitiveSnapshots()
  }

  private func purgePermissionSensitiveSnapshots() async {
    let scope = await cache.currentScope()
    await searchCache.removeAll(scope: scope)
    await cache.remove(resourcesNamed: AppCacheResources.socialRelationshipNames)
    await cache.remove(AppCacheResources.friendsActivity)
  }
}
