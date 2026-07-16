import Foundation
import Supabase

// RPC records remain colocated with their mappings so schema drift is reviewable in one diff.
// swiftlint:disable file_length

// swiftlint:disable:next type_body_length
struct SupabaseEventRepository: EventRepository {
  let capabilities = EventRepositoryCapabilities.phase4Memories

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

  func duplicateCandidates(
    for input: CommunityEventCreationInput,
    viewerID _: UUID
  ) async throws -> [CommunityEventSummary] {
    try await withAppFailure {
      let response: PostgrestResponse<[CatalogEventRPCRecord]> = try await client
        .rpc(
          "find_catalog_event_duplicate_candidates",
          params: FindEventDuplicateCandidatesParameters(input: input)
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
      let posts: PostgrestResponse<[CatalogEventPostRPCRecord]> = try await client
        .rpc(
          "list_catalog_event_posts",
          params: ListCatalogEventPostsParameters(eventID: id)
        )
        .execute()
      let diaries: PostgrestResponse<[CatalogEventDiaryRPCRecord]> = try await client
        .rpc(
          "list_catalog_event_diaries",
          params: ListCatalogEventDiariesParameters(eventID: id)
        )
        .execute()
      return CommunityEventDetail(
        summary: summary,
        attendances: try attendees.value.map(EventAttendance.init(databaseRecord:)),
        posts: try posts.value.map(EventPost.init(databaseRecord:)),
        diaryPreviews: try diaries.value.map(EventDiaryPreview.init(databaseRecord:))
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

  func activityFeed(viewerID _: UUID) async throws -> [EventActivity] {
    try await withAppFailure {
      let response: PostgrestResponse<[CatalogEventActivityRPCRecord]> = try await client
        .rpc("list_catalog_event_activity", params: CatalogEventPageParameters())
        .execute()
      let summariesByID = try await summaryMap(from: response.value.map(\.event))
      return try response.value.map { record in
        guard let event = summariesByID[record.event.eventID] else { throw AppFailure.unexpected }
        return try EventActivity(databaseRecord: record, event: event)
      }
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

  func confirmCancelledPerformance(
    eventID: UUID,
    viewerID: UUID,
    audience: EventAudience
  ) async throws -> CommunityEventDetail {
    try await withAppFailure {
      _ = try await client
        .rpc(
          "confirm_cancelled_catalog_event_performance",
          params: ConfirmCancelledPerformanceParameters(
            eventID: eventID,
            audience: audience
          )
        )
        .execute()
      return try await eventDetail(id: eventID, viewerID: viewerID)
    }
  }

  func addPost(
    eventID: UUID,
    authorID _: UUID,
    parentPostID: UUID?,
    body: String,
    audience: EventAudience
  ) async throws -> EventPost {
    try await withAppFailure {
      let created: PostgrestResponse<CreateCatalogEventPostRPCRecord> = try await client
        .rpc(
          "create_catalog_event_post",
          params: CreateCatalogEventPostParameters(
            eventID: eventID,
            parentPostID: parentPostID,
            body: body,
            audience: audience
          )
        )
        .single()
        .execute()
      let response: PostgrestResponse<[CatalogEventPostRPCRecord]> = try await client
        .rpc(
          "list_catalog_event_posts",
          params: ListCatalogEventPostsParameters(eventID: eventID)
        )
        .execute()
      guard let record = response.value.first(where: { $0.id == created.value.postID }) else {
        throw AppFailure.unexpected
      }
      return try EventPost(databaseRecord: record)
    }
  }

  func inviteCandidates(eventID: UUID, viewerID _: UUID) async throws -> [EventInviteCandidate] {
    try await withAppFailure {
      let response: PostgrestResponse<[CatalogEventInviteCandidateRPCRecord]> = try await client
        .rpc(
          "list_catalog_event_invite_candidates",
          params: CatalogEventIDParameters(eventID: eventID)
        )
        .execute()
      return response.value.map(EventInviteCandidate.init(databaseRecord:))
    }
  }

  func sendInvitations(eventID: UUID, senderID _: UUID, recipientIDs: [UUID]) async throws {
    try await withAppFailure {
      _ = try await client
        .rpc(
          "send_catalog_event_invitations",
          params: SendCatalogEventInvitationsParameters(
            eventID: eventID,
            recipientIDs: recipientIDs
          )
        )
        .execute()
    }
  }

  func pendingInvitations(viewerID _: UUID) async throws -> [EventInvitation] {
    try await withAppFailure {
      let response: PostgrestResponse<[CatalogEventInvitationRPCRecord]> = try await client
        .rpc("list_pending_catalog_event_invitations", params: CatalogEventPageParameters(limit: 20))
        .execute()
      let eventsByID = try await summaryMap(from: response.value.map(\.event))
      return try response.value.map { record in
        guard let event = eventsByID[record.eventID] else { throw AppFailure.unexpected }
        return try EventInvitation(databaseRecord: record, event: event)
      }
    }
  }

  func respondToInvitation(
    invitationID: UUID,
    viewerID _: UUID,
    response: EventInvitationResponse,
    audience: EventAudience
  ) async throws {
    try await withAppFailure {
      _ = try await client
        .rpc(
          "respond_catalog_event_invitation",
          params: RespondCatalogEventInvitationParameters(
            invitationID: invitationID,
            response: response,
            audience: audience
          )
        )
        .execute()
    }
  }

  func saveDiary(
    eventID: UUID,
    authorID: UUID,
    input: EventDiaryInput
  ) async throws -> CommunityEventDetail {
    try await withAppFailure {
      _ = try await client
        .rpc(
          "upsert_catalog_event_diary",
          params: UpsertCatalogEventDiaryParameters(eventID: eventID, input: input)
        )
        .execute()
      return try await eventDetail(id: eventID, viewerID: authorID)
    }
  }

  func preparePhotoDiary(
    eventID: UUID,
    authorID _: UUID,
    audience: EventAudience
  ) async throws -> UUID {
    try await withAppFailure {
      let input = EventDiaryInput(
        score: nil,
        performanceScore: nil,
        note: nil,
        audience: audience
      )
      let response: PostgrestResponse<UpsertCatalogEventDiaryRPCRecord> = try await client
        .rpc(
          "upsert_catalog_event_diary",
          params: UpsertCatalogEventDiaryParameters(
            eventID: eventID,
            input: input,
            publish: false
          )
        )
        .single()
        .execute()
      return response.value.diaryID
    }
  }

  func profileHistory(
    profileID: UUID,
    viewerID _: UUID
  ) async throws -> CommunityProfileHistory {
    try await withAppFailure {
      async let attendanceResponse: PostgrestResponse<[CatalogEventProfileAttendanceRPCRecord]> = client
        .rpc(
          "list_catalog_profile_attendance",
          params: CatalogEventProfileAttendanceParameters(profileID: profileID, state: .going)
        )
        .execute()
      async let historyResponse: PostgrestResponse<[CatalogEventProfileHistoryRPCRecord]> = client
        .rpc(
          "list_catalog_profile_event_history",
          params: CatalogEventProfileHistoryParameters(profileID: profileID)
        )
        .execute()
      let (attendance, history) = try await (attendanceResponse, historyResponse)
      let allEventRecords = attendance.value.map(\.event) + history.value.map(\.event)
      let eventsByID = try await summaryMap(from: allEventRecords)
      let going = try attendance.value.map { record in
        guard let event = eventsByID[record.event.eventID] else { throw AppFailure.unexpected }
        return event
      }
      var went: [CommunityEventSummary] = []
      var diaries: [EventProfileDiary] = []
      for record in history.value {
        guard let event = eventsByID[record.event.eventID] else { throw AppFailure.unexpected }
        switch record.historyKind {
        case "went":
          went.append(event)
        case "diary":
          guard let diaryRecord = record.diary else { throw AppFailure.unexpected }
          diaries.append(
            EventProfileDiary(
              event: event,
              diary: try EventDiaryPreview(databaseRecord: diaryRecord)
            )
          )
        default:
          throw AppFailure.unexpected
        }
      }
      return CommunityProfileHistory(going: going, went: went, diaries: diaries)
    }
  }

  func reportEvent(
    eventID: UUID,
    reporterID _: UUID,
    reason: EventReportReason,
    note: String?
  ) async throws {
    try await withAppFailure {
      _ = try await client
        .rpc(
          "report_catalog_event",
          params: ReportCatalogEventParameters(
            eventID: eventID,
            reason: reason,
            note: note
          )
        )
        .execute()
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
    let uniqueRecords = records.reduce(into: [UUID: CatalogEventRPCRecord]()) { result, record in
      result[record.eventID] = record
    }
    async let socialResponse: PostgrestResponse<[CatalogEventSocialSummaryRPCRecord]> = client
      .rpc(
        "get_catalog_event_social_summaries",
        params: CatalogEventSocialSummariesParameters(eventIDs: Array(uniqueRecords.keys))
      )
      .execute()
    async let diaryResponse: PostgrestResponse<[CatalogEventDiarySummaryRPCRecord]> = client
      .rpc(
        "get_catalog_event_diary_summaries",
        params: CatalogEventSocialSummariesParameters(eventIDs: Array(uniqueRecords.keys))
      )
      .execute()
    let (social, diary) = try await (socialResponse, diaryResponse)
    let socialByEventID = Dictionary(uniqueKeysWithValues: social.value.map { ($0.eventID, $0) })
    let diaryByEventID = Dictionary(uniqueKeysWithValues: diary.value.map { ($0.eventID, $0) })
    return try records.map {
      try CommunityEventSummary(
        databaseRecord: $0,
        socialRecord: socialByEventID[$0.eventID],
        diaryRecord: diaryByEventID[$0.eventID]
      )
    }
  }

  private func summaryMap(
    from records: [CatalogEventRPCRecord]
  ) async throws -> [UUID: CommunityEventSummary] {
    let uniqueRecords = records.reduce(into: [UUID: CatalogEventRPCRecord]()) { result, record in
      result[record.eventID] = record
    }
    return Dictionary(uniqueKeysWithValues: try await summaries(from: Array(uniqueRecords.values)).map {
      ($0.id, $0)
    })
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

struct ListCatalogEventPostsParameters: Encodable, Equatable, Sendable {
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

struct CreateCatalogEventPostParameters: Encodable, Equatable, Sendable {
  let eventID: UUID
  let parentPostID: UUID?
  let body: String
  let audience: EventAudience

  enum CodingKeys: String, CodingKey {
    case eventID = "p_event_id"
    case parentPostID = "p_parent_post_id"
    case body = "p_body"
    case audience = "p_audience"
  }
}

struct SendCatalogEventInvitationsParameters: Encodable, Equatable, Sendable {
  let eventID: UUID
  let recipientIDs: [UUID]

  enum CodingKeys: String, CodingKey {
    case eventID = "p_event_id"
    case recipientIDs = "p_recipient_ids"
  }
}

struct RespondCatalogEventInvitationParameters: Encodable, Equatable, Sendable {
  let invitationID: UUID
  let response: EventInvitationResponse
  let audience: EventAudience

  enum CodingKeys: String, CodingKey {
    case invitationID = "p_invitation_id"
    case response = "p_response"
    case audience = "p_audience"
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

struct FindEventDuplicateCandidatesParameters: Encodable, Equatable, Sendable {
  let artists: [CreateCatalogEventArtistParameters]
  let catalogPlaceID: UUID
  let eventDate: String
  let catalogTourID: UUID?
  let startsAt: String?
  let timeZoneIdentifier: String
  let listing: CommunityEventListing
  let limit = 5

  init(input: CommunityEventCreationInput) {
    let create = CreateCatalogEventParameters(input: input)
    artists = create.artists
    catalogPlaceID = create.catalogPlaceID
    eventDate = create.eventDate
    catalogTourID = create.catalogTourID
    startsAt = create.startsAt
    timeZoneIdentifier = create.timeZoneIdentifier
    listing = create.listing
  }

  enum CodingKeys: String, CodingKey {
    case artists = "p_artists"
    case catalogPlaceID = "p_catalog_place_id"
    case eventDate = "p_event_date"
    case catalogTourID = "p_catalog_tour_id"
    case startsAt = "p_starts_at"
    case timeZoneIdentifier = "p_time_zone_identifier"
    case listing = "p_listing"
    case limit = "p_limit"
  }
}

struct ConfirmCancelledPerformanceParameters: Encodable, Equatable, Sendable {
  let eventID: UUID
  let audience: EventAudience

  enum CodingKeys: String, CodingKey {
    case eventID = "p_event_id"
    case audience = "p_audience"
  }
}

struct ReportCatalogEventParameters: Encodable, Equatable, Sendable {
  let eventID: UUID
  let reason: EventReportReason
  let note: String?

  init(eventID: UUID, reason: EventReportReason, note: String?) {
    self.eventID = eventID
    self.reason = reason
    self.note = CatalogInput.optionalNormalizedText(note ?? "")
  }

  enum CodingKeys: String, CodingKey {
    case eventID = "p_event_id"
    case reason = "p_reason"
    case note = "p_note"
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

struct CatalogEventPostRPCRecord: Decodable, Equatable, Sendable {
  let id: UUID
  let parentPostID: UUID?
  let authorID: UUID
  let authorUsername: String
  let authorDisplayName: String
  let authorRelationship: String
  let authorAvatarObjectPath: String?
  let authorAvatarVersion: Int64
  let body: String
  let audience: EventAudience
  let createdAt: String
  let isDeleted: Bool

  enum CodingKeys: String, CodingKey {
    case id, body, audience
    case parentPostID = "parent_post_id"
    case authorID = "author_id"
    case authorUsername = "author_username"
    case authorDisplayName = "author_display_name"
    case authorRelationship = "author_relationship"
    case authorAvatarObjectPath = "author_avatar_object_path"
    case authorAvatarVersion = "author_avatar_version"
    case createdAt = "created_at"
    case isDeleted = "is_deleted"
  }
}

struct CreateCatalogEventPostRPCRecord: Decodable, Equatable, Sendable {
  let postID: UUID

  enum CodingKeys: String, CodingKey {
    case postID = "post_id"
  }
}

struct CatalogEventInviteCandidateRPCRecord: Decodable, Equatable, Sendable {
  let id: UUID
  let username: String
  let displayName: String
  let relationship: String
  let avatarObjectPath: String?
  let avatarVersion: Int64
  let attendanceStatus: EventAttendanceStatus?
  let isAlreadyInvited: Bool

  enum CodingKeys: String, CodingKey {
    case id, username, relationship
    case displayName = "display_name"
    case avatarObjectPath = "avatar_object_path"
    case avatarVersion = "avatar_version"
    case attendanceStatus = "attendance_status"
    case isAlreadyInvited = "is_already_invited"
  }
}

struct CatalogEventInvitationRPCRecord: Decodable, Equatable, Sendable {
  let invitationID: UUID
  let eventID: UUID
  let event: CatalogEventRPCRecord
  let senderID: UUID
  let senderUsername: String
  let senderDisplayName: String
  let senderRelationship: String
  let senderAvatarObjectPath: String?
  let senderAvatarVersion: Int64
  let createdAt: String

  enum CodingKeys: String, CodingKey {
    case event
    case invitationID = "invitation_id"
    case eventID = "event_id"
    case senderID = "sender_id"
    case senderUsername = "sender_username"
    case senderDisplayName = "sender_display_name"
    case senderRelationship = "sender_relationship"
    case senderAvatarObjectPath = "sender_avatar_object_path"
    case senderAvatarVersion = "sender_avatar_version"
    case createdAt = "created_at"
  }
}

struct CatalogEventActivityRPCRecord: Decodable, Equatable, Sendable {
  let activityID: UUID
  let action: EventActivityKind
  let actorID: UUID
  let actorUsername: String
  let actorDisplayName: String
  let actorRelationship: String
  let actorAvatarObjectPath: String?
  let actorAvatarVersion: Int64
  let subjectID: UUID?
  let diary: CatalogEventDiaryRPCRecord?
  let event: CatalogEventRPCRecord
  let occurredAt: String

  enum CodingKeys: String, CodingKey {
    case action, diary, event
    case activityID = "activity_id"
    case actorID = "actor_id"
    case actorUsername = "actor_username"
    case actorDisplayName = "actor_display_name"
    case actorRelationship = "actor_relationship"
    case actorAvatarObjectPath = "actor_avatar_object_path"
    case actorAvatarVersion = "actor_avatar_version"
    case subjectID = "subject_id"
    case occurredAt = "occurred_at"
  }
}

extension CommunityEventSummary {
  init(
    databaseRecord: CatalogEventRPCRecord,
    socialRecord: CatalogEventSocialSummaryRPCRecord? = nil,
    diaryRecord: CatalogEventDiarySummaryRPCRecord? = nil
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
      diaryCount: Int(diaryRecord?.diaryCount ?? 0),
      averageDiaryScore: diaryRecord?.averageScore,
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

extension EventPost {
  init(databaseRecord: CatalogEventPostRPCRecord) throws {
    guard let createdAt = CommunityEventDateCoding.dateTime(from: databaseRecord.createdAt) else {
      throw AppFailure.unexpected
    }
    self.init(
      id: databaseRecord.id,
      parentPostID: databaseRecord.parentPostID,
      author: SocialProfile(
        id: databaseRecord.authorID,
        username: databaseRecord.authorUsername,
        displayName: databaseRecord.authorDisplayName,
        relationship: RelationshipState(rawValue: databaseRecord.authorRelationship) ?? .none,
        avatarObjectPath: databaseRecord.authorAvatarObjectPath,
        avatarVersion: databaseRecord.authorAvatarVersion
      ),
      body: databaseRecord.body,
      audience: databaseRecord.audience,
      createdAt: createdAt,
      isDeleted: databaseRecord.isDeleted
    )
  }
}

private extension EventInviteCandidate {
  init(databaseRecord: CatalogEventInviteCandidateRPCRecord) {
    self.init(
      profile: SocialProfile(
        id: databaseRecord.id,
        username: databaseRecord.username,
        displayName: databaseRecord.displayName,
        relationship: RelationshipState(rawValue: databaseRecord.relationship) ?? .none,
        avatarObjectPath: databaseRecord.avatarObjectPath,
        avatarVersion: databaseRecord.avatarVersion
      ),
      attendanceStatus: databaseRecord.attendanceStatus,
      isAlreadyInvited: databaseRecord.isAlreadyInvited
    )
  }
}

extension EventInvitation {
  init(databaseRecord: CatalogEventInvitationRPCRecord, event: CommunityEventSummary) throws {
    guard let createdAt = CommunityEventDateCoding.dateTime(from: databaseRecord.createdAt) else {
      throw AppFailure.unexpected
    }
    self.init(
      id: databaseRecord.invitationID,
      event: event,
      sender: SocialProfile(
        id: databaseRecord.senderID,
        username: databaseRecord.senderUsername,
        displayName: databaseRecord.senderDisplayName,
        relationship: RelationshipState(rawValue: databaseRecord.senderRelationship) ?? .none,
        avatarObjectPath: databaseRecord.senderAvatarObjectPath,
        avatarVersion: databaseRecord.senderAvatarVersion
      ),
      createdAt: createdAt
    )
  }
}

extension EventActivity {
  init(databaseRecord: CatalogEventActivityRPCRecord, event: CommunityEventSummary) throws {
    guard let occurredAt = CommunityEventDateCoding.dateTime(from: databaseRecord.occurredAt) else {
      throw AppFailure.unexpected
    }
    let actor = SocialProfile(
      id: databaseRecord.actorID,
      username: databaseRecord.actorUsername,
      displayName: databaseRecord.actorDisplayName,
      relationship: RelationshipState(rawValue: databaseRecord.actorRelationship) ?? .none,
      avatarObjectPath: databaseRecord.actorAvatarObjectPath,
      avatarVersion: databaseRecord.actorAvatarVersion
    )
    self.init(
      id: databaseRecord.activityID,
      kind: databaseRecord.action,
      actor: actor,
      event: event,
      diary: try databaseRecord.diary.map(EventDiaryPreview.init(databaseRecord:)),
      occurredAt: occurredAt,
      message: databaseRecord.action.message(eventName: event.headlinerName)
    )
  }
}

private extension EventActivityKind {
  func message(eventName: String) -> String {
    switch self {
    case .eventCreated:
      "added \(eventName)"
    case .eventUpdated:
      "updated \(eventName)"
    case .markedGoing:
      "is going to \(eventName)"
    case .markedWent:
      "went to \(eventName)"
    case .invitationAccepted:
      "accepted an invite to \(eventName)"
    case .diaryPublished:
      "posted about \(eventName)"
    case .diaryMediaAdded:
      "added photos to a post about \(eventName)"
    case .eventPosted:
      "commented on \(eventName)"
    case .eventReplied:
      "replied on \(eventName)"
    }
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
