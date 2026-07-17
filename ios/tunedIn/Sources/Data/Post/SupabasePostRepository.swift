import Foundation
import Supabase

struct SupabasePostRepository: PostRepository {
  private let client: SupabaseClient
  private let signedURLs: SignedURLCache

  init(client: SupabaseClient, signedURLs: SignedURLCache = SignedURLCache()) {
    self.client = client
    self.signedURLs = signedURLs
  }

  func reserveMedia(postID: UUID, mediaID: UUID) async throws -> PostMediaReservation {
    try await withAppFailure {
      let response: PostgrestResponse<PostMediaReservationRecord> = try await client
        .rpc("reserve_post_media", params: ReservePostMediaParameters(postID: postID, mediaID: mediaID))
        .single()
        .execute()
      return try PostMediaReservation(databaseRecord: response.value)
    }
  }

  func uploadReservedMedia(
    _ jpegData: Data,
    reservation: PostMediaReservation
  ) async throws -> PostMedia {
    try await withAppFailure {
      let options = FileOptions(cacheControl: "3600", contentType: "image/jpeg")
      do {
        try await client.storage.from("images").upload(
          reservation.objectPath,
          data: jpegData,
          options: options
        )
      } catch {
        try await client.storage.from("images").update(
          reservation.objectPath,
          data: jpegData,
          options: options
        )
      }
      let _: PostgrestResponse<PostMediaReservationRecord> = try await client
        .rpc("attach_post_media", params: PostMediaIDParameters(mediaID: reservation.mediaID))
        .single()
        .execute()
      let attached = try await media(postID: reservation.postID, cursor: nil)
      guard let result = attached.first(where: { $0.id == reservation.mediaID }) else {
        throw AppFailure.unexpected
      }
      return result
    }
  }

  func media(postID: UUID, cursor: PostMediaCursor?) async throws -> [PostMedia] {
    try await withAppFailure {
      let response: PostgrestResponse<[PostMediaRecord]> = try await client
        .rpc("list_post_media", params: ListPostMediaParameters(postID: postID, cursor: cursor))
        .execute()
      return try response.value.map(PostMedia.init(databaseRecord:))
    }
  }

  func mediaURL(mediaID: UUID, objectPath: String, version: Int64) async throws -> URL {
    try await withAppFailure {
      try await signedURLs.value(for: .postMedia(mediaID: mediaID, version: version)) {
        try await client.storage.from("images").createSignedURL(
          path: objectPath,
          expiresIn: 3600,
          cacheNonce: String(version)
        )
      }
    }
  }

  func comments(postID: UUID, cursor: PostCommentCursor?) async throws -> [PostComment] {
    try await withAppFailure {
      let response: PostgrestResponse<[PostCommentRecord]> = try await client
        .rpc("list_post_comments", params: ListPostCommentsParameters(postID: postID, cursor: cursor))
        .execute()
      return try response.value.map(PostComment.init(databaseRecord:))
    }
  }

  func createComment(postID: UUID, body: String) async throws -> PostComment {
    try await withAppFailure {
      let response: PostgrestResponse<PostCommentRecord> = try await client
        .rpc("create_post_comment", params: CreatePostCommentParameters(postID: postID, body: body))
        .single()
        .execute()
      return try PostComment(databaseRecord: response.value)
    }
  }
}

private struct ReservePostMediaParameters: Encodable, Sendable {
  let postID: UUID
  let mediaID: UUID

  enum CodingKeys: String, CodingKey {
    case postID = "p_post_id"
    case mediaID = "p_media_id"
  }
}

private struct PostMediaIDParameters: Encodable, Sendable {
  let mediaID: UUID
  enum CodingKeys: String, CodingKey { case mediaID = "p_media_id" }
}

private struct ListPostMediaParameters: Encodable, Sendable {
  let postID: UUID
  let cursorAttachedAt: String?
  let cursorID: UUID?
  let limit = 30

  init(postID: UUID, cursor: PostMediaCursor?) {
    self.postID = postID
    cursorAttachedAt = cursor.map { CommunityEventDateCoding.dateTimeString($0.attachedAt) }
    cursorID = cursor?.mediaID
  }

  enum CodingKeys: String, CodingKey {
    case postID = "p_post_id"
    case cursorAttachedAt = "p_cursor_attached_at"
    case cursorID = "p_cursor_id"
    case limit = "p_limit"
  }
}

private struct ListPostCommentsParameters: Encodable, Sendable {
  let postID: UUID
  let cursorCreatedAt: String?
  let cursorID: UUID?
  let limit = 30

  init(postID: UUID, cursor: PostCommentCursor?) {
    self.postID = postID
    cursorCreatedAt = cursor.map { CommunityEventDateCoding.dateTimeString($0.createdAt) }
    cursorID = cursor?.commentID
  }

  enum CodingKeys: String, CodingKey {
    case postID = "p_post_id"
    case cursorCreatedAt = "p_cursor_created_at"
    case cursorID = "p_cursor_id"
    case limit = "p_limit"
  }
}

private struct CreatePostCommentParameters: Encodable, Sendable {
  let postID: UUID
  let body: String

  enum CodingKeys: String, CodingKey {
    case postID = "p_post_id"
    case body = "p_body"
  }
}

private struct PostMediaReservationRecord: Decodable, Sendable {
  let id: UUID
  let postID: UUID
  let uploaderID: UUID
  let objectPath: String
  let caption: String?
  let version: Int64
  let attachedAt: String?
  let expiresAt: String

  enum CodingKeys: String, CodingKey {
    case id, caption, version
    case postID = "post_id"
    case uploaderID = "uploader_id"
    case objectPath = "object_path"
    case attachedAt = "attached_at"
    case expiresAt = "expires_at"
  }
}

private struct PostMediaRecord: Decodable, Sendable {
  let id: UUID
  let postID: UUID
  let uploaderID: UUID
  let username: String
  let displayName: String
  let objectPath: String
  let caption: String?
  let version: Int64
  let attachedAt: String

  enum CodingKeys: String, CodingKey {
    case id, username, caption, version
    case postID = "post_id"
    case uploaderID = "uploader_id"
    case displayName = "display_name"
    case objectPath = "object_path"
    case attachedAt = "attached_at"
  }
}

private struct PostCommentRecord: Decodable, Sendable {
  let id: UUID
  let postID: UUID
  let authorID: UUID
  let username: String
  let displayName: String
  let body: String?
  let createdAt: String
  let updatedAt: String
  let deletedAt: String?

  enum CodingKeys: String, CodingKey {
    case id, username, body
    case postID = "post_id"
    case authorID = "author_id"
    case displayName = "display_name"
    case createdAt = "created_at"
    case updatedAt = "updated_at"
    case deletedAt = "deleted_at"
  }
}

private extension PostMediaReservation {
  init(databaseRecord: PostMediaReservationRecord) throws {
    guard let expiresAt = CommunityEventDateCoding.dateTime(from: databaseRecord.expiresAt) else {
      throw AppFailure.unexpected
    }
    self.init(
      mediaID: databaseRecord.id,
      postID: databaseRecord.postID,
      objectPath: databaseRecord.objectPath,
      expiresAt: expiresAt
    )
  }
}

private extension PostMedia {
  init(databaseRecord: PostMediaRecord) throws {
    guard let attachedAt = CommunityEventDateCoding.dateTime(from: databaseRecord.attachedAt) else {
      throw AppFailure.unexpected
    }
    self.init(
      id: databaseRecord.id,
      postID: databaseRecord.postID,
      uploaderID: databaseRecord.uploaderID,
      username: databaseRecord.username,
      displayName: databaseRecord.displayName,
      objectPath: databaseRecord.objectPath,
      caption: databaseRecord.caption,
      version: databaseRecord.version,
      attachedAt: attachedAt
    )
  }
}

private extension PostComment {
  init(databaseRecord: PostCommentRecord) throws {
    guard
      let createdAt = CommunityEventDateCoding.dateTime(from: databaseRecord.createdAt),
      let updatedAt = CommunityEventDateCoding.dateTime(from: databaseRecord.updatedAt)
    else {
      throw AppFailure.unexpected
    }
    let deletedAt = try databaseRecord.deletedAt.map {
      guard let date = CommunityEventDateCoding.dateTime(from: $0) else {
        throw AppFailure.unexpected
      }
      return date
    }
    self.init(
      id: databaseRecord.id,
      postID: databaseRecord.postID,
      authorID: databaseRecord.authorID,
      username: databaseRecord.username,
      displayName: databaseRecord.displayName,
      body: databaseRecord.body,
      createdAt: createdAt,
      updatedAt: updatedAt,
      deletedAt: deletedAt
    )
  }
}
