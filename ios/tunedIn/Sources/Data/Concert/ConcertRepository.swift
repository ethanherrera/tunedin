import Foundation

protocol ConcertRepository: Sendable {
  func createPrivateConcert(_ input: ConcertCreationInput) async throws -> Concert
  func updateConcert(_ input: ConcertUpdateInput) async throws -> Concert
  func tagCollaborator(
    concertID: UUID,
    profileID: UUID,
    expectedVersion: Int64
  ) async throws -> Concert
  func removeCollaborator(
    concertID: UUID,
    profileID: UUID,
    expectedVersion: Int64
  ) async throws -> Concert
  func transferOwnership(
    concertID: UUID,
    newOwnerID: UUID,
    expectedVersion: Int64
  ) async throws -> Concert
  func deleteConcert(id: UUID) async throws
  func collaborators(concertID: UUID) async throws -> [ConcertCollaborator]
  func comments(
    concertID: UUID,
    cursor: ConcertCommentCursor?
  ) async throws -> [ConcertComment]
  func createComment(concertID: UUID, body: String) async throws -> ConcertComment
  func updateComment(commentID: UUID, body: String) async throws -> ConcertComment
  func deleteComment(commentID: UUID) async throws
  func friendsActivity(cursor: FriendsActivityCursor?) async throws -> [FriendActivity]
  func profileConcertHistory(
    profileID: UUID,
    query: ConcertHistoryQuery,
    cursor: ConcertHistoryCursor?
  ) async throws -> [ConcertPreview]
  func fetchConcertDetail(id: UUID, viewerID: UUID) async throws -> ConcertDetail
  func observeConcert(id: UUID) -> AsyncStream<Void>
  func observeFriendsActivity() -> AsyncStream<Void>
}
