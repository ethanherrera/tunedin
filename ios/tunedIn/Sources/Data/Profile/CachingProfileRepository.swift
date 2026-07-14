import Foundation

protocol CacheAwareProfileRepository: ProfileRepository {
  func fetchProfile(for userID: UUID, policy: CacheReadPolicy) async throws -> Profile
}

extension ProfileRepository {
  func fetchProfile(for userID: UUID, policy: CacheReadPolicy) async throws -> Profile {
    if let repository = self as? any CacheAwareProfileRepository {
      return try await repository.fetchProfile(for: userID, policy: policy)
    }
    return try await fetchProfile(for: userID)
  }
}

struct CachingProfileRepository: CacheAwareProfileRepository {
  let remote: any ProfileRepository
  let cache: AppDataCache

  func fetchProfile(for userID: UUID) async throws -> Profile {
    try await fetchProfile(for: userID, policy: .automatic)
  }

  func fetchProfile(for userID: UUID, policy: CacheReadPolicy) async throws -> Profile {
    try await cache.value(
      for: AppCacheResources.profile(userID: userID),
      freshness: .profile,
      policy: policy
    ) {
      try await remote.fetchProfile(for: userID)
    }
  }

  func isUsernameAvailable(_ username: String) async throws -> Bool {
    try await remote.isUsernameAvailable(username)
  }

  func completeOnboarding(username: String, displayName: String) async throws -> Profile {
    let profile = try await remote.completeOnboarding(username: username, displayName: displayName)
    try? await cache.store(profile, for: AppCacheResources.profile(userID: profile.id))
    return profile
  }

  func setAvatar(jpegData: Data, for userID: UUID) async throws -> Profile {
    let profile = try await remote.setAvatar(jpegData: jpegData, for: userID)
    try? await cache.store(profile, for: AppCacheResources.profile(userID: userID))
    return profile
  }

  func removeAvatar(for userID: UUID) async throws -> Profile {
    do {
      let profile = try await remote.removeAvatar(for: userID)
      try? await cache.store(profile, for: AppCacheResources.profile(userID: userID))
      return profile
    } catch let error as AvatarRemovalError {
      try? await cache.store(error.profile, for: AppCacheResources.profile(userID: userID))
      throw error
    }
  }

  func avatarURL(profileID: UUID, objectPath: String, version: Int64) async throws -> URL {
    try await remote.avatarURL(profileID: profileID, objectPath: objectPath, version: version)
  }
}
