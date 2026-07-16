import Foundation

struct ListCatalogEventDiariesParameters: Encodable, Equatable, Sendable {
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

struct UpsertCatalogEventDiaryParameters: Encodable, Equatable, Sendable {
  let eventID: UUID
  let overallScore: Double?
  let performanceScore: Double?
  let reviewBody: String?
  let audience: EventAudience
  let publish = true

  init(eventID: UUID, input: EventDiaryInput) {
    self.eventID = eventID
    overallScore = input.score
    performanceScore = input.performanceScore
    reviewBody = CatalogInput.optionalNormalizedText(input.note ?? "")
    audience = input.audience
  }

  enum CodingKeys: String, CodingKey {
    case eventID = "p_event_id"
    case overallScore = "p_overall_score"
    case performanceScore = "p_performance_score"
    case reviewBody = "p_review_body"
    case audience = "p_audience"
    case publish = "p_publish"
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

struct CatalogEventDiarySummaryRPCRecord: Decodable, Equatable, Sendable {
  let eventID: UUID
  let diaryCount: Int64
  let averageScore: Double?

  enum CodingKeys: String, CodingKey {
    case eventID = "event_id"
    case diaryCount = "diary_count"
    case averageScore = "average_score"
  }
}

struct CatalogEventDiaryRPCRecord: Decodable, Equatable, Sendable {
  let diaryID: UUID
  let authorID: UUID
  let authorUsername: String
  let authorDisplayName: String
  let authorRelationship: String
  let authorAvatarObjectPath: String?
  let authorAvatarVersion: Int64
  let overallScore: Double?
  let performanceScore: Double?
  let reviewBody: String?
  let photoCount: Int64
  let videoCount: Int64
  let commentCount: Int64
  let audience: EventAudience
  let publishedAt: String

  enum CodingKeys: String, CodingKey {
    case audience
    case diaryID = "diary_id"
    case authorID = "author_id"
    case authorUsername = "author_username"
    case authorDisplayName = "author_display_name"
    case authorRelationship = "author_relationship"
    case authorAvatarObjectPath = "author_avatar_object_path"
    case authorAvatarVersion = "author_avatar_version"
    case overallScore = "overall_score"
    case performanceScore = "performance_score"
    case reviewBody = "review_body"
    case photoCount = "photo_count"
    case videoCount = "video_count"
    case commentCount = "comment_count"
    case publishedAt = "published_at"
  }
}

struct CatalogEventProfileHistoryRPCRecord: Decodable, Equatable, Sendable {
  let historyKind: String
  let event: CatalogEventRPCRecord
  let diary: CatalogEventDiaryRPCRecord?
  let occurredAt: String

  enum CodingKeys: String, CodingKey {
    case event, diary
    case historyKind = "history_kind"
    case occurredAt = "occurred_at"
  }
}

extension EventDiaryPreview {
  init(databaseRecord: CatalogEventDiaryRPCRecord) throws {
    guard let publishedAt = CommunityEventDateCoding.dateTime(from: databaseRecord.publishedAt) else {
      throw AppFailure.unexpected
    }
    self.init(
      id: databaseRecord.diaryID,
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
      note: databaseRecord.reviewBody,
      photoCount: Int(databaseRecord.photoCount),
      videoCount: Int(databaseRecord.videoCount),
      commentCount: Int(databaseRecord.commentCount),
      audience: databaseRecord.audience,
      publishedAt: publishedAt
    )
  }
}
