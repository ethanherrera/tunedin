import Foundation
import Supabase

struct SupabaseProfileRepository: ProfileRepository {
  let client: SupabaseClient

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
