import Foundation

protocol ConcertRepository: Sendable {
  func createPrivateConcert(_ input: ConcertCreationInput) async throws -> Concert
  func updateConcert(_ input: ConcertUpdateInput) async throws -> Concert
  func setConcertPhoto(_ jpegData: Data, concertID: UUID) async throws -> Concert
  func removeConcertPhoto(concertID: UUID) async throws -> Concert
  func concertPhotoURL(concertID: UUID, objectPath: String, version: Int64) async throws -> URL
  func albumPolicy() async throws -> ConcertAlbumPolicy
  func reserveAlbumPhoto(concertID: UUID, photoID: UUID) async throws -> ConcertPhotoReservation
  func uploadReservedAlbumPhoto(_ jpegData: Data, reservation: ConcertPhotoReservation) async throws -> ConcertAlbumPhoto
  func albumPhotos(concertID: UUID, cursor: ConcertAlbumPhotoCursor?) async throws -> [ConcertAlbumPhoto]
  func albumPhotoURL(photoID: UUID, objectPath: String, version: Int64) async throws -> URL
  func updateAlbumPhotoCaption(photoID: UUID, caption: String?) async throws -> ConcertAlbumPhoto
  func deleteAlbumPhoto(photoID: UUID) async throws
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
