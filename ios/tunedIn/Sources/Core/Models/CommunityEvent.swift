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

enum CommunityEventCoverSource: String, Codable, Equatable, Sendable {
  case community
  case provider
  case wikimedia
}

struct CommunityEventCover: Codable, Equatable, Sendable {
  let source: CommunityEventCoverSource
  let objectPath: String?
  let remoteURL: URL?
  let providerName: String?
  let attribution: String?
  let sourcePageURL: URL?
  let licenseName: String?
  let licenseURL: URL?
  let version: Int64

  enum CodingKeys: String, CodingKey {
    case source, attribution, version
    case objectPath = "object_path"
    case remoteURL = "remote_url"
    case providerName = "provider_name"
    case sourcePageURL = "source_page_url"
    case licenseName = "license_name"
    case licenseURL = "license_url"
  }
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

  var id: UUID {
    catalogArtistID
  }
}

struct EventFriendPreview: Codable, Equatable, Identifiable, Sendable {
  let profile: SocialProfile
  let status: EventAttendanceStatus

  var id: UUID {
    profile.id
  }
}

struct CommunityEventSummary: Codable, Equatable, Identifiable, Sendable {
  let id: UUID
  let artists: [CommunityEventArtist]
  let cover: CommunityEventCover?
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
  let currentUserAudience: EventAudience?
  let friendPreviews: [EventFriendPreview]
  let publicGoingCount: Int
  let publicWentCount: Int
  let postCount: Int
  let averagePostScore: Double?
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
      .cancelled
    case .postponed:
      .postponed
    case .completed:
      .memories
    case .scheduled:
      date >= memoryUnlockAt ? .memories : .upcoming
    }
  }

  func canCreatePost(at date: Date = .now) -> Bool {
    let memoriesAreAvailable = phase(at: date) == .memories
      || (lifecycle == .cancelled && date >= memoryUnlockAt)
    return memoriesAreAvailable && currentUserAttendance == .went
  }

  func replacingCover(_ cover: CommunityEventCover?) -> Self {
    Self(
      id: id,
      artists: artists,
      cover: cover,
      catalogPlaceID: catalogPlaceID,
      catalogAreaID: catalogAreaID,
      catalogTourID: catalogTourID,
      venueName: venueName,
      areaName: areaName,
      eventDate: eventDate,
      startsAt: startsAt,
      timeZoneIdentifier: timeZoneIdentifier,
      memoryUnlockAt: memoryUnlockAt,
      lifecycle: lifecycle,
      listing: listing,
      integrity: integrity,
      rowState: rowState,
      sourceLabel: sourceLabel,
      currentUserAttendance: currentUserAttendance,
      currentUserAudience: currentUserAudience,
      friendPreviews: friendPreviews,
      publicGoingCount: publicGoingCount,
      publicWentCount: publicWentCount,
      postCount: postCount,
      averagePostScore: averagePostScore,
      duplicateCandidateEventID: duplicateCandidateEventID
    )
  }
}

struct EventAttendance: Codable, Equatable, Identifiable, Sendable {
  let profile: SocialProfile
  let status: EventAttendanceStatus
  let audience: EventAudience
  let updatedAt: Date

  var id: UUID {
    profile.id
  }
}

struct EventAttendanceCursor: Equatable, Sendable {
  let updatedAt: Date
  let profileID: UUID
}

struct EventAttendancePage: Equatable, Sendable {
  let items: [EventAttendance]
  let nextCursor: EventAttendanceCursor?
}

struct EventComment: Codable, Equatable, Identifiable, Sendable {
  let id: UUID
  let parentCommentID: UUID?
  let author: SocialProfile
  let body: String
  let audience: EventAudience
  let createdAt: Date
  let isDeleted: Bool
}

struct EventPostPreview: Codable, Equatable, Identifiable, Sendable {
  let id: UUID
  let author: SocialProfile
  let score: Double?
  let performanceScore: Double?
  let note: String?
  let photoCount: Int
  let videoCount: Int
  let commentCount: Int
  let audience: EventAudience
  let publishedAt: Date
}

struct EventPostCursor: Equatable, Sendable {
  let publishedAt: Date
  let postID: UUID
}

struct EventPostPage: Equatable, Sendable {
  let items: [EventPostPreview]
  let nextCursor: EventPostCursor?
}

struct EventProfilePost: Equatable, Identifiable, Sendable {
  let event: CommunityEventSummary
  let post: EventPostPreview

  var id: UUID {
    post.id
  }
}

struct CommunityProfileHistory: Equatable, Sendable {
  let going: [CommunityEventSummary]
  let went: [CommunityEventSummary]
  let posts: [EventProfilePost]

  static let empty = Self(going: [], went: [], posts: [])
}

struct CommunityEventDetail: Codable, Equatable, Identifiable, Sendable {
  let summary: CommunityEventSummary
  let attendances: [EventAttendance]
  let comments: [EventComment]
  let postPreviews: [EventPostPreview]

  var id: UUID {
    summary.id
  }
}

enum EventActivityKind: String, Codable, Equatable, Sendable {
  case eventCreated = "event_created"
  case eventUpdated = "event_updated"
  case markedGoing = "marked_going"
  case markedWent = "marked_went"
  case invitationAccepted = "invitation_accepted"
  case postPublished = "post_published"
  case postMediaAdded = "post_media_added"
  case eventCommented = "event_commented"
  case eventCommentReplied = "event_comment_replied"
}

struct EventActivity: Codable, Equatable, Identifiable, Sendable {
  let id: UUID
  let kind: EventActivityKind
  let actor: SocialProfile
  let event: CommunityEventSummary
  let post: EventPostPreview?
  let occurredAt: Date
  let message: String
}

struct EventInviteCandidate: Codable, Equatable, Identifiable, Sendable {
  let profile: SocialProfile
  let attendanceStatus: EventAttendanceStatus?
  let isAlreadyInvited: Bool

  var id: UUID {
    profile.id
  }
}

enum EventInvitationResponse: String, Codable, Equatable, Sendable {
  case accepted
  case declined
}

struct EventInvitation: Codable, Equatable, Identifiable, Sendable {
  let id: UUID
  let event: CommunityEventSummary
  let sender: SocialProfile
  let createdAt: Date
}

struct CommunityEventCreationInput: Equatable, Sendable {
  let artists: [CatalogArtist]
  let place: CatalogPlace
  let tour: CatalogTour?
  let eventDate: Date
  let startsAt: Date?
  let timeZoneIdentifier: String
  let listing: CommunityEventListing

  var artistCatalogIDs: [UUID] {
    artists.map(\.id)
  }

  var placeCatalogID: UUID {
    place.id
  }

  var areaCatalogID: UUID? {
    place.areaID
  }

  var tourCatalogID: UUID? {
    tour?.id
  }
}

struct EventPostInput: Equatable, Sendable {
  let score: Double?
  let performanceScore: Double?
  let note: String?
  let audience: EventAudience
  let hasReadyPhoto: Bool

  init(
    score: Double?,
    performanceScore: Double?,
    note: String?,
    audience: EventAudience,
    hasReadyPhoto: Bool = false
  ) {
    self.score = score
    self.performanceScore = performanceScore
    self.note = note
    self.audience = audience
    self.hasReadyPhoto = hasReadyPhoto
  }
}

enum EventReportReason: String, CaseIterable, Codable, Equatable, Sendable {
  case duplicate
  case wrongDate = "wrong_date"
  case wrongVenue = "wrong_venue"
  case wrongLineup = "wrong_lineup"
  case cancelled
  case sensitiveLocation = "sensitive_location"
  case other

  var title: String {
    switch self {
    case .duplicate: "Duplicate concert"
    case .wrongDate: "Wrong date or time"
    case .wrongVenue: "Wrong venue"
    case .wrongLineup: "Wrong lineup"
    case .cancelled: "Cancelled or postponed"
    case .sensitiveLocation: "Sensitive location"
    case .other: "Something else"
    }
  }
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
      "This concert is no longer available."
    case let .invalidEvent(message):
      message
    case .duplicateEvent:
      "A matching concert already exists. Open it instead of creating another."
    case .invitationUnavailable:
      "That invitation is no longer available."
    case let .featureUnavailable(feature):
      "\(feature) isn’t available yet."
    }
  }
}
