import Foundation
import Supabase

public enum PublicSchema {
  public enum ConcertEventType: String, Codable, Hashable, Sendable {
    case concertCreated = "concert_created"
    case concertUpdated = "concert_updated"
    case setlistUpdated = "setlist_updated"
    case collaboratorTagged = "collaborator_tagged"
    case collaboratorRemoved = "collaborator_removed"
    case visibilityChanged = "visibility_changed"
    case ownershipTransferred = "ownership_transferred"
    case commentAdded = "comment_added"
    case commentUpdated = "comment_updated"
    case commentDeleted = "comment_deleted"
    case albumPhotoAdded = "album_photo_added"
  }
  public enum ConcertPhotoStatus: String, Codable, Hashable, Sendable {
    case pending = "pending"
    case ready = "ready"
    case deleting = "deleting"
  }
  public enum ConcertVisibility: String, Codable, Hashable, Sendable {
    case `private` = "private"
    case collaborators = "collaborators"
    case friends = "friends"
  }
  public enum ProductFeedbackCategory: String, Codable, Hashable, Sendable {
    case bug = "bug"
    case idea = "idea"
    case other = "other"
  }
  public enum RelationshipStatus: String, Codable, Hashable, Sendable {
    case pending = "pending"
    case accepted = "accepted"
    case declined = "declined"
    case blocked = "blocked"
  }
  public struct CommentsSelect: Codable, Hashable, Sendable {
    public let authorId: UUID
    public let body: String?
    public let concertId: UUID
    public let createdAt: String
    public let deletedAt: String?
    public let id: UUID
    public let updatedAt: String
    public enum CodingKeys: String, CodingKey {
      case authorId = "author_id"
      case body = "body"
      case concertId = "concert_id"
      case createdAt = "created_at"
      case deletedAt = "deleted_at"
      case id = "id"
      case updatedAt = "updated_at"
    }
  }
  public struct CommentsInsert: Codable, Hashable, Sendable {
    public let authorId: UUID
    public let body: String?
    public let concertId: UUID
    public let createdAt: String?
    public let deletedAt: String?
    public let id: UUID?
    public let updatedAt: String?
    public enum CodingKeys: String, CodingKey {
      case authorId = "author_id"
      case body = "body"
      case concertId = "concert_id"
      case createdAt = "created_at"
      case deletedAt = "deleted_at"
      case id = "id"
      case updatedAt = "updated_at"
    }
  }
  public struct CommentsUpdate: Codable, Hashable, Sendable {
    public let authorId: UUID?
    public let body: String?
    public let concertId: UUID?
    public let createdAt: String?
    public let deletedAt: String?
    public let id: UUID?
    public let updatedAt: String?
    public enum CodingKeys: String, CodingKey {
      case authorId = "author_id"
      case body = "body"
      case concertId = "concert_id"
      case createdAt = "created_at"
      case deletedAt = "deleted_at"
      case id = "id"
      case updatedAt = "updated_at"
    }
  }
  public struct ConcertArtistsSelect: Codable, Hashable, Sendable {
    public let artistName: String
    public let concertId: UUID
    public let createdAt: String
    public let id: UUID
    public let isPrimary: Bool
    public let lineupPosition: Int16
    public let updatedAt: String
    public enum CodingKeys: String, CodingKey {
      case artistName = "artist_name"
      case concertId = "concert_id"
      case createdAt = "created_at"
      case id = "id"
      case isPrimary = "is_primary"
      case lineupPosition = "lineup_position"
      case updatedAt = "updated_at"
    }
  }
  public struct ConcertArtistsInsert: Codable, Hashable, Sendable {
    public let artistName: String
    public let concertId: UUID
    public let createdAt: String?
    public let id: UUID?
    public let isPrimary: Bool?
    public let lineupPosition: Int16
    public let updatedAt: String?
    public enum CodingKeys: String, CodingKey {
      case artistName = "artist_name"
      case concertId = "concert_id"
      case createdAt = "created_at"
      case id = "id"
      case isPrimary = "is_primary"
      case lineupPosition = "lineup_position"
      case updatedAt = "updated_at"
    }
  }
  public struct ConcertArtistsUpdate: Codable, Hashable, Sendable {
    public let artistName: String?
    public let concertId: UUID?
    public let createdAt: String?
    public let id: UUID?
    public let isPrimary: Bool?
    public let lineupPosition: Int16?
    public let updatedAt: String?
    public enum CodingKeys: String, CodingKey {
      case artistName = "artist_name"
      case concertId = "concert_id"
      case createdAt = "created_at"
      case id = "id"
      case isPrimary = "is_primary"
      case lineupPosition = "lineup_position"
      case updatedAt = "updated_at"
    }
  }
  public struct ConcertCollaboratorsSelect: Codable, Hashable, Sendable {
    public let concertId: UUID
    public let createdAt: String
    public let profileId: UUID
    public let taggedBy: UUID
    public let updatedAt: String
    public enum CodingKeys: String, CodingKey {
      case concertId = "concert_id"
      case createdAt = "created_at"
      case profileId = "profile_id"
      case taggedBy = "tagged_by"
      case updatedAt = "updated_at"
    }
  }
  public struct ConcertCollaboratorsInsert: Codable, Hashable, Sendable {
    public let concertId: UUID
    public let createdAt: String?
    public let profileId: UUID
    public let taggedBy: UUID
    public let updatedAt: String?
    public enum CodingKeys: String, CodingKey {
      case concertId = "concert_id"
      case createdAt = "created_at"
      case profileId = "profile_id"
      case taggedBy = "tagged_by"
      case updatedAt = "updated_at"
    }
  }
  public struct ConcertCollaboratorsUpdate: Codable, Hashable, Sendable {
    public let concertId: UUID?
    public let createdAt: String?
    public let profileId: UUID?
    public let taggedBy: UUID?
    public let updatedAt: String?
    public enum CodingKeys: String, CodingKey {
      case concertId = "concert_id"
      case createdAt = "created_at"
      case profileId = "profile_id"
      case taggedBy = "tagged_by"
      case updatedAt = "updated_at"
    }
  }
  public struct ConcertEventsSelect: Codable, Hashable, Sendable {
    public let actorId: UUID
    public let concertId: UUID
    public let eventType: ConcertEventType
    public let id: UUID
    public let metadata: AnyJSON
    public let occurredAt: String
    public let subjectId: UUID?
    public enum CodingKeys: String, CodingKey {
      case actorId = "actor_id"
      case concertId = "concert_id"
      case eventType = "event_type"
      case id = "id"
      case metadata = "metadata"
      case occurredAt = "occurred_at"
      case subjectId = "subject_id"
    }
  }
  public struct ConcertEventsInsert: Codable, Hashable, Sendable {
    public let actorId: UUID
    public let concertId: UUID
    public let eventType: ConcertEventType
    public let id: UUID?
    public let metadata: AnyJSON?
    public let occurredAt: String?
    public let subjectId: UUID?
    public enum CodingKeys: String, CodingKey {
      case actorId = "actor_id"
      case concertId = "concert_id"
      case eventType = "event_type"
      case id = "id"
      case metadata = "metadata"
      case occurredAt = "occurred_at"
      case subjectId = "subject_id"
    }
  }
  public struct ConcertEventsUpdate: Codable, Hashable, Sendable {
    public let actorId: UUID?
    public let concertId: UUID?
    public let eventType: ConcertEventType?
    public let id: UUID?
    public let metadata: AnyJSON?
    public let occurredAt: String?
    public let subjectId: UUID?
    public enum CodingKeys: String, CodingKey {
      case actorId = "actor_id"
      case concertId = "concert_id"
      case eventType = "event_type"
      case id = "id"
      case metadata = "metadata"
      case occurredAt = "occurred_at"
      case subjectId = "subject_id"
    }
  }
  public struct ConcertPhotosSelect: Codable, Hashable, Sendable {
    public let attachedAt: String?
    public let caption: String?
    public let concertId: UUID
    public let createdAt: String
    public let deletedAt: String?
    public let deletionRequestedAt: String?
    public let expiresAt: String
    public let id: UUID
    public let objectPath: String
    public let status: ConcertPhotoStatus
    public let uploaderId: UUID
    public let version: Int64
    public enum CodingKeys: String, CodingKey {
      case attachedAt = "attached_at"
      case caption = "caption"
      case concertId = "concert_id"
      case createdAt = "created_at"
      case deletedAt = "deleted_at"
      case deletionRequestedAt = "deletion_requested_at"
      case expiresAt = "expires_at"
      case id = "id"
      case objectPath = "object_path"
      case status = "status"
      case uploaderId = "uploader_id"
      case version = "version"
    }
  }
  public struct ConcertPhotosInsert: Codable, Hashable, Sendable {
    public let attachedAt: String?
    public let caption: String?
    public let concertId: UUID
    public let createdAt: String?
    public let deletedAt: String?
    public let deletionRequestedAt: String?
    public let expiresAt: String?
    public let id: UUID?
    public let objectPath: String
    public let status: ConcertPhotoStatus?
    public let uploaderId: UUID
    public let version: Int64?
    public enum CodingKeys: String, CodingKey {
      case attachedAt = "attached_at"
      case caption = "caption"
      case concertId = "concert_id"
      case createdAt = "created_at"
      case deletedAt = "deleted_at"
      case deletionRequestedAt = "deletion_requested_at"
      case expiresAt = "expires_at"
      case id = "id"
      case objectPath = "object_path"
      case status = "status"
      case uploaderId = "uploader_id"
      case version = "version"
    }
  }
  public struct ConcertPhotosUpdate: Codable, Hashable, Sendable {
    public let attachedAt: String?
    public let caption: String?
    public let concertId: UUID?
    public let createdAt: String?
    public let deletedAt: String?
    public let deletionRequestedAt: String?
    public let expiresAt: String?
    public let id: UUID?
    public let objectPath: String?
    public let status: ConcertPhotoStatus?
    public let uploaderId: UUID?
    public let version: Int64?
    public enum CodingKeys: String, CodingKey {
      case attachedAt = "attached_at"
      case caption = "caption"
      case concertId = "concert_id"
      case createdAt = "created_at"
      case deletedAt = "deleted_at"
      case deletionRequestedAt = "deletion_requested_at"
      case expiresAt = "expires_at"
      case id = "id"
      case objectPath = "object_path"
      case status = "status"
      case uploaderId = "uploader_id"
      case version = "version"
    }
  }
  public struct ConcertsSelect: Codable, Hashable, Sendable {
    public let city: String?
    public let concertDate: String
    public let createdAt: String
    public let deletionRequestedAt: String?
    public let deletionStatus: String
    public let id: UUID
    public let lastActivityAt: String
    public let ownerId: UUID
    public let photoObjectPath: String?
    public let photoVersion: Int64
    public let startsAt: String?
    public let tour: String?
    public let updatedAt: String
    public let venueName: String
    public let venueTimeZone: String?
    public let version: Int64
    public let visibility: ConcertVisibility
    public enum CodingKeys: String, CodingKey {
      case city = "city"
      case concertDate = "concert_date"
      case createdAt = "created_at"
      case deletionRequestedAt = "deletion_requested_at"
      case deletionStatus = "deletion_status"
      case id = "id"
      case lastActivityAt = "last_activity_at"
      case ownerId = "owner_id"
      case photoObjectPath = "photo_object_path"
      case photoVersion = "photo_version"
      case startsAt = "starts_at"
      case tour = "tour"
      case updatedAt = "updated_at"
      case venueName = "venue_name"
      case venueTimeZone = "venue_time_zone"
      case version = "version"
      case visibility = "visibility"
    }
  }
  public struct ConcertsInsert: Codable, Hashable, Sendable {
    public let city: String?
    public let concertDate: String
    public let createdAt: String?
    public let deletionRequestedAt: String?
    public let deletionStatus: String?
    public let id: UUID?
    public let lastActivityAt: String?
    public let ownerId: UUID
    public let photoObjectPath: String?
    public let photoVersion: Int64?
    public let startsAt: String?
    public let tour: String?
    public let updatedAt: String?
    public let venueName: String
    public let venueTimeZone: String?
    public let version: Int64?
    public let visibility: ConcertVisibility?
    public enum CodingKeys: String, CodingKey {
      case city = "city"
      case concertDate = "concert_date"
      case createdAt = "created_at"
      case deletionRequestedAt = "deletion_requested_at"
      case deletionStatus = "deletion_status"
      case id = "id"
      case lastActivityAt = "last_activity_at"
      case ownerId = "owner_id"
      case photoObjectPath = "photo_object_path"
      case photoVersion = "photo_version"
      case startsAt = "starts_at"
      case tour = "tour"
      case updatedAt = "updated_at"
      case venueName = "venue_name"
      case venueTimeZone = "venue_time_zone"
      case version = "version"
      case visibility = "visibility"
    }
  }
  public struct ConcertsUpdate: Codable, Hashable, Sendable {
    public let city: String?
    public let concertDate: String?
    public let createdAt: String?
    public let deletionRequestedAt: String?
    public let deletionStatus: String?
    public let id: UUID?
    public let lastActivityAt: String?
    public let ownerId: UUID?
    public let photoObjectPath: String?
    public let photoVersion: Int64?
    public let startsAt: String?
    public let tour: String?
    public let updatedAt: String?
    public let venueName: String?
    public let venueTimeZone: String?
    public let version: Int64?
    public let visibility: ConcertVisibility?
    public enum CodingKeys: String, CodingKey {
      case city = "city"
      case concertDate = "concert_date"
      case createdAt = "created_at"
      case deletionRequestedAt = "deletion_requested_at"
      case deletionStatus = "deletion_status"
      case id = "id"
      case lastActivityAt = "last_activity_at"
      case ownerId = "owner_id"
      case photoObjectPath = "photo_object_path"
      case photoVersion = "photo_version"
      case startsAt = "starts_at"
      case tour = "tour"
      case updatedAt = "updated_at"
      case venueName = "venue_name"
      case venueTimeZone = "venue_time_zone"
      case version = "version"
      case visibility = "visibility"
    }
  }
  public struct DirectCollaborationNotificationsSelect: Codable, Hashable, Sendable {
    public let activityCount: Int32
    public let actorId: UUID
    public let concertId: UUID
    public let createdAt: String
    public let deliveredAt: String?
    public let firstActivityAt: String
    public let id: UUID
    public let kind: String
    public let latestActivityAt: String
    public let recipientId: UUID
    public let summaryDueAt: String
    public enum CodingKeys: String, CodingKey {
      case activityCount = "activity_count"
      case actorId = "actor_id"
      case concertId = "concert_id"
      case createdAt = "created_at"
      case deliveredAt = "delivered_at"
      case firstActivityAt = "first_activity_at"
      case id = "id"
      case kind = "kind"
      case latestActivityAt = "latest_activity_at"
      case recipientId = "recipient_id"
      case summaryDueAt = "summary_due_at"
    }
  }
  public struct DirectCollaborationNotificationsInsert: Codable, Hashable, Sendable {
    public let activityCount: Int32?
    public let actorId: UUID
    public let concertId: UUID
    public let createdAt: String?
    public let deliveredAt: String?
    public let firstActivityAt: String?
    public let id: UUID?
    public let kind: String
    public let latestActivityAt: String?
    public let recipientId: UUID
    public let summaryDueAt: String?
    public enum CodingKeys: String, CodingKey {
      case activityCount = "activity_count"
      case actorId = "actor_id"
      case concertId = "concert_id"
      case createdAt = "created_at"
      case deliveredAt = "delivered_at"
      case firstActivityAt = "first_activity_at"
      case id = "id"
      case kind = "kind"
      case latestActivityAt = "latest_activity_at"
      case recipientId = "recipient_id"
      case summaryDueAt = "summary_due_at"
    }
  }
  public struct DirectCollaborationNotificationsUpdate: Codable, Hashable, Sendable {
    public let activityCount: Int32?
    public let actorId: UUID?
    public let concertId: UUID?
    public let createdAt: String?
    public let deliveredAt: String?
    public let firstActivityAt: String?
    public let id: UUID?
    public let kind: String?
    public let latestActivityAt: String?
    public let recipientId: UUID?
    public let summaryDueAt: String?
    public enum CodingKeys: String, CodingKey {
      case activityCount = "activity_count"
      case actorId = "actor_id"
      case concertId = "concert_id"
      case createdAt = "created_at"
      case deliveredAt = "delivered_at"
      case firstActivityAt = "first_activity_at"
      case id = "id"
      case kind = "kind"
      case latestActivityAt = "latest_activity_at"
      case recipientId = "recipient_id"
      case summaryDueAt = "summary_due_at"
    }
  }
  public struct ProductFeedbackSelect: Codable, Hashable, Sendable {
    public let appEnvironment: String
    public let buildNumber: String
    public let category: ProductFeedbackCategory
    public let createdAt: String
    public let expiresAt: String
    public let gitSha: String
    public let id: UUID
    public let message: String
    public let originatingScreen: String
    public let releaseVersion: String
    public let submitterId: UUID
    public enum CodingKeys: String, CodingKey {
      case appEnvironment = "app_environment"
      case buildNumber = "build_number"
      case category = "category"
      case createdAt = "created_at"
      case expiresAt = "expires_at"
      case gitSha = "git_sha"
      case id = "id"
      case message = "message"
      case originatingScreen = "originating_screen"
      case releaseVersion = "release_version"
      case submitterId = "submitter_id"
    }
  }
  public struct ProductFeedbackInsert: Codable, Hashable, Sendable {
    public let appEnvironment: String
    public let buildNumber: String
    public let category: ProductFeedbackCategory
    public let createdAt: String?
    public let expiresAt: String?
    public let gitSha: String
    public let id: UUID?
    public let message: String
    public let originatingScreen: String
    public let releaseVersion: String
    public let submitterId: UUID
    public enum CodingKeys: String, CodingKey {
      case appEnvironment = "app_environment"
      case buildNumber = "build_number"
      case category = "category"
      case createdAt = "created_at"
      case expiresAt = "expires_at"
      case gitSha = "git_sha"
      case id = "id"
      case message = "message"
      case originatingScreen = "originating_screen"
      case releaseVersion = "release_version"
      case submitterId = "submitter_id"
    }
  }
  public struct ProductFeedbackUpdate: Codable, Hashable, Sendable {
    public let appEnvironment: String?
    public let buildNumber: String?
    public let category: ProductFeedbackCategory?
    public let createdAt: String?
    public let expiresAt: String?
    public let gitSha: String?
    public let id: UUID?
    public let message: String?
    public let originatingScreen: String?
    public let releaseVersion: String?
    public let submitterId: UUID?
    public enum CodingKeys: String, CodingKey {
      case appEnvironment = "app_environment"
      case buildNumber = "build_number"
      case category = "category"
      case createdAt = "created_at"
      case expiresAt = "expires_at"
      case gitSha = "git_sha"
      case id = "id"
      case message = "message"
      case originatingScreen = "originating_screen"
      case releaseVersion = "release_version"
      case submitterId = "submitter_id"
    }
  }
  public struct ProfilesSelect: Codable, Hashable, Sendable {
    public let avatarObjectPath: String?
    public let avatarVersion: Int64
    public let createdAt: String
    public let displayName: String?
    public let id: UUID
    public let onboardingCompletedAt: String?
    public let updatedAt: String
    public let username: String?
    public enum CodingKeys: String, CodingKey {
      case avatarObjectPath = "avatar_object_path"
      case avatarVersion = "avatar_version"
      case createdAt = "created_at"
      case displayName = "display_name"
      case id = "id"
      case onboardingCompletedAt = "onboarding_completed_at"
      case updatedAt = "updated_at"
      case username = "username"
    }
  }
  public struct ProfilesInsert: Codable, Hashable, Sendable {
    public let avatarObjectPath: String?
    public let avatarVersion: Int64?
    public let createdAt: String?
    public let displayName: String?
    public let id: UUID
    public let onboardingCompletedAt: String?
    public let updatedAt: String?
    public let username: String?
    public enum CodingKeys: String, CodingKey {
      case avatarObjectPath = "avatar_object_path"
      case avatarVersion = "avatar_version"
      case createdAt = "created_at"
      case displayName = "display_name"
      case id = "id"
      case onboardingCompletedAt = "onboarding_completed_at"
      case updatedAt = "updated_at"
      case username = "username"
    }
  }
  public struct ProfilesUpdate: Codable, Hashable, Sendable {
    public let avatarObjectPath: String?
    public let avatarVersion: Int64?
    public let createdAt: String?
    public let displayName: String?
    public let id: UUID?
    public let onboardingCompletedAt: String?
    public let updatedAt: String?
    public let username: String?
    public enum CodingKeys: String, CodingKey {
      case avatarObjectPath = "avatar_object_path"
      case avatarVersion = "avatar_version"
      case createdAt = "created_at"
      case displayName = "display_name"
      case id = "id"
      case onboardingCompletedAt = "onboarding_completed_at"
      case updatedAt = "updated_at"
      case username = "username"
    }
  }
  public struct RelationshipsSelect: Codable, Hashable, Sendable {
    public let blockerId: UUID?
    public let createdAt: String
    public let initiatorId: UUID
    public let requestedAt: String
    public let respondedAt: String?
    public let responderId: UUID?
    public let status: RelationshipStatus
    public let updatedAt: String
    public let userHighId: UUID
    public let userLowId: UUID
    public enum CodingKeys: String, CodingKey {
      case blockerId = "blocker_id"
      case createdAt = "created_at"
      case initiatorId = "initiator_id"
      case requestedAt = "requested_at"
      case respondedAt = "responded_at"
      case responderId = "responder_id"
      case status = "status"
      case updatedAt = "updated_at"
      case userHighId = "user_high_id"
      case userLowId = "user_low_id"
    }
  }
  public struct RelationshipsInsert: Codable, Hashable, Sendable {
    public let blockerId: UUID?
    public let createdAt: String?
    public let initiatorId: UUID
    public let requestedAt: String?
    public let respondedAt: String?
    public let responderId: UUID?
    public let status: RelationshipStatus
    public let updatedAt: String?
    public let userHighId: UUID
    public let userLowId: UUID
    public enum CodingKeys: String, CodingKey {
      case blockerId = "blocker_id"
      case createdAt = "created_at"
      case initiatorId = "initiator_id"
      case requestedAt = "requested_at"
      case respondedAt = "responded_at"
      case responderId = "responder_id"
      case status = "status"
      case updatedAt = "updated_at"
      case userHighId = "user_high_id"
      case userLowId = "user_low_id"
    }
  }
  public struct RelationshipsUpdate: Codable, Hashable, Sendable {
    public let blockerId: UUID?
    public let createdAt: String?
    public let initiatorId: UUID?
    public let requestedAt: String?
    public let respondedAt: String?
    public let responderId: UUID?
    public let status: RelationshipStatus?
    public let updatedAt: String?
    public let userHighId: UUID?
    public let userLowId: UUID?
    public enum CodingKeys: String, CodingKey {
      case blockerId = "blocker_id"
      case createdAt = "created_at"
      case initiatorId = "initiator_id"
      case requestedAt = "requested_at"
      case respondedAt = "responded_at"
      case responderId = "responder_id"
      case status = "status"
      case updatedAt = "updated_at"
      case userHighId = "user_high_id"
      case userLowId = "user_low_id"
    }
  }
  public struct SetlistItemsSelect: Codable, Hashable, Sendable {
    public let concertId: UUID
    public let createdAt: String
    public let id: UUID
    public let setPosition: Int16
    public let songTitle: String
    public let updatedAt: String
    public enum CodingKeys: String, CodingKey {
      case concertId = "concert_id"
      case createdAt = "created_at"
      case id = "id"
      case setPosition = "set_position"
      case songTitle = "song_title"
      case updatedAt = "updated_at"
    }
  }
  public struct SetlistItemsInsert: Codable, Hashable, Sendable {
    public let concertId: UUID
    public let createdAt: String?
    public let id: UUID?
    public let setPosition: Int16
    public let songTitle: String
    public let updatedAt: String?
    public enum CodingKeys: String, CodingKey {
      case concertId = "concert_id"
      case createdAt = "created_at"
      case id = "id"
      case setPosition = "set_position"
      case songTitle = "song_title"
      case updatedAt = "updated_at"
    }
  }
  public struct SetlistItemsUpdate: Codable, Hashable, Sendable {
    public let concertId: UUID?
    public let createdAt: String?
    public let id: UUID?
    public let setPosition: Int16?
    public let songTitle: String?
    public let updatedAt: String?
    public enum CodingKeys: String, CodingKey {
      case concertId = "concert_id"
      case createdAt = "created_at"
      case id = "id"
      case setPosition = "set_position"
      case songTitle = "song_title"
      case updatedAt = "updated_at"
    }
  }
}
