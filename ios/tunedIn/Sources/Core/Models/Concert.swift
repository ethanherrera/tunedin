import Foundation

struct Concert: Equatable, Identifiable, Sendable {
  let id: UUID
  let ownerID: UUID
  let venueName: String
  let city: String?
  let concertDate: String
  let startsAt: Date?
  let venueTimeZone: String?
  let tour: String?
  let visibility: ConcertVisibility
  let createdAt: Date
  let updatedAt: Date
  let lastActivityAt: Date
}

enum ConcertVisibility: String, Equatable, Sendable {
  case `private`
  case collaborators
  case friends
}

struct ConcertCreationInput: Equatable, Sendable {
  let artists: [ConcertArtistInput]
  let venueName: String
  let concertDate: String
  let city: String?
  let tour: String?
  let startsAt: Date?
  let venueTimeZone: String?
  let setlist: [String]
}

struct ConcertArtistInput: Equatable, Sendable {
  let name: String
  let isPrimary: Bool
}

enum ConcertInput {
  static func normalizedText(_ value: String) -> String {
    value.split(whereSeparator: \.isWhitespace).joined(separator: " ")
  }

  static func hasControlCharacters(_ value: String) -> Bool {
    value.rangeOfCharacter(from: .controlCharacters) != nil
  }

  static func isValidRequiredText(_ value: String, maximumLength: Int) -> Bool {
    !hasControlCharacters(value) && {
      let normalized = normalizedText(value)
      return !normalized.isEmpty && normalized.count <= maximumLength
    }()
  }

  static func isValidOptionalText(_ value: String, maximumLength: Int) -> Bool {
    !hasControlCharacters(value) && normalizedText(value).count <= maximumLength
  }
}
