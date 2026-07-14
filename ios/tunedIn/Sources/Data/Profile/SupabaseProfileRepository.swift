import Foundation
import Supabase

struct SupabaseProfileRepository: ProfileRepository {
  let client: SupabaseClient
  let signedURLs: SignedURLCache

  init(
    client: SupabaseClient,
    signedURLs: SignedURLCache = SignedURLCache()
  ) {
    self.client = client
    self.signedURLs = signedURLs
  }

  func fetchProfile(for userID: UUID) async throws -> Profile {
    try await withAppFailure {
      let response: PostgrestResponse<Profile> = try await client
        .from("profiles")
        .select()
        .eq("id", value: userID.uuidString)
        .single()
        .execute()

      return response.value
    }
  }

  func isUsernameAvailable(_ username: String) async throws -> Bool {
    try await withAppFailure {
      let response: PostgrestResponse<Bool> = try await client
        .rpc("is_username_available", params: UsernameParameter(username: username))
        .execute()

      return response.value
    }
  }

  func completeOnboarding(username: String, displayName: String) async throws -> Profile {
    try await withAppFailure {
      let response: PostgrestResponse<Profile> = try await client
        .rpc(
          "complete_onboarding",
          params: CompleteOnboardingParameters(username: username, displayName: displayName)
        )
        .single()
        .execute()

      return response.value
    }
  }

  func setAvatar(jpegData: Data, for userID: UUID) async throws -> Profile {
    try await withAppFailure {
      let path = avatarPath(for: userID)
      try await client.storage.from("images").upload(
        path,
        data: jpegData,
        options: FileOptions(cacheControl: "3600", contentType: "image/jpeg", upsert: true)
      )

      do {
        let response: PostgrestResponse<Profile> = try await client
          .rpc("set_profile_avatar").single().execute()
        await signedURLs.remove(kind: .avatar, id: userID)
        return response.value
      } catch {
        _ = try? await client.storage.from("images").remove(paths: [path])
        throw error
      }
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
    await signedURLs.remove(kind: .avatar, id: userID)
    return profile
  }

  func avatarURL(profileID: UUID, objectPath: String, version: Int64) async throws -> URL {
    try await withAppFailure {
      try await signedURLs.value(for: .avatar(profileID: profileID, version: version)) {
        try await client.storage.from("images").createSignedURL(
          path: objectPath,
          expiresIn: 3600,
          cacheNonce: String(version)
        )
      }
    }
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
