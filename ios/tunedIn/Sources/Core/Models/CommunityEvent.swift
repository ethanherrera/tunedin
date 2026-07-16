import Foundation

enum CommunityEventLifecycle: String, Codable, CaseIterable, Equatable, Sendable {
  case scheduled
  case postponed
  case cancelled
  case completed
}

enum CommunityEventListing: String, Codable, CaseIterable, Equatable, Sendable {
  case listed
  case unlisted
}

enum CommunityEventIntegrity: String, Codable, CaseIterable, Equatable, Sendable {
  case communityAdded = "community_added"
  case corroborated
  case disputed
}

enum CommunityEventRowState: String, Codable, CaseIterable, Equatable, Sendable {
  case active
  case merged
  case tombstoned
}

enum EventAttendanceStatus: String, Codable, CaseIterable, Equatable, Sendable {
  case going
  case went
  case didNotGo = "did_not_go"
}

enum EventAudience: String, Codable, CaseIterable, Equatable, Sendable {
  case privateOnly = "private"
  case friends
  case community

  var title: String {
    switch self {
    case .privateOnly: "Only me"
    case .friends: "Friends"
    case .community: "Community"
    }
  }
}

enum CommunityEventPhase: Equatable, Sendable {
  case upcoming
  case postponed
  case cancelled
  case memories
}

struct CommunityEventArtist: Codable, Equatable, Identifiable, Sendable {
  let catalogArtistID: UUID
  let displayName: String
  let position: Int
  let isHeadliner: Bool

  var id: UUID { catalogArtistID }
}

struct EventFriendPreview: Codable, Equatable, Identifiable, Sendable {
  let profile: SocialProfile
  let status: EventAttendanceStatus

  var id: UUID { profile.id }
}

struct CommunityEventSummary: Codable, Equatable, Identifiable, Sendable {
  let id: UUID
  let artists: [CommunityEventArtist]
  let catalogPlaceID: UUID?
  let catalogAreaID: UUID?
  let catalogTourID: UUID?
  let venueName: String
  let areaName: String
  let eventDate: Date
  let startsAt: Date?
  let timeZoneIdentifier: String
  let memoryUnlockAt: Date
  let lifecycle: CommunityEventLifecycle
  let listing: CommunityEventListing
  let integrity: CommunityEventIntegrity
  let rowState: CommunityEventRowState
  let sourceLabel: String
  let currentUserAttendance: EventAttendanceStatus?
  let friendPreviews: [EventFriendPreview]
  let publicGoingCount: Int
  let publicWentCount: Int
  let diaryCount: Int
  let duplicateCandidateEventID: UUID?

  var title: String {
    artists.sorted(by: { $0.position < $1.position }).map(\.displayName).joined(separator: ", ")
  }

  var headlinerName: String {
    artists.first(where: \.isHeadliner)?.displayName ?? title
  }

  func phase(at date: Date = .now) -> CommunityEventPhase {
    switch lifecycle {
    case .cancelled:
      return .cancelled
    case .postponed:
      return .postponed
    case .completed:
      return .memories
    case .scheduled:
      return date >= memoryUnlockAt ? .memories : .upcoming
    }
  }

  func canCreateDiary(at date: Date = .now) -> Bool {
    phase(at: date) == .memories && currentUserAttendance == .went
  }
}

struct EventAttendance: Codable, Equatable, Identifiable, Sendable {
  let profile: SocialProfile
  let status: EventAttendanceStatus
  let audience: EventAudience
  let updatedAt: Date

  var id: UUID { profile.id }
}

struct EventPost: Codable, Equatable, Identifiable, Sendable {
  let id: UUID
  let author: SocialProfile
  let body: String
  let audience: EventAudience
  let createdAt: Date
}

struct EventDiaryPreview: Codable, Equatable, Identifiable, Sendable {
  let id: UUID
  let author: SocialProfile
  let score: Double?
  let note: String?
  let photoCount: Int
  let videoCount: Int
  let audience: EventAudience
  let publishedAt: Date
}

struct CommunityEventDetail: Codable, Equatable, Identifiable, Sendable {
  let summary: CommunityEventSummary
  let attendances: [EventAttendance]
  let posts: [EventPost]
  let diaryPreviews: [EventDiaryPreview]

  var id: UUID { summary.id }
}

enum EventActivityKind: String, Codable, Equatable, Sendable {
  case markedGoing = "marked_going"
  case sharedDiary = "shared_diary"
  case postedComment = "posted_comment"
  case invitedYou = "invited_you"
}

struct EventActivity: Codable, Equatable, Identifiable, Sendable {
  let id: UUID
  let kind: EventActivityKind
  let actor: SocialProfile
  let event: CommunityEventSummary
  let occurredAt: Date
  let message: String
}

struct EventInviteCandidate: Codable, Equatable, Identifiable, Sendable {
  let profile: SocialProfile
  let attendanceStatus: EventAttendanceStatus?
  let isAlreadyInvited: Bool

  var id: UUID { profile.id }
}

struct CommunityEventCreationInput: Equatable, Sendable {
  let artists: [CatalogArtist]
  let place: CatalogPlace
  let tour: CatalogTour?
  let eventDate: Date
  let startsAt: Date?
  let timeZoneIdentifier: String
  let listing: CommunityEventListing

  var artistCatalogIDs: [UUID] { artists.map(\.id) }
  var placeCatalogID: UUID { place.id }
  var areaCatalogID: UUID? { place.areaID }
  var tourCatalogID: UUID? { tour?.id }
}

struct EventDiaryInput: Equatable, Sendable {
  let score: Double?
  let note: String?
  let audience: EventAudience
}

enum CommunityEventError: LocalizedError, Equatable {
  case eventUnavailable
  case invalidEvent(String)
  case duplicateEvent(UUID)
  case invitationUnavailable
  case featureUnavailable(String)

  var errorDescription: String? {
    switch self {
    case .eventUnavailable:
      "This event is no longer available."
    case let .invalidEvent(message):
      message
    case .duplicateEvent:
      "A matching event already exists. Open it instead of creating another."
    case .invitationUnavailable:
      "That invitation is no longer available."
    case let .featureUnavailable(feature):
      "\(feature) will be available in a later community events phase."
    }
  }
}
