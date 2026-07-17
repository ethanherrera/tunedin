import Foundation

struct PostComment: Codable, Equatable, Identifiable, Sendable {
  let id: UUID
  let postID: UUID
  let authorID: UUID
  let username: String
  let displayName: String
  let body: String?
  let createdAt: Date
  let updatedAt: Date
  let deletedAt: Date?

  var isDeleted: Bool { deletedAt != nil }
}

struct PostCommentCursor: Equatable, Sendable {
  let createdAt: Date
  let commentID: UUID
}

struct PostMedia: Codable, Equatable, Identifiable, Sendable {
  let id: UUID
  let postID: UUID
  let uploaderID: UUID
  let username: String
  let displayName: String
  let objectPath: String
  let caption: String?
  let version: Int64
  let attachedAt: Date
}

struct PostMediaCursor: Equatable, Sendable {
  let attachedAt: Date
  let mediaID: UUID
}

struct PostMediaReservation: Equatable, Sendable {
  let mediaID: UUID
  let postID: UUID
  let objectPath: String
  let expiresAt: Date
}
