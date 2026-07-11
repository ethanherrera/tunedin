import Foundation
import Supabase

public enum PublicSchema {
  public struct ProfilesSelect: Codable, Hashable, Sendable {
    public let createdAt: String
    public let displayName: String?
    public let id: UUID
    public let onboardingCompletedAt: String?
    public let updatedAt: String
    public let username: String?
    public enum CodingKeys: String, CodingKey {
      case createdAt = "created_at"
      case displayName = "display_name"
      case id = "id"
      case onboardingCompletedAt = "onboarding_completed_at"
      case updatedAt = "updated_at"
      case username = "username"
    }
  }
  public struct ProfilesInsert: Codable, Hashable, Sendable {
    public let createdAt: String?
    public let displayName: String?
    public let id: UUID
    public let onboardingCompletedAt: String?
    public let updatedAt: String?
    public let username: String?
    public enum CodingKeys: String, CodingKey {
      case createdAt = "created_at"
      case displayName = "display_name"
      case id = "id"
      case onboardingCompletedAt = "onboarding_completed_at"
      case updatedAt = "updated_at"
      case username = "username"
    }
  }
  public struct ProfilesUpdate: Codable, Hashable, Sendable {
    public let createdAt: String?
    public let displayName: String?
    public let id: UUID?
    public let onboardingCompletedAt: String?
    public let updatedAt: String?
    public let username: String?
    public enum CodingKeys: String, CodingKey {
      case createdAt = "created_at"
      case displayName = "display_name"
      case id = "id"
      case onboardingCompletedAt = "onboarding_completed_at"
      case updatedAt = "updated_at"
      case username = "username"
    }
  }
}
