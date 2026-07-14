import Foundation

struct Concert: Codable, Equatable, Identifiable, Sendable {
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
  let version: Int64
  let photoObjectPath: String?
  let photoVersion: Int64

  init(
    id: UUID,
    ownerID: UUID,
    venueName: String,
    city: String?,
    concertDate: String,
    startsAt: Date?,
    venueTimeZone: String?,
    tour: String?,
    visibility: ConcertVisibility,
    createdAt: Date,
    updatedAt: Date,
    lastActivityAt: Date,
    version: Int64 = 1,
    photoObjectPath: String? = nil,
    photoVersion: Int64 = 0
  ) {
    self.id = id
    self.ownerID = ownerID
    self.venueName = venueName
    self.city = city
    self.concertDate = concertDate
    self.startsAt = startsAt
    self.venueTimeZone = venueTimeZone
    self.tour = tour
    self.visibility = visibility
    self.createdAt = createdAt
    self.updatedAt = updatedAt
    self.lastActivityAt = lastActivityAt
    self.version = version
    self.photoObjectPath = photoObjectPath
    self.photoVersion = photoVersion
  }
}

enum ConcertVisibility: String, Codable, CaseIterable, Equatable, Sendable {
  case `private`
  case collaborators
  case friends
}

struct ConcertHistoryCursor: Equatable, Sendable {
  let concertDate: String?
  let updatedAt: Date?
  let text: String?
  let concertID: UUID

  init(preview: ConcertPreview, sort: ConcertHistorySort) {
    concertID = preview.id
    switch sort {
    case .newest, .oldest:
      concertDate = preview.concert.concertDate
      updatedAt = nil
      text = nil
    case .recentlyUpdated:
      concertDate = nil
      updatedAt = preview.concert.updatedAt
      text = nil
    case .artist:
      concertDate = nil
      updatedAt = nil
      text = preview.primaryArtistName.lowercased()
    case .venue:
      concertDate = nil
      updatedAt = nil
      text = preview.concert.venueName.lowercased()
    }
  }
}

struct ConcertHistoryQuery: Equatable, Sendable {
  var searchText = ""
  var year: Int?
  var visibility: ConcertVisibility?
  var sort: ConcertHistorySort = .newest
}

enum ConcertHistorySort: String, CaseIterable, Equatable, Sendable {
  case newest
  case oldest
  case recentlyUpdated = "recently_updated"
  case artist
  case venue

  var displayTitle: String {
    switch self {
    case .newest: "Newest"
    case .oldest: "Oldest"
    case .recentlyUpdated: "Recently updated"
    case .artist: "Artist"
    case .venue: "Venue"
    }
  }
}

struct ConcertPreview: Codable, Equatable, Identifiable, Sendable {
  let concert: Concert
  let primaryArtistName: String

  var id: UUID {
    concert.id
  }
}

struct ConcertArtist: Codable, Equatable, Identifiable, Sendable {
  let id: UUID
  let name: String
  let lineupPosition: Int
  let isPrimary: Bool
}

struct SetlistEntry: Codable, Equatable, Identifiable, Sendable {
  let id: UUID
  let position: Int
  let title: String
}

struct ConcertTimelineEvent: Codable, Equatable, Identifiable, Sendable {
  let id: UUID
  let actorID: UUID
  let occurredAt: Date
  let title: String
  let kind: ConcertEventKind

  init(
    id: UUID,
    actorID: UUID,
    occurredAt: Date,
    title: String,
    kind: ConcertEventKind = .concertCreated
  ) {
    self.id = id
    self.actorID = actorID
    self.occurredAt = occurredAt
    self.title = title
    self.kind = kind
  }
}

struct ConcertDetail: Codable, Equatable, Sendable {
  let concert: Concert
  let artists: [ConcertArtist]
  let setlist: [SetlistEntry]
  let history: [ConcertTimelineEvent]
  let collaborators: [ConcertCollaborator]

  init(
    concert: Concert,
    artists: [ConcertArtist],
    setlist: [SetlistEntry],
    history: [ConcertTimelineEvent],
    collaborators: [ConcertCollaborator] = []
  ) {
    self.concert = concert
    self.artists = artists
    self.setlist = setlist
    self.history = history
    self.collaborators = collaborators
  }
}

enum ConcertEventKind: String, Codable, CaseIterable, Equatable, Sendable {
  case concertCreated = "concert_created"
  case concertUpdated = "concert_updated"
  case setlistUpdated = "setlist_updated"
  case collaboratorTagged = "collaborator_tagged"
  case collaboratorRemoved = "collaborator_removed"
  case visibilityChanged = "visibility_changed"
  case ownershipTransferred = "ownership_transferred"
  case commentAdded = "comment_added"
  case commentUpdated = "comment_updated"
  case commentDeleted = "comment_deleted"
  case albumPhotoAdded = "album_photo_added"

  var timelineTitle: String {
    switch self {
    case .concertCreated:
      "Concert created"
    case .concertUpdated:
      "Concert updated"
    case .setlistUpdated:
      "Setlist updated"
    case .collaboratorTagged:
      "Collaborator added"
    case .collaboratorRemoved:
      "Collaborator removed"
    case .visibilityChanged:
      "Visibility changed"
    case .ownershipTransferred:
      "Ownership transferred"
    case .commentAdded:
      "Comment added"
    case .commentUpdated:
      "Comment updated"
    case .commentDeleted:
      "Comment removed"
    case .albumPhotoAdded:
      "Photo added"
    }
  }
}

struct ConcertCollaborator: Codable, Equatable, Identifiable, Sendable {
  let id: UUID
  let username: String
  let displayName: String
  let isOwner: Bool
  let taggedAt: Date
}

enum ConcertViewerRole: Equatable, Sendable {
  case owner
  case editor
  case viewer

  var canEdit: Bool {
    self == .owner || self == .editor
  }

  var canManagePeople: Bool {
    canEdit
  }

  var canTransferOrDelete: Bool {
    self == .owner
  }
}

struct ConcertComment: Codable, Equatable, Identifiable, Sendable {
  let id: UUID
  let concertID: UUID
  let authorID: UUID
  let username: String
  let displayName: String
  let body: String?
  let createdAt: Date
  let updatedAt: Date
  let deletedAt: Date?

  var isDeleted: Bool {
    deletedAt != nil
  }
}

struct ConcertCommentCursor: Equatable, Sendable {
  let createdAt: Date
  let commentID: UUID
}

struct ConcertAlbumPolicy: Codable, Equatable, Sendable {
  let policyVersion: Int
  let concertPhotoLimit: Int
  let contributorPhotoLimit: Int
  let reservationLimit24Hours: Int
  let pickerBatchLimit: Int
  let captionCharacterLimit: Int
  let attachedFileByteLimit: Int
  let pendingReservationLifetimeSeconds: Int

  enum CodingKeys: String, CodingKey {
    case policyVersion = "policy_version"
    case concertPhotoLimit = "concert_photo_limit"
    case contributorPhotoLimit = "contributor_photo_limit"
    case reservationLimit24Hours = "reservation_limit_24_hours"
    case pickerBatchLimit = "picker_batch_limit"
    case captionCharacterLimit = "caption_character_limit"
    case attachedFileByteLimit = "attached_file_byte_limit"
    case pendingReservationLifetimeSeconds = "pending_reservation_lifetime_seconds"
  }
}

struct ConcertAlbumPhoto: Codable, Equatable, Identifiable, Sendable {
  let id: UUID
  let concertID: UUID
  let uploaderID: UUID
  let username: String
  let displayName: String
  let objectPath: String
  let caption: String?
  let version: Int64
  let attachedAt: Date
}

struct ConcertAlbumPhotoCursor: Equatable, Sendable {
  let attachedAt: Date
  let photoID: UUID
}

struct ConcertPhotoReservation: Equatable, Sendable {
  let photoID: UUID
  let concertID: UUID
  let objectPath: String
  let expiresAt: Date
}

struct ConcertUpdateInput: Equatable, Sendable {
  let concertID: UUID
  let expectedVersion: Int64
  let artists: [ConcertArtistInput]
  let venueName: String
  let concertDate: String
  let city: String?
  let tour: String?
  let startsAt: Date?
  let venueTimeZone: String?
  let setlist: [String]
  let visibility: ConcertVisibility
}

struct FriendsActivityCursor: Equatable, Sendable {
  let occurredAt: Date
  let eventID: UUID
}

struct FriendActivity: Codable, Equatable, Identifiable, Sendable {
  let id: UUID
  let concertID: UUID
  let actorID: UUID
  let actorUsername: String
  let actorDisplayName: String
  let eventKind: ConcertEventKind
  let occurredAt: Date
  let primaryArtistName: String
  let venueName: String
  let concertDate: String
  var changedFields: [String] = []
  var setlistPreview: [String] = []
  var setlistCount = 0
  var photoID: UUID?
  var photoObjectPath: String?
  var photoVersion: Int64 = 0

  var activityTitle: String {
    switch eventKind {
    case .concertCreated:
      "saved a night"
    case .concertUpdated:
      "added to a night"
    case .setlistUpdated:
      "updated the setlist"
    case .commentAdded:
      "left a note"
    case .commentUpdated:
      "refined a note"
    case .commentDeleted:
      "removed a note"
    case .albumPhotoAdded:
      "added a photo"
    case .collaboratorTagged, .collaboratorRemoved, .visibilityChanged, .ownershipTransferred:
      "updated a concert"
    }
  }
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
