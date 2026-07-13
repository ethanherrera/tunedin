import Foundation

struct AuthenticatedUser: Equatable, Sendable {
  let id: UUID
  let email: String?
}

struct Profile: Codable, Equatable, Sendable {
  let id: UUID
  let username: String?
  let displayName: String?
  let avatarObjectPath: String?
  let avatarVersion: Int64
  let onboardingCompletedAt: Date?
  let createdAt: Date
  let updatedAt: Date

  init(
    id: UUID,
    username: String?,
    displayName: String?,
    avatarObjectPath: String? = nil,
    avatarVersion: Int64 = 0,
    onboardingCompletedAt: Date?,
    createdAt: Date,
    updatedAt: Date
  ) {
    self.id = id
    self.username = username
    self.displayName = displayName
    self.avatarObjectPath = avatarObjectPath
    self.avatarVersion = avatarVersion
    self.onboardingCompletedAt = onboardingCompletedAt
    self.createdAt = createdAt
    self.updatedAt = updatedAt
  }

  var hasCompletedOnboarding: Bool {
    onboardingCompletedAt != nil && username != nil && displayName != nil
  }

  enum CodingKeys: String, CodingKey {
    case id
    case username
    case displayName = "display_name"
    case avatarObjectPath = "avatar_object_path"
    case avatarVersion = "avatar_version"
    case onboardingCompletedAt = "onboarding_completed_at"
    case createdAt = "created_at"
    case updatedAt = "updated_at"
  }
}

enum RelationshipState: String, Codable, CaseIterable, Equatable, Sendable {
  case none
  case outgoing
  case incoming
  case friends
  case declined
  case blocked
  case unavailable

  var canViewFriendContent: Bool {
    self == .friends
  }
}

struct SocialProfile: Identifiable, Codable, Equatable, Sendable {
  let id: UUID
  let username: String
  let displayName: String
  let relationship: RelationshipState
  let avatarObjectPath: String?
  let avatarVersion: Int64

  init(
    id: UUID,
    username: String,
    displayName: String,
    relationship: RelationshipState,
    avatarObjectPath: String? = nil,
    avatarVersion: Int64 = 0
  ) {
    self.id = id
    self.username = username
    self.displayName = displayName
    self.relationship = relationship
    self.avatarObjectPath = avatarObjectPath
    self.avatarVersion = avatarVersion
  }
}

enum ProfileInput {
  static func normalizedUsername(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
  }

  static func normalizedDisplayName(_ value: String) -> String {
    value.split(whereSeparator: \.isWhitespace).joined(separator: " ")
  }

  static func isUsernameValid(_ value: String) -> Bool {
    let normalized = normalizedUsername(value)
    return normalized.range(
      of: "^[a-z0-9][a-z0-9_]{1,22}[a-z0-9]$",
      options: .regularExpression
    ) != nil
  }

  static func isDisplayNameValid(_ value: String) -> Bool {
    guard value.rangeOfCharacter(from: .controlCharacters) == nil else {
      return false
    }

    let normalized = normalizedDisplayName(value)
    return (1 ... 50).contains(normalized.count)
  }
}
