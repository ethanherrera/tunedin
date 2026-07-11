import Foundation

struct AuthenticatedUser: Equatable, Sendable {
  let id: UUID
  let email: String?
}

struct Profile: Codable, Equatable, Sendable {
  let id: UUID
  let username: String?
  let displayName: String?
  let onboardingCompletedAt: Date?
  let createdAt: Date
  let updatedAt: Date

  var hasCompletedOnboarding: Bool {
    onboardingCompletedAt != nil && username != nil && displayName != nil
  }

  enum CodingKeys: String, CodingKey {
    case id
    case username
    case displayName = "display_name"
    case onboardingCompletedAt = "onboarding_completed_at"
    case createdAt = "created_at"
    case updatedAt = "updated_at"
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
