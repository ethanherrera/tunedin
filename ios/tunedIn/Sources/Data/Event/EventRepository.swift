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
  static let complete: Self = [
    .discovery, .plans, .activityFeed, .attendance, .conversation, .invitations, .diaries
  ]
}

protocol EventRepository: Sendable {
  var capabilities: EventRepositoryCapabilities { get }

  func searchEvents(query: String, viewerID: UUID) async throws -> [CommunityEventSummary]
  func eventDetail(id: UUID, viewerID: UUID) async throws -> CommunityEventDetail
  func plans(viewerID: UUID) async throws -> [CommunityEventSummary]
  func activityFeed(viewerID: UUID) async throws -> [EventActivity]
  func setAttendance(
    eventID: UUID,
    viewerID: UUID,
    status: EventAttendanceStatus?,
    audience: EventAudience
  ) async throws -> CommunityEventDetail
  func addPost(
    eventID: UUID,
    authorID: UUID,
    body: String,
    audience: EventAudience
  ) async throws -> EventPost
  func inviteCandidates(eventID: UUID, viewerID: UUID) async throws -> [EventInviteCandidate]
  func sendInvitations(eventID: UUID, senderID: UUID, recipientIDs: [UUID]) async throws
  func saveDiary(
    eventID: UUID,
    authorID: UUID,
    input: EventDiaryInput
  ) async throws -> CommunityEventDetail
  func createEvent(_ input: CommunityEventCreationInput, creatorID: UUID) async throws -> CommunityEventDetail
}

extension EventRepository {
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

  func addPost(
    eventID _: UUID,
    authorID _: UUID,
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

  func saveDiary(
    eventID _: UUID,
    authorID _: UUID,
    input _: EventDiaryInput
  ) async throws -> CommunityEventDetail {
    throw CommunityEventError.featureUnavailable("Concert diaries")
  }
}
