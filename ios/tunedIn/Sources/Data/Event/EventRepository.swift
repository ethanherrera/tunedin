import Foundation

protocol EventRepository: Sendable {
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
  func createEvent(_ input: CommunityEventCreationInput, creatorID: UUID) async throws -> CommunityEventDetail
}
