import Foundation

protocol SocialRepository: Sendable {
  func searchProfiles(usernamePrefix: String) async throws -> [SocialProfile]
  func profile(username: String) async throws -> SocialProfile?
  func friends(username: String) async throws -> [SocialProfile]
  func incomingFriendRequests() async throws -> [SocialProfile]
  func sendFriendRequest(to profileID: UUID) async throws
  func acceptFriendRequest(from profileID: UUID) async throws
  func declineFriendRequest(from profileID: UUID) async throws
  func withdrawFriendRequest(to profileID: UUID) async throws
  func removeFriend(_ profileID: UUID) async throws
  func block(_ profileID: UUID) async throws
  func unblock(_ profileID: UUID) async throws
}
