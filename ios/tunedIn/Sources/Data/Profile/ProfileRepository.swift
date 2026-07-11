import Foundation

protocol ProfileRepository: Sendable {
  func fetchProfile(for userID: UUID) async throws -> Profile
  func isUsernameAvailable(_ username: String) async throws -> Bool
  func completeOnboarding(username: String, displayName: String) async throws -> Profile
}
