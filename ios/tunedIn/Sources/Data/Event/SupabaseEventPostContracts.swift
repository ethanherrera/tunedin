import Foundation

struct ListCatalogEventPostsParameters: Encodable, Equatable, Sendable {
  let eventID: UUID
  let scope: String
  let cursor: [String: String]?
  let limit: Int

  init(
    eventID: UUID,
    scope: String = "all",
    cursor: [String: String]? = nil,
    limit: Int = 30
  ) {
    self.eventID = eventID
    self.scope = scope
    self.cursor = cursor
    self.limit = limit
  }

  enum CodingKeys: String, CodingKey {
    case eventID = "p_event_id"
    case scope = "p_scope"
    case cursor = "p_cursor"
    case limit = "p_limit"
  }
}

struct UpsertCatalogEventPostParameters: Encodable, Equatable, Sendable {
  let eventID: UUID
  let overallScore: Double?
  let performanceScore: Double?
  let note: String?
  let audience: EventAudience
  let publish: Bool

  init(eventID: UUID, input: EventPostInput, publish: Bool = true) {
    self.eventID = eventID
    overallScore = input.score
    performanceScore = input.performanceScore
    note = CatalogInput.optionalNormalizedText(input.note ?? "")
    audience = input.audience
    self.publish = publish
  }

  enum CodingKeys: String, CodingKey {
    case eventID = "p_event_id"
    case overallScore = "p_overall_score"
    case performanceScore = "p_performance_score"
    case note = "p_note"
    case audience = "p_audience"
    case publish = "p_publish"
  }
}

struct UpsertCatalogEventPostRPCRecord: Decodable, Equatable, Sendable {
  let postID: UUID
  let eventID: UUID
  let publishedAt: String?

  enum CodingKeys: String, CodingKey {
    case postID = "post_id"
    case eventID = "event_id"
    case publishedAt = "published_at"
  }
}

struct CatalogEventProfileAttendanceParameters: Encodable, Equatable, Sendable {
  let profileID: UUID
  let state: EventAttendanceStatus
  let cursor: [String: String]?
  let limit: Int

  init(
    profileID: UUID,
    state: EventAttendanceStatus,
    cursor: [String: String]? = nil,
    limit: Int = 50
  ) {
    self.profileID = profileID
    self.state = state
    self.cursor = cursor
    self.limit = limit
  }

  enum CodingKeys: String, CodingKey {
    case profileID = "p_profile_id"
    case state = "p_state"
    case cursor = "p_cursor"
    case limit = "p_limit"
  }
}

struct CatalogEventProfileHistoryParameters: Encodable, Equatable, Sendable {
  let profileID: UUID
  let cursor: [String: String]?
  let limit: Int

  init(profileID: UUID, cursor: [String: String]? = nil, limit: Int = 50) {
    self.profileID = profileID
    self.cursor = cursor
    self.limit = limit
  }

  enum CodingKeys: String, CodingKey {
    case profileID = "p_profile_id"
    case cursor = "p_cursor"
    case limit = "p_limit"
  }
}

struct CatalogEventPostSummaryRPCRecord: Decodable, Equatable, Sendable {
  let eventID: UUID
  let postCount: Int64
  let averageScore: Double?

  enum CodingKeys: String, CodingKey {
    case eventID = "event_id"
    case postCount = "post_count"
    case averageScore = "average_score"
  }
}

struct CatalogEventPostRPCRecord: Decodable, Equatable, Sendable {
  let postID: UUID
  let authorID: UUID
  let authorUsername: String
  let authorDisplayName: String
  let authorRelationship: String
  let authorAvatarObjectPath: String?
  let authorAvatarVersion: Int64
  let overallScore: Double?
  let performanceScore: Double?
  let note: String?
  let photoCount: Int64
  let videoCount: Int64
  let commentCount: Int64
  let audience: EventAudience
  let publishedAt: String
  let nextCursor: CatalogEventPostCursorRPCRecord?

  enum CodingKeys: String, CodingKey {
    case audience
    case postID = "post_id"
    case authorID = "author_id"
    case authorUsername = "author_username"
    case authorDisplayName = "author_display_name"
    case authorRelationship = "author_relationship"
    case authorAvatarObjectPath = "author_avatar_object_path"
    case authorAvatarVersion = "author_avatar_version"
    case overallScore = "overall_score"
    case performanceScore = "performance_score"
    case note
    case photoCount = "photo_count"
    case videoCount = "video_count"
    case commentCount = "comment_count"
    case publishedAt = "published_at"
    case nextCursor = "next_cursor"
  }
}

struct CatalogEventPostCursorRPCRecord: Decodable, Equatable, Sendable {
  let publishedAt: String
  let postID: UUID

  enum CodingKeys: String, CodingKey {
    case publishedAt = "published_at"
    case postID = "post_id"
  }
}

struct CatalogEventProfileHistoryRPCRecord: Decodable, Equatable, Sendable {
  let historyKind: String
  let event: CatalogEventRPCRecord
  let post: CatalogEventPostRPCRecord?
  let occurredAt: String

  enum CodingKeys: String, CodingKey {
    case event, post
    case historyKind = "history_kind"
    case occurredAt = "occurred_at"
  }
}

struct CatalogEventProfileAttendanceRPCRecord: Decodable, Equatable, Sendable {
  let attendanceID: UUID
  let event: CatalogEventRPCRecord
  let status: EventAttendanceStatus
  let audience: EventAudience
  let occurredAt: String

  enum CodingKeys: String, CodingKey {
    case event, status, audience
    case attendanceID = "attendance_id"
    case occurredAt = "occurred_at"
  }
}

extension EventPostPreview {
  init(databaseRecord: CatalogEventPostRPCRecord) throws {
    guard let publishedAt = CommunityEventDateCoding.dateTime(from: databaseRecord.publishedAt) else {
      throw AppFailure.unexpected
    }
    self.init(
      id: databaseRecord.postID,
      author: SocialProfile(
        id: databaseRecord.authorID,
        username: databaseRecord.authorUsername,
        displayName: databaseRecord.authorDisplayName,
        relationship: RelationshipState(rawValue: databaseRecord.authorRelationship) ?? .none,
        avatarObjectPath: databaseRecord.authorAvatarObjectPath,
        avatarVersion: databaseRecord.authorAvatarVersion
      ),
      score: databaseRecord.overallScore,
      performanceScore: databaseRecord.performanceScore,
      note: databaseRecord.note,
      photoCount: Int(databaseRecord.photoCount),
      videoCount: Int(databaseRecord.videoCount),
      commentCount: Int(databaseRecord.commentCount),
      audience: databaseRecord.audience,
      publishedAt: publishedAt
    )
  }
}

extension EventPostCursor {
  var requestValue: [String: String] {
    [
      "published_at": CommunityEventDateCoding.dateTimeString(publishedAt),
      "post_id": postID.uuidString
    ]
  }
}

extension CatalogEventPostRPCRecord {
  func postCursor() throws -> EventPostCursor? {
    guard let nextCursor else { return nil }
    guard let publishedAt = CommunityEventDateCoding.dateTime(from: nextCursor.publishedAt) else {
      throw AppFailure.unexpected
    }
    return EventPostCursor(publishedAt: publishedAt, postID: nextCursor.postID)
  }
}
