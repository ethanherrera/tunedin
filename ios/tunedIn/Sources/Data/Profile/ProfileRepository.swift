import Foundation

protocol ProfileRepository: Sendable {
  func fetchProfile(for userID: UUID) async throws -> Profile
  func isUsernameAvailable(_ username: String) async throws -> Bool
  func completeOnboarding(username: String, displayName: String) async throws -> Profile
  func setAvatar(jpegData: Data, for userID: UUID) async throws -> Profile
  func removeAvatar(for userID: UUID) async throws -> Profile
  func avatarURL(profileID: UUID, objectPath: String, version: Int64) async throws -> URL
}
