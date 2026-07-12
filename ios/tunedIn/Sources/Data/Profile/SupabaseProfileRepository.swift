import Foundation
import Supabase

struct SupabaseProfileRepository: ProfileRepository {
  let client: SupabaseClient
  private let avatarURLs = AvatarURLCache()

  func fetchProfile(for userID: UUID) async throws -> Profile {
    let response: PostgrestResponse<Profile> = try await client
      .from("profiles")
      .select()
      .eq("id", value: userID.uuidString)
      .single()
      .execute()

    return response.value
  }

  func isUsernameAvailable(_ username: String) async throws -> Bool {
    let response: PostgrestResponse<Bool> = try await client
      .rpc("is_username_available", params: UsernameParameter(username: username))
      .execute()

    return response.value
  }

  func completeOnboarding(username: String, displayName: String) async throws -> Profile {
    let response: PostgrestResponse<Profile> = try await client
      .rpc(
        "complete_onboarding",
        params: CompleteOnboardingParameters(username: username, displayName: displayName)
      )
      .single()
      .execute()

    return response.value
  }

  func setAvatar(jpegData: Data, for userID: UUID) async throws -> Profile {
    let path = avatarPath(for: userID)
    try await client.storage.from("images").upload(
      path,
      data: jpegData,
      options: FileOptions(cacheControl: "3600", contentType: "image/jpeg", upsert: true)
    )

    do {
      let response: PostgrestResponse<Profile> = try await client
        .rpc("set_profile_avatar").single().execute()
      await avatarURLs.remove(profileID: userID)
      return response.value
    } catch {
      _ = try? await client.storage.from("images").remove(paths: [path])
      throw error
    }
  }

  func removeAvatar(for userID: UUID) async throws -> Profile {
    let response: PostgrestResponse<String?> = try await client
      .rpc("remove_profile_avatar").execute()
    let profile = try await fetchProfile(for: userID)
    let path = response.value ?? avatarPath(for: userID)
    do {
      try await client.storage.from("images").remove(paths: [path])
    } catch {
      throw AvatarRemovalError(profile: profile, underlying: error)
    }
    await avatarURLs.remove(profileID: userID)
    return profile
  }

  func avatarURL(profileID: UUID, objectPath: String, version: Int64) async throws -> URL {
    if let cached = await avatarURLs.value(profileID: profileID, version: version) {
      return cached
    }
    let url = try await client.storage.from("images").createSignedURL(
      path: objectPath,
      expiresIn: 3600,
      cacheNonce: String(version)
    )
    await avatarURLs.insert(url, profileID: profileID, version: version)
    return url
  }

  private func avatarPath(for userID: UUID) -> String {
    "avatars/\(userID.uuidString.lowercased())/profile.jpg"
  }
}

struct AvatarRemovalError: LocalizedError {
  let profile: Profile
  let underlying: any Error

  var errorDescription: String? {
    "Your profile photo was removed, but its stored file still needs deletion. Try again."
  }
}

actor AvatarURLCache {
  private struct Entry {
    let version: Int64
    let url: URL
    let expiresAt: Date
  }

  private var entries: [UUID: Entry] = [:]

  func value(profileID: UUID, version: Int64, now: Date = .now) -> URL? {
    guard let entry = entries[profileID], entry.version == version, entry.expiresAt > now else {
      entries[profileID] = nil
      return nil
    }
    return entry.url
  }

  func insert(_ url: URL, profileID: UUID, version: Int64, now: Date = .now) {
    entries[profileID] = Entry(version: version, url: url, expiresAt: now.addingTimeInterval(55 * 60))
    if entries.count > 100, let oldest = entries.min(by: { $0.value.expiresAt < $1.value.expiresAt })?.key {
      entries[oldest] = nil
    }
  }

  func remove(profileID: UUID) {
    entries[profileID] = nil
  }
}

actor AlbumPolicyCache {
  private var entry: (policy: ConcertAlbumPolicy, expiresAt: Date)?

  func value(now: Date = .now) -> ConcertAlbumPolicy? {
    guard let entry, entry.expiresAt > now else {
      self.entry = nil
      return nil
    }
    return entry.policy
  }

  func insert(_ policy: ConcertAlbumPolicy, now: Date = .now) {
    entry = (policy, now.addingTimeInterval(55 * 60))
  }
}

private struct UsernameParameter: Encodable {
  let username: String

  enum CodingKeys: String, CodingKey {
    case username = "p_username"
  }
}

private struct CompleteOnboardingParameters: Encodable {
  let username: String
  let displayName: String

  enum CodingKeys: String, CodingKey {
    case username = "p_username"
    case displayName = "p_display_name"
  }
}
