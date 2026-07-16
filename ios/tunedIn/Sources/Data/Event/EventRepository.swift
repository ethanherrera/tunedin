import Foundation

struct EventRepositoryCapabilities: OptionSet, Equatable, Sendable {
  let rawValue: Int

  static let discovery = Self(rawValue: 1 << 0)
  static let plans = Self(rawValue: 1 << 1)
  static let activityFeed = Self(rawValue: 1 << 2)
  static let attendance = Self(rawValue: 1 << 3)
  static let conversation = Self(rawValue: 1 << 4)
  static let invitations = Self(rawValue: 1 << 5)
  static let diaries = Self(rawValue: 1 << 6)

  static let phase1Discovery: Self = [.discovery]
  static let phase2Attendance: Self = [.discovery, .plans, .attendance]
  static let phase3Social: Self = [
    .discovery, .plans, .activityFeed, .attendance, .conversation, .invitations
  ]
  static let phase4Memories: Self = [
    .discovery, .plans, .activityFeed, .attendance, .conversation, .invitations, .diaries
  ]
  static let complete: Self = [
    .discovery, .plans, .activityFeed, .attendance, .conversation, .invitations, .diaries
  ]
}

protocol EventRepository: Sendable {
  var capabilities: EventRepositoryCapabilities { get }

  func searchEvents(query: String, viewerID: UUID) async throws -> [CommunityEventSummary]
  func duplicateCandidates(
    for input: CommunityEventCreationInput,
    viewerID: UUID
  ) async throws -> [CommunityEventSummary]
  func eventDetail(id: UUID, viewerID: UUID) async throws -> CommunityEventDetail
  func plans(viewerID: UUID) async throws -> [CommunityEventSummary]
  func activityFeed(viewerID: UUID) async throws -> [EventActivity]
  func setAttendance(
    eventID: UUID,
    viewerID: UUID,
    status: EventAttendanceStatus?,
    audience: EventAudience
  ) async throws -> CommunityEventDetail
  func confirmCancelledPerformance(
    eventID: UUID,
    viewerID: UUID,
    audience: EventAudience
  ) async throws -> CommunityEventDetail
  func addPost(
    eventID: UUID,
    authorID: UUID,
    parentPostID: UUID?,
    body: String,
    audience: EventAudience
  ) async throws -> EventPost
  func inviteCandidates(eventID: UUID, viewerID: UUID) async throws -> [EventInviteCandidate]
  func sendInvitations(eventID: UUID, senderID: UUID, recipientIDs: [UUID]) async throws
  func pendingInvitations(viewerID: UUID) async throws -> [EventInvitation]
  func respondToInvitation(
    invitationID: UUID,
    viewerID: UUID,
    response: EventInvitationResponse,
    audience: EventAudience
  ) async throws
  func saveDiary(
    eventID: UUID,
    authorID: UUID,
    input: EventDiaryInput
  ) async throws -> CommunityEventDetail
  func preparePhotoDiary(
    eventID: UUID,
    authorID: UUID,
    audience: EventAudience
  ) async throws -> UUID
  func profileHistory(profileID: UUID, viewerID: UUID) async throws -> CommunityProfileHistory
  func reportEvent(
    eventID: UUID,
    reporterID: UUID,
    reason: EventReportReason,
    note: String?
  ) async throws
  func createEvent(_ input: CommunityEventCreationInput, creatorID: UUID) async throws -> CommunityEventDetail
}

extension EventRepository {
  func duplicateCandidates(
    for _: CommunityEventCreationInput,
    viewerID _: UUID
  ) async throws -> [CommunityEventSummary] {
    []
  }

  func plans(viewerID _: UUID) async throws -> [CommunityEventSummary] {
    throw CommunityEventError.featureUnavailable("Plans")
  }

  func activityFeed(viewerID _: UUID) async throws -> [EventActivity] {
    throw CommunityEventError.featureUnavailable("Community event activity")
  }

  func setAttendance(
    eventID _: UUID,
    viewerID _: UUID,
    status _: EventAttendanceStatus?,
    audience _: EventAudience
  ) async throws -> CommunityEventDetail {
    throw CommunityEventError.featureUnavailable("Going and Went")
  }

  func confirmCancelledPerformance(
    eventID _: UUID,
    viewerID _: UUID,
    audience _: EventAudience
  ) async throws -> CommunityEventDetail {
    throw CommunityEventError.featureUnavailable("Cancelled performance confirmation")
  }

  func addPost(
    eventID _: UUID,
    authorID _: UUID,
    parentPostID _: UUID?,
    body _: String,
    audience _: EventAudience
  ) async throws -> EventPost {
    throw CommunityEventError.featureUnavailable("Event conversation")
  }

  func inviteCandidates(eventID _: UUID, viewerID _: UUID) async throws -> [EventInviteCandidate] {
    throw CommunityEventError.featureUnavailable("Invitations")
  }

  func sendInvitations(eventID _: UUID, senderID _: UUID, recipientIDs _: [UUID]) async throws {
    throw CommunityEventError.featureUnavailable("Invitations")
  }

  func pendingInvitations(viewerID _: UUID) async throws -> [EventInvitation] {
    throw CommunityEventError.featureUnavailable("Invitations")
  }

  func respondToInvitation(
    invitationID _: UUID,
    viewerID _: UUID,
    response _: EventInvitationResponse,
    audience _: EventAudience
  ) async throws {
    throw CommunityEventError.featureUnavailable("Invitations")
  }

  func saveDiary(
    eventID _: UUID,
    authorID _: UUID,
    input _: EventDiaryInput
  ) async throws -> CommunityEventDetail {
    throw CommunityEventError.featureUnavailable("Concert diaries")
  }

  func preparePhotoDiary(
    eventID _: UUID,
    authorID _: UUID,
    audience _: EventAudience
  ) async throws -> UUID {
    throw CommunityEventError.featureUnavailable("Diary photos")
  }

  func profileHistory(
    profileID _: UUID,
    viewerID _: UUID
  ) async throws -> CommunityProfileHistory {
    throw CommunityEventError.featureUnavailable("Concert history")
  }

  func reportEvent(
    eventID _: UUID,
    reporterID _: UUID,
    reason _: EventReportReason,
    note _: String?
  ) async throws {
    throw CommunityEventError.featureUnavailable("Event reports")
  }
}
