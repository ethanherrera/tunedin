import Foundation
import Supabase

struct SupabaseSocialRepository: SocialRepository {
  let client: SupabaseClient

  func searchProfiles(usernamePrefix: String) async throws -> [SocialProfile] {
    try await withAppFailure {
      let response: PostgrestResponse<[SocialProfileRecord]> = try await client
        .rpc("search_profiles", params: UsernamePrefixParameter(usernamePrefix: usernamePrefix))
        .execute()

      return response.value.map(SocialProfile.init(databaseRecord:))
    }
  }

  func profile(username: String) async throws -> SocialProfile? {
    try await withAppFailure {
      let response: PostgrestResponse<[SocialProfileRecord]> = try await client
        .rpc("profile_by_username", params: UsernameParameter(username: username))
        .execute()

      return response.value.first.map(SocialProfile.init(databaseRecord:))
    }
  }

  func friends(username: String) async throws -> [SocialProfile] {
    try await withAppFailure {
      let response: PostgrestResponse<[SocialProfileRecord]> = try await client
        .rpc("list_profile_friends", params: UsernameParameter(username: username))
        .execute()

      return response.value.map(SocialProfile.init(databaseRecord:))
    }
  }

  func incomingFriendRequests() async throws -> [SocialProfile] {
    try await withAppFailure {
      let response: PostgrestResponse<[SocialProfileRecord]> = try await client
        .rpc("list_incoming_friend_requests")
        .execute()

      return response.value.map(SocialProfile.init(databaseRecord:))
    }
  }

  func sendFriendRequest(to profileID: UUID) async throws {
    try await performRelationshipRPC(
      "send_friend_request",
      params: RecipientIDParameter(recipientID: profileID)
    )
  }

  func acceptFriendRequest(from profileID: UUID) async throws {
    try await performRelationshipRPC(
      "accept_friend_request",
      params: RequesterIDParameter(requesterID: profileID)
    )
  }

  func declineFriendRequest(from profileID: UUID) async throws {
    try await performRelationshipRPC(
      "decline_friend_request",
      params: RequesterIDParameter(requesterID: profileID)
    )
  }

  func withdrawFriendRequest(to profileID: UUID) async throws {
    try await performRelationshipRPC(
      "withdraw_friend_request",
      params: RecipientIDParameter(recipientID: profileID)
    )
  }

  func removeFriend(_ profileID: UUID) async throws {
    try await performRelationshipRPC(
      "remove_friend",
      params: FriendIDParameter(friendID: profileID)
    )
  }

  func block(_ profileID: UUID) async throws {
    try await performRelationshipRPC("block_profile", params: ProfileIDParameter(profileID: profileID))
  }

  func unblock(_ profileID: UUID) async throws {
    try await performRelationshipRPC("unblock_profile", params: ProfileIDParameter(profileID: profileID))
  }

  private func performRelationshipRPC(_ name: String, params: some Encodable) async throws {
    try await withAppFailure {
      _ = try await client
        .rpc(name, params: params)
        .execute()
    }
  }
}

private struct SocialProfileRecord: Decodable {
  let id: UUID
  let username: String
  let displayName: String
  let relationship: String
  let avatarObjectPath: String?
  let avatarVersion: Int64

  enum CodingKeys: String, CodingKey {
    case id
    case username
    case displayName = "display_name"
    case relationship
    case avatarObjectPath = "avatar_object_path"
    case avatarVersion = "avatar_version"
  }
}

private extension SocialProfile {
  init(databaseRecord: SocialProfileRecord) {
    self.init(
      id: databaseRecord.id,
      username: databaseRecord.username,
      displayName: databaseRecord.displayName,
      relationship: RelationshipState(rawValue: databaseRecord.relationship) ?? .none,
      avatarObjectPath: databaseRecord.avatarObjectPath,
      avatarVersion: databaseRecord.avatarVersion
    )
  }
}

private struct UsernamePrefixParameter: Encodable {
  let usernamePrefix: String

  enum CodingKeys: String, CodingKey {
    case usernamePrefix = "p_username_prefix"
  }
}

private struct UsernameParameter: Encodable {
  let username: String

  enum CodingKeys: String, CodingKey {
    case username = "p_username"
  }
}

struct ProfileIDParameter: Encodable {
  let profileID: UUID

  enum CodingKeys: String, CodingKey {
    case profileID = "p_profile_id"
  }
}

struct RecipientIDParameter: Encodable {
  let recipientID: UUID

  enum CodingKeys: String, CodingKey {
    case recipientID = "p_recipient_id"
  }
}

struct RequesterIDParameter: Encodable {
  let requesterID: UUID

  enum CodingKeys: String, CodingKey {
    case requesterID = "p_requester_id"
  }
}

struct FriendIDParameter: Encodable {
  let friendID: UUID

  enum CodingKeys: String, CodingKey {
    case friendID = "p_friend_id"
  }
}
