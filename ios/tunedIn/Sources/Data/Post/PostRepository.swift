import Foundation

protocol PostRepository: Sendable {
  func reserveMedia(postID: UUID, mediaID: UUID) async throws -> PostMediaReservation
  func uploadReservedMedia(_ jpegData: Data, reservation: PostMediaReservation) async throws -> PostMedia
  func media(postID: UUID, cursor: PostMediaCursor?) async throws -> [PostMedia]
  func mediaURL(mediaID: UUID, objectPath: String, version: Int64) async throws -> URL
  func comments(postID: UUID, cursor: PostCommentCursor?) async throws -> [PostComment]
  func createComment(postID: UUID, body: String) async throws -> PostComment
}
