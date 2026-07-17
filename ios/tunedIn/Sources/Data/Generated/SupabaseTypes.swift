import Foundation
import Supabase

public enum PublicSchema {
  public enum CatalogEntityKind: String, Codable, Hashable, Sendable {
    case artist = "artist"
    case area = "area"
    case place = "place"
    case song = "song"
    case tour = "tour"
  }
  public enum CatalogEntityOrigin: String, Codable, Hashable, Sendable {
    case musicbrainz = "musicbrainz"
    case tunedinCustom = "tunedin_custom"
  }
  public enum CatalogEntityStatus: String, Codable, Hashable, Sendable {
    case active = "active"
    case needsReview = "needs_review"
    case merged = "merged"
    case retired = "retired"
  }
  public enum CatalogEventAttendanceStatus: String, Codable, Hashable, Sendable {
    case going = "going"
    case went = "went"
    case didNotGo = "did_not_go"
  }
  public enum CatalogEventAudience: String, Codable, Hashable, Sendable {
    case `private` = "private"
    case friends = "friends"
    case community = "community"
  }
  public enum CatalogEventIntegrity: String, Codable, Hashable, Sendable {
    case communityAdded = "community_added"
    case corroborated = "corroborated"
    case disputed = "disputed"
  }
  public enum CatalogEventInvitationStatus: String, Codable, Hashable, Sendable {
    case pending = "pending"
    case accepted = "accepted"
    case declined = "declined"
    case withdrawn = "withdrawn"
  }
  public enum CatalogEventLifecycle: String, Codable, Hashable, Sendable {
    case scheduled = "scheduled"
    case postponed = "postponed"
    case cancelled = "cancelled"
    case completed = "completed"
  }
  public enum CatalogEventListing: String, Codable, Hashable, Sendable {
    case listed = "listed"
    case unlisted = "unlisted"
  }
  public enum CatalogEventRowState: String, Codable, Hashable, Sendable {
    case active = "active"
    case merged = "merged"
    case tombstoned = "tombstoned"
  }
  public enum PostMediaStatus: String, Codable, Hashable, Sendable {
    case pending = "pending"
    case ready = "ready"
    case deleting = "deleting"
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
  public enum SocialActivityAction: String, Codable, Hashable, Sendable {
    case eventCreated = "event_created"
    case eventUpdated = "event_updated"
    case markedGoing = "marked_going"
    case markedWent = "marked_went"
    case invitationAccepted = "invitation_accepted"
    case postPublished = "post_published"
    case postMediaAdded = "post_media_added"
    case eventCommented = "event_commented"
    case eventCommentReplied = "event_comment_replied"
  }
  public struct CatalogAreasSelect: Codable, Hashable, Sendable {
    public let areaType: String?
    public let countryCode: String?
    public let id: UUID
    public let kind: CatalogEntityKind
    public let parentAreaId: UUID?
    public let subdivisionCode: String?
    public enum CodingKeys: String, CodingKey {
      case areaType = "area_type"
      case countryCode = "country_code"
      case id = "id"
      case kind = "kind"
      case parentAreaId = "parent_area_id"
      case subdivisionCode = "subdivision_code"
    }
  }
  public struct CatalogAreasInsert: Codable, Hashable, Sendable {
    public let areaType: String?
    public let countryCode: String?
    public let id: UUID
    public let kind: CatalogEntityKind?
    public let parentAreaId: UUID?
    public let subdivisionCode: String?
    public enum CodingKeys: String, CodingKey {
      case areaType = "area_type"
      case countryCode = "country_code"
      case id = "id"
      case kind = "kind"
      case parentAreaId = "parent_area_id"
      case subdivisionCode = "subdivision_code"
    }
  }
  public struct CatalogAreasUpdate: Codable, Hashable, Sendable {
    public let areaType: String?
    public let countryCode: String?
    public let id: UUID?
    public let kind: CatalogEntityKind?
    public let parentAreaId: UUID?
    public let subdivisionCode: String?
    public enum CodingKeys: String, CodingKey {
      case areaType = "area_type"
      case countryCode = "country_code"
      case id = "id"
      case kind = "kind"
      case parentAreaId = "parent_area_id"
      case subdivisionCode = "subdivision_code"
    }
  }
  public struct CatalogArtistsSelect: Codable, Hashable, Sendable {
    public let areaId: UUID?
    public let areaName: String?
    public let artistType: String?
    public let countryCode: String?
    public let ended: Bool?
    public let id: UUID
    public let kind: CatalogEntityKind
    public let lifeSpanBegin: String?
    public let lifeSpanEnd: String?
    public enum CodingKeys: String, CodingKey {
      case areaId = "area_id"
      case areaName = "area_name"
      case artistType = "artist_type"
      case countryCode = "country_code"
      case ended = "ended"
      case id = "id"
      case kind = "kind"
      case lifeSpanBegin = "life_span_begin"
      case lifeSpanEnd = "life_span_end"
    }
  }
  public struct CatalogArtistsInsert: Codable, Hashable, Sendable {
    public let areaId: UUID?
    public let areaName: String?
    public let artistType: String?
    public let countryCode: String?
    public let ended: Bool?
    public let id: UUID
    public let kind: CatalogEntityKind?
    public let lifeSpanBegin: String?
    public let lifeSpanEnd: String?
    public enum CodingKeys: String, CodingKey {
      case areaId = "area_id"
      case areaName = "area_name"
      case artistType = "artist_type"
      case countryCode = "country_code"
      case ended = "ended"
      case id = "id"
      case kind = "kind"
      case lifeSpanBegin = "life_span_begin"
      case lifeSpanEnd = "life_span_end"
    }
  }
  public struct CatalogArtistsUpdate: Codable, Hashable, Sendable {
    public let areaId: UUID?
    public let areaName: String?
    public let artistType: String?
    public let countryCode: String?
    public let ended: Bool?
    public let id: UUID?
    public let kind: CatalogEntityKind?
    public let lifeSpanBegin: String?
    public let lifeSpanEnd: String?
    public enum CodingKeys: String, CodingKey {
      case areaId = "area_id"
      case areaName = "area_name"
      case artistType = "artist_type"
      case countryCode = "country_code"
      case ended = "ended"
      case id = "id"
      case kind = "kind"
      case lifeSpanBegin = "life_span_begin"
      case lifeSpanEnd = "life_span_end"
    }
  }
  public struct CatalogEntitiesSelect: Codable, Hashable, Sendable {
    public let createdAt: String
    public let disambiguation: String?
    public let displayName: String
    public let id: UUID
    public let kind: CatalogEntityKind
    public let mergedIntoId: UUID?
    public let musicbrainzMbid: UUID?
    public let origin: CatalogEntityOrigin
    public let sortName: String
    public let status: CatalogEntityStatus
    public let updatedAt: String
    public enum CodingKeys: String, CodingKey {
      case createdAt = "created_at"
      case disambiguation = "disambiguation"
      case displayName = "display_name"
      case id = "id"
      case kind = "kind"
      case mergedIntoId = "merged_into_id"
      case musicbrainzMbid = "musicbrainz_mbid"
      case origin = "origin"
      case sortName = "sort_name"
      case status = "status"
      case updatedAt = "updated_at"
    }
  }
  public struct CatalogEntitiesInsert: Codable, Hashable, Sendable {
    public let createdAt: String?
    public let disambiguation: String?
    public let displayName: String
    public let id: UUID?
    public let kind: CatalogEntityKind
    public let mergedIntoId: UUID?
    public let musicbrainzMbid: UUID?
    public let origin: CatalogEntityOrigin
    public let sortName: String
    public let status: CatalogEntityStatus?
    public let updatedAt: String?
    public enum CodingKeys: String, CodingKey {
      case createdAt = "created_at"
      case disambiguation = "disambiguation"
      case displayName = "display_name"
      case id = "id"
      case kind = "kind"
      case mergedIntoId = "merged_into_id"
      case musicbrainzMbid = "musicbrainz_mbid"
      case origin = "origin"
      case sortName = "sort_name"
      case status = "status"
      case updatedAt = "updated_at"
    }
  }
  public struct CatalogEntitiesUpdate: Codable, Hashable, Sendable {
    public let createdAt: String?
    public let disambiguation: String?
    public let displayName: String?
    public let id: UUID?
    public let kind: CatalogEntityKind?
    public let mergedIntoId: UUID?
    public let musicbrainzMbid: UUID?
    public let origin: CatalogEntityOrigin?
    public let sortName: String?
    public let status: CatalogEntityStatus?
    public let updatedAt: String?
    public enum CodingKeys: String, CodingKey {
      case createdAt = "created_at"
      case disambiguation = "disambiguation"
      case displayName = "display_name"
      case id = "id"
      case kind = "kind"
      case mergedIntoId = "merged_into_id"
      case musicbrainzMbid = "musicbrainz_mbid"
      case origin = "origin"
      case sortName = "sort_name"
      case status = "status"
      case updatedAt = "updated_at"
    }
  }
  public struct CatalogEventArtistsSelect: Codable, Hashable, Sendable {
    public let artistNameSnapshot: String
    public let catalogArtistId: UUID
    public let eventId: UUID
    public let isHeadliner: Bool
    public let lineupPosition: Int16
    public enum CodingKeys: String, CodingKey {
      case artistNameSnapshot = "artist_name_snapshot"
      case catalogArtistId = "catalog_artist_id"
      case eventId = "event_id"
      case isHeadliner = "is_headliner"
      case lineupPosition = "lineup_position"
    }
  }
  public struct CatalogEventArtistsInsert: Codable, Hashable, Sendable {
    public let artistNameSnapshot: String
    public let catalogArtistId: UUID
    public let eventId: UUID
    public let isHeadliner: Bool?
    public let lineupPosition: Int16
    public enum CodingKeys: String, CodingKey {
      case artistNameSnapshot = "artist_name_snapshot"
      case catalogArtistId = "catalog_artist_id"
      case eventId = "event_id"
      case isHeadliner = "is_headliner"
      case lineupPosition = "lineup_position"
    }
  }
  public struct CatalogEventArtistsUpdate: Codable, Hashable, Sendable {
    public let artistNameSnapshot: String?
    public let catalogArtistId: UUID?
    public let eventId: UUID?
    public let isHeadliner: Bool?
    public let lineupPosition: Int16?
    public enum CodingKeys: String, CodingKey {
      case artistNameSnapshot = "artist_name_snapshot"
      case catalogArtistId = "catalog_artist_id"
      case eventId = "event_id"
      case isHeadliner = "is_headliner"
      case lineupPosition = "lineup_position"
    }
  }
  public struct CatalogEventAttendanceSelect: Codable, Hashable, Sendable {
    public let audience: CatalogEventAudience
    public let cancelledPerformanceConfirmedAt: String?
    public let createdAt: String
    public let eventId: UUID
    public let id: UUID
    public let profileId: UUID
    public let status: CatalogEventAttendanceStatus
    public let supersededAt: String?
    public let supersededByAttendanceId: UUID?
    public let updatedAt: String
    public enum CodingKeys: String, CodingKey {
      case audience = "audience"
      case cancelledPerformanceConfirmedAt = "cancelled_performance_confirmed_at"
      case createdAt = "created_at"
      case eventId = "event_id"
      case id = "id"
      case profileId = "profile_id"
      case status = "status"
      case supersededAt = "superseded_at"
      case supersededByAttendanceId = "superseded_by_attendance_id"
      case updatedAt = "updated_at"
    }
  }
  public struct CatalogEventAttendanceInsert: Codable, Hashable, Sendable {
    public let audience: CatalogEventAudience?
    public let cancelledPerformanceConfirmedAt: String?
    public let createdAt: String?
    public let eventId: UUID
    public let id: UUID?
    public let profileId: UUID
    public let status: CatalogEventAttendanceStatus
    public let supersededAt: String?
    public let supersededByAttendanceId: UUID?
    public let updatedAt: String?
    public enum CodingKeys: String, CodingKey {
      case audience = "audience"
      case cancelledPerformanceConfirmedAt = "cancelled_performance_confirmed_at"
      case createdAt = "created_at"
      case eventId = "event_id"
      case id = "id"
      case profileId = "profile_id"
      case status = "status"
      case supersededAt = "superseded_at"
      case supersededByAttendanceId = "superseded_by_attendance_id"
      case updatedAt = "updated_at"
    }
  }
  public struct CatalogEventAttendanceUpdate: Codable, Hashable, Sendable {
    public let audience: CatalogEventAudience?
    public let cancelledPerformanceConfirmedAt: String?
    public let createdAt: String?
    public let eventId: UUID?
    public let id: UUID?
    public let profileId: UUID?
    public let status: CatalogEventAttendanceStatus?
    public let supersededAt: String?
    public let supersededByAttendanceId: UUID?
    public let updatedAt: String?
    public enum CodingKeys: String, CodingKey {
      case audience = "audience"
      case cancelledPerformanceConfirmedAt = "cancelled_performance_confirmed_at"
      case createdAt = "created_at"
      case eventId = "event_id"
      case id = "id"
      case profileId = "profile_id"
      case status = "status"
      case supersededAt = "superseded_at"
      case supersededByAttendanceId = "superseded_by_attendance_id"
      case updatedAt = "updated_at"
    }
  }
  public struct CatalogEventInvitationsSelect: Codable, Hashable, Sendable {
    public let createdAt: String
    public let eventId: UUID
    public let id: UUID
    public let recipientId: UUID
    public let respondedAt: String?
    public let senderId: UUID
    public let status: CatalogEventInvitationStatus
    public let updatedAt: String
    public enum CodingKeys: String, CodingKey {
      case createdAt = "created_at"
      case eventId = "event_id"
      case id = "id"
      case recipientId = "recipient_id"
      case respondedAt = "responded_at"
      case senderId = "sender_id"
      case status = "status"
      case updatedAt = "updated_at"
    }
  }
  public struct CatalogEventInvitationsInsert: Codable, Hashable, Sendable {
    public let createdAt: String?
    public let eventId: UUID
    public let id: UUID?
    public let recipientId: UUID
    public let respondedAt: String?
    public let senderId: UUID
    public let status: CatalogEventInvitationStatus?
    public let updatedAt: String?
    public enum CodingKeys: String, CodingKey {
      case createdAt = "created_at"
      case eventId = "event_id"
      case id = "id"
      case recipientId = "recipient_id"
      case respondedAt = "responded_at"
      case senderId = "sender_id"
      case status = "status"
      case updatedAt = "updated_at"
    }
  }
  public struct CatalogEventInvitationsUpdate: Codable, Hashable, Sendable {
    public let createdAt: String?
    public let eventId: UUID?
    public let id: UUID?
    public let recipientId: UUID?
    public let respondedAt: String?
    public let senderId: UUID?
    public let status: CatalogEventInvitationStatus?
    public let updatedAt: String?
    public enum CodingKeys: String, CodingKey {
      case createdAt = "created_at"
      case eventId = "event_id"
      case id = "id"
      case recipientId = "recipient_id"
      case respondedAt = "responded_at"
      case senderId = "sender_id"
      case status = "status"
      case updatedAt = "updated_at"
    }
  }
  public struct CatalogEventsSelect: Codable, Hashable, Sendable {
    public let areaNameSnapshot: String
    public let catalogAreaId: UUID?
    public let catalogPlaceId: UUID
    public let catalogTourId: UUID?
    public let coverAttribution: String?
    public let coverLicenseName: String?
    public let coverLicenseUrl: String?
    public let coverObjectPath: String?
    public let coverProviderName: String?
    public let coverRemoteUrl: String?
    public let coverSource: String?
    public let coverSourcePageUrl: String?
    public let coverVersion: Int64
    public let createdAt: String
    public let createdBy: UUID
    public let eventDate: String
    public let exactDuplicateKey: String
    public let headlinerCatalogArtistId: UUID
    public let headlinerNameSnapshot: String
    public let id: UUID
    public let integrity: CatalogEventIntegrity
    public let lastMaterialActivityAt: String
    public let lifecycle: CatalogEventLifecycle
    public let listing: CatalogEventListing
    public let memoryUnlockAt: String
    public let mergedIntoEventId: UUID?
    public let rowState: CatalogEventRowState
    public let searchText: String
    public let startsAt: String?
    public let timeZoneIdentifier: String
    public let tourNameSnapshot: String?
    public let updatedAt: String
    public let venueNameSnapshot: String
    public let version: Int32
    public enum CodingKeys: String, CodingKey {
      case areaNameSnapshot = "area_name_snapshot"
      case catalogAreaId = "catalog_area_id"
      case catalogPlaceId = "catalog_place_id"
      case catalogTourId = "catalog_tour_id"
      case coverAttribution = "cover_attribution"
      case coverLicenseName = "cover_license_name"
      case coverLicenseUrl = "cover_license_url"
      case coverObjectPath = "cover_object_path"
      case coverProviderName = "cover_provider_name"
      case coverRemoteUrl = "cover_remote_url"
      case coverSource = "cover_source"
      case coverSourcePageUrl = "cover_source_page_url"
      case coverVersion = "cover_version"
      case createdAt = "created_at"
      case createdBy = "created_by"
      case eventDate = "event_date"
      case exactDuplicateKey = "exact_duplicate_key"
      case headlinerCatalogArtistId = "headliner_catalog_artist_id"
      case headlinerNameSnapshot = "headliner_name_snapshot"
      case id = "id"
      case integrity = "integrity"
      case lastMaterialActivityAt = "last_material_activity_at"
      case lifecycle = "lifecycle"
      case listing = "listing"
      case memoryUnlockAt = "memory_unlock_at"
      case mergedIntoEventId = "merged_into_event_id"
      case rowState = "row_state"
      case searchText = "search_text"
      case startsAt = "starts_at"
      case timeZoneIdentifier = "time_zone_identifier"
      case tourNameSnapshot = "tour_name_snapshot"
      case updatedAt = "updated_at"
      case venueNameSnapshot = "venue_name_snapshot"
      case version = "version"
    }
  }
  public struct CatalogEventsInsert: Codable, Hashable, Sendable {
    public let areaNameSnapshot: String
    public let catalogAreaId: UUID?
    public let catalogPlaceId: UUID
    public let catalogTourId: UUID?
    public let coverAttribution: String?
    public let coverLicenseName: String?
    public let coverLicenseUrl: String?
    public let coverObjectPath: String?
    public let coverProviderName: String?
    public let coverRemoteUrl: String?
    public let coverSource: String?
    public let coverSourcePageUrl: String?
    public let coverVersion: Int64?
    public let createdAt: String?
    public let createdBy: UUID
    public let eventDate: String
    public let exactDuplicateKey: String
    public let headlinerCatalogArtistId: UUID
    public let headlinerNameSnapshot: String
    public let id: UUID?
    public let integrity: CatalogEventIntegrity?
    public let lastMaterialActivityAt: String?
    public let lifecycle: CatalogEventLifecycle?
    public let listing: CatalogEventListing?
    public let memoryUnlockAt: String
    public let mergedIntoEventId: UUID?
    public let rowState: CatalogEventRowState?
    public let searchText: String
    public let startsAt: String?
    public let timeZoneIdentifier: String
    public let tourNameSnapshot: String?
    public let updatedAt: String?
    public let venueNameSnapshot: String
    public let version: Int32?
    public enum CodingKeys: String, CodingKey {
      case areaNameSnapshot = "area_name_snapshot"
      case catalogAreaId = "catalog_area_id"
      case catalogPlaceId = "catalog_place_id"
      case catalogTourId = "catalog_tour_id"
      case coverAttribution = "cover_attribution"
      case coverLicenseName = "cover_license_name"
      case coverLicenseUrl = "cover_license_url"
      case coverObjectPath = "cover_object_path"
      case coverProviderName = "cover_provider_name"
      case coverRemoteUrl = "cover_remote_url"
      case coverSource = "cover_source"
      case coverSourcePageUrl = "cover_source_page_url"
      case coverVersion = "cover_version"
      case createdAt = "created_at"
      case createdBy = "created_by"
      case eventDate = "event_date"
      case exactDuplicateKey = "exact_duplicate_key"
      case headlinerCatalogArtistId = "headliner_catalog_artist_id"
      case headlinerNameSnapshot = "headliner_name_snapshot"
      case id = "id"
      case integrity = "integrity"
      case lastMaterialActivityAt = "last_material_activity_at"
      case lifecycle = "lifecycle"
      case listing = "listing"
      case memoryUnlockAt = "memory_unlock_at"
      case mergedIntoEventId = "merged_into_event_id"
      case rowState = "row_state"
      case searchText = "search_text"
      case startsAt = "starts_at"
      case timeZoneIdentifier = "time_zone_identifier"
      case tourNameSnapshot = "tour_name_snapshot"
      case updatedAt = "updated_at"
      case venueNameSnapshot = "venue_name_snapshot"
      case version = "version"
    }
  }
  public struct CatalogEventsUpdate: Codable, Hashable, Sendable {
    public let areaNameSnapshot: String?
    public let catalogAreaId: UUID?
    public let catalogPlaceId: UUID?
    public let catalogTourId: UUID?
    public let coverAttribution: String?
    public let coverLicenseName: String?
    public let coverLicenseUrl: String?
    public let coverObjectPath: String?
    public let coverProviderName: String?
    public let coverRemoteUrl: String?
    public let coverSource: String?
    public let coverSourcePageUrl: String?
    public let coverVersion: Int64?
    public let createdAt: String?
    public let createdBy: UUID?
    public let eventDate: String?
    public let exactDuplicateKey: String?
    public let headlinerCatalogArtistId: UUID?
    public let headlinerNameSnapshot: String?
    public let id: UUID?
    public let integrity: CatalogEventIntegrity?
    public let lastMaterialActivityAt: String?
    public let lifecycle: CatalogEventLifecycle?
    public let listing: CatalogEventListing?
    public let memoryUnlockAt: String?
    public let mergedIntoEventId: UUID?
    public let rowState: CatalogEventRowState?
    public let searchText: String?
    public let startsAt: String?
    public let timeZoneIdentifier: String?
    public let tourNameSnapshot: String?
    public let updatedAt: String?
    public let venueNameSnapshot: String?
    public let version: Int32?
    public enum CodingKeys: String, CodingKey {
      case areaNameSnapshot = "area_name_snapshot"
      case catalogAreaId = "catalog_area_id"
      case catalogPlaceId = "catalog_place_id"
      case catalogTourId = "catalog_tour_id"
      case coverAttribution = "cover_attribution"
      case coverLicenseName = "cover_license_name"
      case coverLicenseUrl = "cover_license_url"
      case coverObjectPath = "cover_object_path"
      case coverProviderName = "cover_provider_name"
      case coverRemoteUrl = "cover_remote_url"
      case coverSource = "cover_source"
      case coverSourcePageUrl = "cover_source_page_url"
      case coverVersion = "cover_version"
      case createdAt = "created_at"
      case createdBy = "created_by"
      case eventDate = "event_date"
      case exactDuplicateKey = "exact_duplicate_key"
      case headlinerCatalogArtistId = "headliner_catalog_artist_id"
      case headlinerNameSnapshot = "headliner_name_snapshot"
      case id = "id"
      case integrity = "integrity"
      case lastMaterialActivityAt = "last_material_activity_at"
      case lifecycle = "lifecycle"
      case listing = "listing"
      case memoryUnlockAt = "memory_unlock_at"
      case mergedIntoEventId = "merged_into_event_id"
      case rowState = "row_state"
      case searchText = "search_text"
      case startsAt = "starts_at"
      case timeZoneIdentifier = "time_zone_identifier"
      case tourNameSnapshot = "tour_name_snapshot"
      case updatedAt = "updated_at"
      case venueNameSnapshot = "venue_name_snapshot"
      case version = "version"
    }
  }
  public struct CatalogPlacesSelect: Codable, Hashable, Sendable {
    public let address: String?
    public let areaId: UUID?
    public let ended: Bool?
    public let id: UUID
    public let kind: CatalogEntityKind
    public let latitude: Decimal?
    public let longitude: Decimal?
    public let placeType: String?
    public enum CodingKeys: String, CodingKey {
      case address = "address"
      case areaId = "area_id"
      case ended = "ended"
      case id = "id"
      case kind = "kind"
      case latitude = "latitude"
      case longitude = "longitude"
      case placeType = "place_type"
    }
  }
  public struct CatalogPlacesInsert: Codable, Hashable, Sendable {
    public let address: String?
    public let areaId: UUID?
    public let ended: Bool?
    public let id: UUID
    public let kind: CatalogEntityKind?
    public let latitude: Decimal?
    public let longitude: Decimal?
    public let placeType: String?
    public enum CodingKeys: String, CodingKey {
      case address = "address"
      case areaId = "area_id"
      case ended = "ended"
      case id = "id"
      case kind = "kind"
      case latitude = "latitude"
      case longitude = "longitude"
      case placeType = "place_type"
    }
  }
  public struct CatalogPlacesUpdate: Codable, Hashable, Sendable {
    public let address: String?
    public let areaId: UUID?
    public let ended: Bool?
    public let id: UUID?
    public let kind: CatalogEntityKind?
    public let latitude: Decimal?
    public let longitude: Decimal?
    public let placeType: String?
    public enum CodingKeys: String, CodingKey {
      case address = "address"
      case areaId = "area_id"
      case ended = "ended"
      case id = "id"
      case kind = "kind"
      case latitude = "latitude"
      case longitude = "longitude"
      case placeType = "place_type"
    }
  }
  public struct CatalogSongArtistsSelect: Codable, Hashable, Sendable {
    public let artistId: UUID
    public let creditName: String?
    public let creditPosition: Int16
    public let joinPhrase: String
    public let songId: UUID
    public enum CodingKeys: String, CodingKey {
      case artistId = "artist_id"
      case creditName = "credit_name"
      case creditPosition = "credit_position"
      case joinPhrase = "join_phrase"
      case songId = "song_id"
    }
  }
  public struct CatalogSongArtistsInsert: Codable, Hashable, Sendable {
    public let artistId: UUID
    public let creditName: String?
    public let creditPosition: Int16
    public let joinPhrase: String?
    public let songId: UUID
    public enum CodingKeys: String, CodingKey {
      case artistId = "artist_id"
      case creditName = "credit_name"
      case creditPosition = "credit_position"
      case joinPhrase = "join_phrase"
      case songId = "song_id"
    }
  }
  public struct CatalogSongArtistsUpdate: Codable, Hashable, Sendable {
    public let artistId: UUID?
    public let creditName: String?
    public let creditPosition: Int16?
    public let joinPhrase: String?
    public let songId: UUID?
    public enum CodingKeys: String, CodingKey {
      case artistId = "artist_id"
      case creditName = "credit_name"
      case creditPosition = "credit_position"
      case joinPhrase = "join_phrase"
      case songId = "song_id"
    }
  }
  public struct CatalogSongsSelect: Codable, Hashable, Sendable {
    public let artistCredit: String?
    public let durationMs: Int32?
    public let firstReleaseDate: String?
    public let id: UUID
    public let kind: CatalogEntityKind
    public let workMbid: UUID?
    public enum CodingKeys: String, CodingKey {
      case artistCredit = "artist_credit"
      case durationMs = "duration_ms"
      case firstReleaseDate = "first_release_date"
      case id = "id"
      case kind = "kind"
      case workMbid = "work_mbid"
    }
  }
  public struct CatalogSongsInsert: Codable, Hashable, Sendable {
    public let artistCredit: String?
    public let durationMs: Int32?
    public let firstReleaseDate: String?
    public let id: UUID
    public let kind: CatalogEntityKind?
    public let workMbid: UUID?
    public enum CodingKeys: String, CodingKey {
      case artistCredit = "artist_credit"
      case durationMs = "duration_ms"
      case firstReleaseDate = "first_release_date"
      case id = "id"
      case kind = "kind"
      case workMbid = "work_mbid"
    }
  }
  public struct CatalogSongsUpdate: Codable, Hashable, Sendable {
    public let artistCredit: String?
    public let durationMs: Int32?
    public let firstReleaseDate: String?
    public let id: UUID?
    public let kind: CatalogEntityKind?
    public let workMbid: UUID?
    public enum CodingKeys: String, CodingKey {
      case artistCredit = "artist_credit"
      case durationMs = "duration_ms"
      case firstReleaseDate = "first_release_date"
      case id = "id"
      case kind = "kind"
      case workMbid = "work_mbid"
    }
  }
  public struct CatalogTourArtistsSelect: Codable, Hashable, Sendable {
    public let artistId: UUID
    public let creditPosition: Int16
    public let tourId: UUID
    public enum CodingKeys: String, CodingKey {
      case artistId = "artist_id"
      case creditPosition = "credit_position"
      case tourId = "tour_id"
    }
  }
  public struct CatalogTourArtistsInsert: Codable, Hashable, Sendable {
    public let artistId: UUID
    public let creditPosition: Int16
    public let tourId: UUID
    public enum CodingKeys: String, CodingKey {
      case artistId = "artist_id"
      case creditPosition = "credit_position"
      case tourId = "tour_id"
    }
  }
  public struct CatalogTourArtistsUpdate: Codable, Hashable, Sendable {
    public let artistId: UUID?
    public let creditPosition: Int16?
    public let tourId: UUID?
    public enum CodingKeys: String, CodingKey {
      case artistId = "artist_id"
      case creditPosition = "credit_position"
      case tourId = "tour_id"
    }
  }
  public struct CatalogToursSelect: Codable, Hashable, Sendable {
    public let id: UUID
    public let kind: CatalogEntityKind
    public let seriesType: String
    public enum CodingKeys: String, CodingKey {
      case id = "id"
      case kind = "kind"
      case seriesType = "series_type"
    }
  }
  public struct CatalogToursInsert: Codable, Hashable, Sendable {
    public let id: UUID
    public let kind: CatalogEntityKind?
    public let seriesType: String?
    public enum CodingKeys: String, CodingKey {
      case id = "id"
      case kind = "kind"
      case seriesType = "series_type"
    }
  }
  public struct CatalogToursUpdate: Codable, Hashable, Sendable {
    public let id: UUID?
    public let kind: CatalogEntityKind?
    public let seriesType: String?
    public enum CodingKeys: String, CodingKey {
      case id = "id"
      case kind = "kind"
      case seriesType = "series_type"
    }
  }
  public struct EventCommentsSelect: Codable, Hashable, Sendable {
    public let audience: CatalogEventAudience
    public let authorId: UUID
    public let body: String
    public let createdAt: String
    public let deletedAt: String?
    public let eventId: UUID
    public let id: UUID
    public let parentCommentId: UUID?
    public let updatedAt: String
    public enum CodingKeys: String, CodingKey {
      case audience = "audience"
      case authorId = "author_id"
      case body = "body"
      case createdAt = "created_at"
      case deletedAt = "deleted_at"
      case eventId = "event_id"
      case id = "id"
      case parentCommentId = "parent_comment_id"
      case updatedAt = "updated_at"
    }
  }
  public struct EventCommentsInsert: Codable, Hashable, Sendable {
    public let audience: CatalogEventAudience?
    public let authorId: UUID
    public let body: String
    public let createdAt: String?
    public let deletedAt: String?
    public let eventId: UUID
    public let id: UUID?
    public let parentCommentId: UUID?
    public let updatedAt: String?
    public enum CodingKeys: String, CodingKey {
      case audience = "audience"
      case authorId = "author_id"
      case body = "body"
      case createdAt = "created_at"
      case deletedAt = "deleted_at"
      case eventId = "event_id"
      case id = "id"
      case parentCommentId = "parent_comment_id"
      case updatedAt = "updated_at"
    }
  }
  public struct EventCommentsUpdate: Codable, Hashable, Sendable {
    public let audience: CatalogEventAudience?
    public let authorId: UUID?
    public let body: String?
    public let createdAt: String?
    public let deletedAt: String?
    public let eventId: UUID?
    public let id: UUID?
    public let parentCommentId: UUID?
    public let updatedAt: String?
    public enum CodingKeys: String, CodingKey {
      case audience = "audience"
      case authorId = "author_id"
      case body = "body"
      case createdAt = "created_at"
      case deletedAt = "deleted_at"
      case eventId = "event_id"
      case id = "id"
      case parentCommentId = "parent_comment_id"
      case updatedAt = "updated_at"
    }
  }
  public struct EventPostsSelect: Codable, Hashable, Sendable {
    public let attendanceId: UUID?
    public let audience: CatalogEventAudience
    public let authorId: UUID
    public let createdAt: String
    public let deletedAt: String?
    public let eventId: UUID?
    public let eventSnapshot: AnyJSON
    public let id: UUID
    public let note: String?
    public let overallScorePoints: Int16?
    public let performanceScorePoints: Int16?
    public let publishedAt: String?
    public let updatedAt: String
    public enum CodingKeys: String, CodingKey {
      case attendanceId = "attendance_id"
      case audience = "audience"
      case authorId = "author_id"
      case createdAt = "created_at"
      case deletedAt = "deleted_at"
      case eventId = "event_id"
      case eventSnapshot = "event_snapshot"
      case id = "id"
      case note = "note"
      case overallScorePoints = "overall_score_points"
      case performanceScorePoints = "performance_score_points"
      case publishedAt = "published_at"
      case updatedAt = "updated_at"
    }
  }
  public struct EventPostsInsert: Codable, Hashable, Sendable {
    public let attendanceId: UUID?
    public let audience: CatalogEventAudience?
    public let authorId: UUID
    public let createdAt: String?
    public let deletedAt: String?
    public let eventId: UUID?
    public let eventSnapshot: AnyJSON
    public let id: UUID?
    public let note: String?
    public let overallScorePoints: Int16?
    public let performanceScorePoints: Int16?
    public let publishedAt: String?
    public let updatedAt: String?
    public enum CodingKeys: String, CodingKey {
      case attendanceId = "attendance_id"
      case audience = "audience"
      case authorId = "author_id"
      case createdAt = "created_at"
      case deletedAt = "deleted_at"
      case eventId = "event_id"
      case eventSnapshot = "event_snapshot"
      case id = "id"
      case note = "note"
      case overallScorePoints = "overall_score_points"
      case performanceScorePoints = "performance_score_points"
      case publishedAt = "published_at"
      case updatedAt = "updated_at"
    }
  }
  public struct EventPostsUpdate: Codable, Hashable, Sendable {
    public let attendanceId: UUID?
    public let audience: CatalogEventAudience?
    public let authorId: UUID?
    public let createdAt: String?
    public let deletedAt: String?
    public let eventId: UUID?
    public let eventSnapshot: AnyJSON?
    public let id: UUID?
    public let note: String?
    public let overallScorePoints: Int16?
    public let performanceScorePoints: Int16?
    public let publishedAt: String?
    public let updatedAt: String?
    public enum CodingKeys: String, CodingKey {
      case attendanceId = "attendance_id"
      case audience = "audience"
      case authorId = "author_id"
      case createdAt = "created_at"
      case deletedAt = "deleted_at"
      case eventId = "event_id"
      case eventSnapshot = "event_snapshot"
      case id = "id"
      case note = "note"
      case overallScorePoints = "overall_score_points"
      case performanceScorePoints = "performance_score_points"
      case publishedAt = "published_at"
      case updatedAt = "updated_at"
    }
  }
  public struct PostCommentsSelect: Codable, Hashable, Sendable {
    public let authorId: UUID
    public let body: String
    public let createdAt: String
    public let deletedAt: String?
    public let id: UUID
    public let postId: UUID
    public let updatedAt: String
    public enum CodingKeys: String, CodingKey {
      case authorId = "author_id"
      case body = "body"
      case createdAt = "created_at"
      case deletedAt = "deleted_at"
      case id = "id"
      case postId = "post_id"
      case updatedAt = "updated_at"
    }
  }
  public struct PostCommentsInsert: Codable, Hashable, Sendable {
    public let authorId: UUID
    public let body: String
    public let createdAt: String?
    public let deletedAt: String?
    public let id: UUID?
    public let postId: UUID
    public let updatedAt: String?
    public enum CodingKeys: String, CodingKey {
      case authorId = "author_id"
      case body = "body"
      case createdAt = "created_at"
      case deletedAt = "deleted_at"
      case id = "id"
      case postId = "post_id"
      case updatedAt = "updated_at"
    }
  }
  public struct PostCommentsUpdate: Codable, Hashable, Sendable {
    public let authorId: UUID?
    public let body: String?
    public let createdAt: String?
    public let deletedAt: String?
    public let id: UUID?
    public let postId: UUID?
    public let updatedAt: String?
    public enum CodingKeys: String, CodingKey {
      case authorId = "author_id"
      case body = "body"
      case createdAt = "created_at"
      case deletedAt = "deleted_at"
      case id = "id"
      case postId = "post_id"
      case updatedAt = "updated_at"
    }
  }
  public struct PostMediaSelect: Codable, Hashable, Sendable {
    public let attachedAt: String?
    public let caption: String?
    public let createdAt: String
    public let deletedAt: String?
    public let deletionRequestedAt: String?
    public let expiresAt: String
    public let id: UUID
    public let objectPath: String
    public let postId: UUID
    public let status: PostMediaStatus
    public let uploaderId: UUID
    public let version: Int64
    public enum CodingKeys: String, CodingKey {
      case attachedAt = "attached_at"
      case caption = "caption"
      case createdAt = "created_at"
      case deletedAt = "deleted_at"
      case deletionRequestedAt = "deletion_requested_at"
      case expiresAt = "expires_at"
      case id = "id"
      case objectPath = "object_path"
      case postId = "post_id"
      case status = "status"
      case uploaderId = "uploader_id"
      case version = "version"
    }
  }
  public struct PostMediaInsert: Codable, Hashable, Sendable {
    public let attachedAt: String?
    public let caption: String?
    public let createdAt: String?
    public let deletedAt: String?
    public let deletionRequestedAt: String?
    public let expiresAt: String
    public let id: UUID
    public let objectPath: String
    public let postId: UUID
    public let status: PostMediaStatus?
    public let uploaderId: UUID
    public let version: Int64?
    public enum CodingKeys: String, CodingKey {
      case attachedAt = "attached_at"
      case caption = "caption"
      case createdAt = "created_at"
      case deletedAt = "deleted_at"
      case deletionRequestedAt = "deletion_requested_at"
      case expiresAt = "expires_at"
      case id = "id"
      case objectPath = "object_path"
      case postId = "post_id"
      case status = "status"
      case uploaderId = "uploader_id"
      case version = "version"
    }
  }
  public struct PostMediaUpdate: Codable, Hashable, Sendable {
    public let attachedAt: String?
    public let caption: String?
    public let createdAt: String?
    public let deletedAt: String?
    public let deletionRequestedAt: String?
    public let expiresAt: String?
    public let id: UUID?
    public let objectPath: String?
    public let postId: UUID?
    public let status: PostMediaStatus?
    public let uploaderId: UUID?
    public let version: Int64?
    public enum CodingKeys: String, CodingKey {
      case attachedAt = "attached_at"
      case caption = "caption"
      case createdAt = "created_at"
      case deletedAt = "deleted_at"
      case deletionRequestedAt = "deletion_requested_at"
      case expiresAt = "expires_at"
      case id = "id"
      case objectPath = "object_path"
      case postId = "post_id"
      case status = "status"
      case uploaderId = "uploader_id"
      case version = "version"
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
  public struct SocialActivityEventsSelect: Codable, Hashable, Sendable {
    public let action: SocialActivityAction
    public let actorId: UUID
    public let eventId: UUID
    public let id: UUID
    public let metadata: AnyJSON
    public let occurredAt: String
    public let subjectId: UUID?
    public enum CodingKeys: String, CodingKey {
      case action = "action"
      case actorId = "actor_id"
      case eventId = "event_id"
      case id = "id"
      case metadata = "metadata"
      case occurredAt = "occurred_at"
      case subjectId = "subject_id"
    }
  }
  public struct SocialActivityEventsInsert: Codable, Hashable, Sendable {
    public let action: SocialActivityAction
    public let actorId: UUID
    public let eventId: UUID
    public let id: UUID?
    public let metadata: AnyJSON?
    public let occurredAt: String?
    public let subjectId: UUID?
    public enum CodingKeys: String, CodingKey {
      case action = "action"
      case actorId = "actor_id"
      case eventId = "event_id"
      case id = "id"
      case metadata = "metadata"
      case occurredAt = "occurred_at"
      case subjectId = "subject_id"
    }
  }
  public struct SocialActivityEventsUpdate: Codable, Hashable, Sendable {
    public let action: SocialActivityAction?
    public let actorId: UUID?
    public let eventId: UUID?
    public let id: UUID?
    public let metadata: AnyJSON?
    public let occurredAt: String?
    public let subjectId: UUID?
    public enum CodingKeys: String, CodingKey {
      case action = "action"
      case actorId = "actor_id"
      case eventId = "event_id"
      case id = "id"
      case metadata = "metadata"
      case occurredAt = "occurred_at"
      case subjectId = "subject_id"
    }
  }
}
