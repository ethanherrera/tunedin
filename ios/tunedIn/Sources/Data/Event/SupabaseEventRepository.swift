import Foundation
import Supabase

struct SupabaseEventRepository: EventRepository {
  let capabilities = EventRepositoryCapabilities.phase2Attendance

  private let client: SupabaseClient

  init(client: SupabaseClient) {
    self.client = client
  }

  func searchEvents(query: String, viewerID _: UUID) async throws -> [CommunityEventSummary] {
    try await withAppFailure {
      let normalized = CatalogInput.normalizedText(query)
      let response: PostgrestResponse<[CatalogEventRPCRecord]> = try await client
        .rpc(
          "search_catalog_events",
          params: SearchCatalogEventsParameters(query: normalized.isEmpty ? nil : normalized)
        )
        .execute()
      return try await summaries(from: response.value)
    }
  }

  func eventDetail(id: UUID, viewerID _: UUID) async throws -> CommunityEventDetail {
    try await withAppFailure {
      let response: PostgrestResponse<CatalogEventRPCRecord> = try await client
        .rpc("get_catalog_event_detail", params: CatalogEventIDParameters(eventID: id))
        .single()
        .execute()
      let summary = try await summaries(from: [response.value]).first
      guard let summary else { throw AppFailure.unexpected }
      let attendees: PostgrestResponse<[CatalogEventAttendeeRPCRecord]> = try await client
        .rpc(
          "list_catalog_event_attendees",
          params: ListCatalogEventAttendeesParameters(eventID: id)
        )
        .execute()
      return CommunityEventDetail(
        summary: summary,
        attendances: try attendees.value.map(EventAttendance.init(databaseRecord:)),
        posts: [],
        diaryPreviews: []
      )
    }
  }

  func plans(viewerID _: UUID) async throws -> [CommunityEventSummary] {
    try await withAppFailure {
      let response: PostgrestResponse<[CatalogEventRPCRecord]> = try await client
        .rpc("list_my_catalog_event_plans", params: CatalogEventPageParameters())
        .execute()
      return try await summaries(from: response.value)
    }
  }

  func setAttendance(
    eventID: UUID,
    viewerID: UUID,
    status: EventAttendanceStatus?,
    audience: EventAudience
  ) async throws -> CommunityEventDetail {
    try await withAppFailure {
      _ = try await client
        .rpc(
          "set_catalog_event_attendance",
          params: SetCatalogEventAttendanceParameters(
            eventID: eventID,
            status: status,
            audience: audience
          )
        )
        .execute()
      return try await eventDetail(id: eventID, viewerID: viewerID)
    }
  }

  func createEvent(
    _ input: CommunityEventCreationInput,
    creatorID: UUID
  ) async throws -> CommunityEventDetail {
    guard (1 ... 10).contains(input.artists.count),
          Set(input.artistCatalogIDs).count == input.artists.count
    else {
      throw CommunityEventError.invalidEvent("Choose between 1 and 10 different artists.")
    }
    guard TimeZone(identifier: input.timeZoneIdentifier) != nil else {
      throw CommunityEventError.invalidEvent("Choose a valid venue time zone.")
    }

    let parameters = CreateCatalogEventParameters(input: input)
    let created: CreateCatalogEventRPCRecord = try await withAppFailure {
      let response: PostgrestResponse<CreateCatalogEventRPCRecord> = try await client
        .rpc("create_catalog_event", params: parameters)
        .single()
        .execute()
      return response.value
    }
    return try await eventDetail(id: created.eventID, viewerID: creatorID)
  }

  private func summaries(
    from records: [CatalogEventRPCRecord]
  ) async throws -> [CommunityEventSummary] {
    guard !records.isEmpty else { return [] }
    let response: PostgrestResponse<[CatalogEventSocialSummaryRPCRecord]> = try await client
      .rpc(
        "get_catalog_event_social_summaries",
        params: CatalogEventSocialSummariesParameters(eventIDs: records.map(\.eventID))
      )
      .execute()
    let socialByEventID = Dictionary(uniqueKeysWithValues: response.value.map { ($0.eventID, $0) })
    return try records.map {
      try CommunityEventSummary(databaseRecord: $0, socialRecord: socialByEventID[$0.eventID])
    }
  }
}

struct SearchCatalogEventsParameters: Encodable, Equatable, Sendable {
  let query: String?
  let filters: [String: String]
  let limit: Int

  init(query: String?, filters: [String: String] = [:], limit: Int = 50) {
    self.query = query
    self.filters = filters
    self.limit = limit
  }

  enum CodingKeys: String, CodingKey {
    case query = "p_query"
    case filters = "p_filters"
    case limit = "p_limit"
  }
}

struct CatalogEventIDParameters: Encodable, Equatable, Sendable {
  let eventID: UUID

  enum CodingKeys: String, CodingKey {
    case eventID = "p_event_id"
  }
}

struct CatalogEventSocialSummariesParameters: Encodable, Equatable, Sendable {
  let eventIDs: [UUID]

  enum CodingKeys: String, CodingKey {
    case eventIDs = "p_event_ids"
  }
}

struct CatalogEventPageParameters: Encodable, Equatable, Sendable {
  let cursor: [String: String]?
  let limit: Int

  init(cursor: [String: String]? = nil, limit: Int = 50) {
    self.cursor = cursor
    self.limit = limit
  }

  enum CodingKeys: String, CodingKey {
    case cursor = "p_cursor"
    case limit = "p_limit"
  }
}

struct ListCatalogEventAttendeesParameters: Encodable, Equatable, Sendable {
  let eventID: UUID
  let scope: String
  let cursor: [String: String]?
  let limit: Int

  init(
    eventID: UUID,
    scope: String = "all",
    cursor: [String: String]? = nil,
    limit: Int = 50
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

struct SetCatalogEventAttendanceParameters: Encodable, Equatable, Sendable {
  let eventID: UUID
  let status: EventAttendanceStatus?
  let audience: EventAudience

  enum CodingKeys: String, CodingKey {
    case eventID = "p_event_id"
    case status = "p_status"
    case audience = "p_audience"
  }
}

struct CreateCatalogEventParameters: Encodable, Equatable, Sendable {
  let artists: [CreateCatalogEventArtistParameters]
  let catalogPlaceID: UUID
  let eventDate: String
  let catalogTourID: UUID?
  let startsAt: String?
  let timeZoneIdentifier: String
  let listing: CommunityEventListing

  init(input: CommunityEventCreationInput) {
    artists = input.artists.enumerated().map { index, artist in
      CreateCatalogEventArtistParameters(
        catalogArtistID: artist.id,
        isPrimary: index == 0
      )
    }
    catalogPlaceID = input.placeCatalogID
    eventDate = CommunityEventDateCoding.dateString(
      input.eventDate,
      timeZoneIdentifier: input.timeZoneIdentifier
    )
    catalogTourID = input.tourCatalogID
    startsAt = input.startsAt.map(CommunityEventDateCoding.dateTimeString)
    timeZoneIdentifier = input.timeZoneIdentifier
    listing = input.listing
  }

  enum CodingKeys: String, CodingKey {
    case artists = "p_artists"
    case catalogPlaceID = "p_catalog_place_id"
    case eventDate = "p_event_date"
    case catalogTourID = "p_catalog_tour_id"
    case startsAt = "p_starts_at"
    case timeZoneIdentifier = "p_time_zone_identifier"
    case listing = "p_listing"
  }
}

struct CreateCatalogEventArtistParameters: Encodable, Equatable, Sendable {
  let catalogArtistID: UUID
  let isPrimary: Bool

  enum CodingKeys: String, CodingKey {
    case catalogArtistID = "catalog_artist_id"
    case isPrimary = "is_primary"
  }
}

struct CreateCatalogEventRPCRecord: Decodable, Equatable, Sendable {
  let eventID: UUID
  let wasCreated: Bool
  let version: Int

  enum CodingKeys: String, CodingKey {
    case eventID = "event_id"
    case wasCreated = "was_created"
    case version
  }
}

struct CatalogEventRPCRecord: Decodable, Equatable, Sendable {
  let eventID: UUID
  let artists: [CatalogEventArtistRPCRecord]
  let catalogPlaceID: UUID
  let catalogAreaID: UUID?
  let catalogTourID: UUID?
  let venueName: String
  let areaName: String
  let eventDate: String
  let startsAt: String?
  let timeZoneIdentifier: String
  let memoryUnlockAt: String
  let lifecycle: CommunityEventLifecycle
  let listing: CommunityEventListing
  let integrity: CommunityEventIntegrity
  let rowState: CommunityEventRowState
  let sourceLabel: String

  enum CodingKeys: String, CodingKey {
    case artists, lifecycle, listing, integrity
    case eventID = "event_id"
    case catalogPlaceID = "catalog_place_id"
    case catalogAreaID = "catalog_area_id"
    case catalogTourID = "catalog_tour_id"
    case venueName = "venue_name"
    case areaName = "area_name"
    case eventDate = "event_date"
    case startsAt = "starts_at"
    case timeZoneIdentifier = "time_zone_identifier"
    case memoryUnlockAt = "memory_unlock_at"
    case rowState = "row_state"
    case sourceLabel = "source_label"
  }
}

struct CatalogEventArtistRPCRecord: Decodable, Equatable, Sendable {
  let catalogArtistID: UUID
  let displayName: String
  let position: Int
  let isHeadliner: Bool

  enum CodingKeys: String, CodingKey {
    case position
    case catalogArtistID = "catalog_artist_id"
    case displayName = "display_name"
    case isHeadliner = "is_headliner"
  }
}

struct CatalogEventSocialSummaryRPCRecord: Decodable, Equatable, Sendable {
  let eventID: UUID
  let currentUserStatus: EventAttendanceStatus?
  let currentUserAudience: EventAudience?
  let friendPreviews: [CatalogEventFriendPreviewRPCRecord]
  let communityGoingCount: Int
  let communityWentCount: Int

  enum CodingKeys: String, CodingKey {
    case eventID = "event_id"
    case currentUserStatus = "current_user_status"
    case currentUserAudience = "current_user_audience"
    case friendPreviews = "friend_previews"
    case communityGoingCount = "community_going_count"
    case communityWentCount = "community_went_count"
  }
}

struct CatalogEventFriendPreviewRPCRecord: Decodable, Equatable, Sendable {
  let profileID: UUID
  let username: String
  let displayName: String
  let relationship: String
  let avatarObjectPath: String?
  let avatarVersion: Int64
  let status: EventAttendanceStatus

  enum CodingKeys: String, CodingKey {
    case username, relationship, status
    case profileID = "profile_id"
    case displayName = "display_name"
    case avatarObjectPath = "avatar_object_path"
    case avatarVersion = "avatar_version"
  }
}

struct CatalogEventAttendeeRPCRecord: Decodable, Equatable, Sendable {
  let id: UUID
  let username: String
  let displayName: String
  let relationship: String
  let avatarObjectPath: String?
  let avatarVersion: Int64
  let status: EventAttendanceStatus
  let audience: EventAudience
  let updatedAt: String

  enum CodingKeys: String, CodingKey {
    case id, username, relationship, status, audience
    case displayName = "display_name"
    case avatarObjectPath = "avatar_object_path"
    case avatarVersion = "avatar_version"
    case updatedAt = "updated_at"
  }
}

extension CommunityEventSummary {
  init(
    databaseRecord: CatalogEventRPCRecord,
    socialRecord: CatalogEventSocialSummaryRPCRecord? = nil
  ) throws {
    guard
      let eventDate = CommunityEventDateCoding.date(from: databaseRecord.eventDate),
      let memoryUnlockAt = CommunityEventDateCoding.dateTime(from: databaseRecord.memoryUnlockAt)
    else {
      throw AppFailure.unexpected
    }
    let startsAt = try databaseRecord.startsAt.map { value in
      guard let date = CommunityEventDateCoding.dateTime(from: value) else {
        throw AppFailure.unexpected
      }
      return date
    }

    self.init(
      id: databaseRecord.eventID,
      artists: databaseRecord.artists.map {
        CommunityEventArtist(
          catalogArtistID: $0.catalogArtistID,
          displayName: $0.displayName,
          position: $0.position,
          isHeadliner: $0.isHeadliner
        )
      },
      catalogPlaceID: databaseRecord.catalogPlaceID,
      catalogAreaID: databaseRecord.catalogAreaID,
      catalogTourID: databaseRecord.catalogTourID,
      venueName: databaseRecord.venueName,
      areaName: databaseRecord.areaName,
      eventDate: eventDate,
      startsAt: startsAt,
      timeZoneIdentifier: databaseRecord.timeZoneIdentifier,
      memoryUnlockAt: memoryUnlockAt,
      lifecycle: databaseRecord.lifecycle,
      listing: databaseRecord.listing,
      integrity: databaseRecord.integrity,
      rowState: databaseRecord.rowState,
      sourceLabel: databaseRecord.sourceLabel,
      currentUserAttendance: socialRecord?.currentUserStatus,
      currentUserAudience: socialRecord?.currentUserAudience,
      friendPreviews: socialRecord?.friendPreviews.map(EventFriendPreview.init(databaseRecord:)) ?? [],
      publicGoingCount: socialRecord?.communityGoingCount ?? 0,
      publicWentCount: socialRecord?.communityWentCount ?? 0,
      diaryCount: 0,
      duplicateCandidateEventID: nil
    )
  }
}

private extension EventFriendPreview {
  init(databaseRecord: CatalogEventFriendPreviewRPCRecord) {
    self.init(
      profile: SocialProfile(
        id: databaseRecord.profileID,
        username: databaseRecord.username,
        displayName: databaseRecord.displayName,
        relationship: RelationshipState(rawValue: databaseRecord.relationship) ?? .none,
        avatarObjectPath: databaseRecord.avatarObjectPath,
        avatarVersion: databaseRecord.avatarVersion
      ),
      status: databaseRecord.status
    )
  }
}

extension EventAttendance {
  init(databaseRecord: CatalogEventAttendeeRPCRecord) throws {
    guard let updatedAt = CommunityEventDateCoding.dateTime(from: databaseRecord.updatedAt) else {
      throw AppFailure.unexpected
    }
    self.init(
      profile: SocialProfile(
        id: databaseRecord.id,
        username: databaseRecord.username,
        displayName: databaseRecord.displayName,
        relationship: RelationshipState(rawValue: databaseRecord.relationship) ?? .none,
        avatarObjectPath: databaseRecord.avatarObjectPath,
        avatarVersion: databaseRecord.avatarVersion
      ),
      status: databaseRecord.status,
      audience: databaseRecord.audience,
      updatedAt: updatedAt
    )
  }
}

enum CommunityEventDateCoding {
  static func preservingWallClockTime(
    _ date: Date,
    from oldTimeZone: TimeZone,
    to newTimeZone: TimeZone
  ) -> Date {
    var oldCalendar = Calendar(identifier: .gregorian)
    oldCalendar.timeZone = oldTimeZone
    let components = oldCalendar.dateComponents(
      [.year, .month, .day, .hour, .minute, .second],
      from: date
    )
    var newCalendar = Calendar(identifier: .gregorian)
    newCalendar.timeZone = newTimeZone
    return newCalendar.date(from: components) ?? date
  }

  static func dateString(_ date: Date, timeZoneIdentifier: String) -> String {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: timeZoneIdentifier) ?? .current
    let components = calendar.dateComponents([.year, .month, .day], from: date)
    return String(
      format: "%04d-%02d-%02d",
      components.year ?? 0,
      components.month ?? 0,
      components.day ?? 0
    )
  }

  static func date(from value: String) -> Date? {
    let parts = value.split(separator: "-").compactMap { Int($0) }
    guard parts.count == 3 else { return nil }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
    return calendar.date(from: DateComponents(
      timeZone: calendar.timeZone,
      year: parts[0],
      month: parts[1],
      day: parts[2],
      hour: 12
    ))
  }

  static func dateTimeString(_ date: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.string(from: date)
  }

  static func dateTime(from value: String) -> Date? {
    let fractionalSecondsFormatter = ISO8601DateFormatter()
    fractionalSecondsFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return fractionalSecondsFormatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
  }
}
