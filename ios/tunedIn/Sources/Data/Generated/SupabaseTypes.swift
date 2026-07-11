import Foundation
import Supabase

public enum PublicSchema {
  public enum ConcertEventType: String, Codable, Hashable, Sendable {
    case concertCreated = "concert_created"
  }
  public enum ConcertVisibility: String, Codable, Hashable, Sendable {
    case `private` = "private"
    case collaborators = "collaborators"
    case friends = "friends"
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
  public struct ConcertEventsSelect: Codable, Hashable, Sendable {
    public let actorId: UUID
    public let concertId: UUID
    public let eventType: ConcertEventType
    public let id: UUID
    public let occurredAt: String
    public enum CodingKeys: String, CodingKey {
      case actorId = "actor_id"
      case concertId = "concert_id"
      case eventType = "event_type"
      case id = "id"
      case occurredAt = "occurred_at"
    }
  }
  public struct ConcertEventsInsert: Codable, Hashable, Sendable {
    public let actorId: UUID
    public let concertId: UUID
    public let eventType: ConcertEventType
    public let id: UUID?
    public let occurredAt: String?
    public enum CodingKeys: String, CodingKey {
      case actorId = "actor_id"
      case concertId = "concert_id"
      case eventType = "event_type"
      case id = "id"
      case occurredAt = "occurred_at"
    }
  }
  public struct ConcertEventsUpdate: Codable, Hashable, Sendable {
    public let actorId: UUID?
    public let concertId: UUID?
    public let eventType: ConcertEventType?
    public let id: UUID?
    public let occurredAt: String?
    public enum CodingKeys: String, CodingKey {
      case actorId = "actor_id"
      case concertId = "concert_id"
      case eventType = "event_type"
      case id = "id"
      case occurredAt = "occurred_at"
    }
  }
  public struct ConcertsSelect: Codable, Hashable, Sendable {
    public let city: String?
    public let concertDate: String
    public let createdAt: String
    public let id: UUID
    public let lastActivityAt: String
    public let ownerId: UUID
    public let startsAt: String?
    public let tour: String?
    public let updatedAt: String
    public let venueName: String
    public let venueTimeZone: String?
    public let visibility: ConcertVisibility
    public enum CodingKeys: String, CodingKey {
      case city = "city"
      case concertDate = "concert_date"
      case createdAt = "created_at"
      case id = "id"
      case lastActivityAt = "last_activity_at"
      case ownerId = "owner_id"
      case startsAt = "starts_at"
      case tour = "tour"
      case updatedAt = "updated_at"
      case venueName = "venue_name"
      case venueTimeZone = "venue_time_zone"
      case visibility = "visibility"
    }
  }
  public struct ConcertsInsert: Codable, Hashable, Sendable {
    public let city: String?
    public let concertDate: String
    public let createdAt: String?
    public let id: UUID?
    public let lastActivityAt: String?
    public let ownerId: UUID
    public let startsAt: String?
    public let tour: String?
    public let updatedAt: String?
    public let venueName: String
    public let venueTimeZone: String?
    public let visibility: ConcertVisibility?
    public enum CodingKeys: String, CodingKey {
      case city = "city"
      case concertDate = "concert_date"
      case createdAt = "created_at"
      case id = "id"
      case lastActivityAt = "last_activity_at"
      case ownerId = "owner_id"
      case startsAt = "starts_at"
      case tour = "tour"
      case updatedAt = "updated_at"
      case venueName = "venue_name"
      case venueTimeZone = "venue_time_zone"
      case visibility = "visibility"
    }
  }
  public struct ConcertsUpdate: Codable, Hashable, Sendable {
    public let city: String?
    public let concertDate: String?
    public let createdAt: String?
    public let id: UUID?
    public let lastActivityAt: String?
    public let ownerId: UUID?
    public let startsAt: String?
    public let tour: String?
    public let updatedAt: String?
    public let venueName: String?
    public let venueTimeZone: String?
    public let visibility: ConcertVisibility?
    public enum CodingKeys: String, CodingKey {
      case city = "city"
      case concertDate = "concert_date"
      case createdAt = "created_at"
      case id = "id"
      case lastActivityAt = "last_activity_at"
      case ownerId = "owner_id"
      case startsAt = "starts_at"
      case tour = "tour"
      case updatedAt = "updated_at"
      case venueName = "venue_name"
      case venueTimeZone = "venue_time_zone"
      case visibility = "visibility"
    }
  }
  public struct ProfilesSelect: Codable, Hashable, Sendable {
    public let createdAt: String
    public let displayName: String?
    public let id: UUID
    public let onboardingCompletedAt: String?
    public let updatedAt: String
    public let username: String?
    public enum CodingKeys: String, CodingKey {
      case createdAt = "created_at"
      case displayName = "display_name"
      case id = "id"
      case onboardingCompletedAt = "onboarding_completed_at"
      case updatedAt = "updated_at"
      case username = "username"
    }
  }
  public struct ProfilesInsert: Codable, Hashable, Sendable {
    public let createdAt: String?
    public let displayName: String?
    public let id: UUID
    public let onboardingCompletedAt: String?
    public let updatedAt: String?
    public let username: String?
    public enum CodingKeys: String, CodingKey {
      case createdAt = "created_at"
      case displayName = "display_name"
      case id = "id"
      case onboardingCompletedAt = "onboarding_completed_at"
      case updatedAt = "updated_at"
      case username = "username"
    }
  }
  public struct ProfilesUpdate: Codable, Hashable, Sendable {
    public let createdAt: String?
    public let displayName: String?
    public let id: UUID?
    public let onboardingCompletedAt: String?
    public let updatedAt: String?
    public let username: String?
    public enum CodingKeys: String, CodingKey {
      case createdAt = "created_at"
      case displayName = "display_name"
      case id = "id"
      case onboardingCompletedAt = "onboarding_completed_at"
      case updatedAt = "updated_at"
      case username = "username"
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
