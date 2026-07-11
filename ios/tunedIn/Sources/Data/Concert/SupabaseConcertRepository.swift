import Foundation
import Supabase

struct SupabaseConcertRepository: ConcertRepository {
  let client: SupabaseClient

  func createPrivateConcert(_ input: ConcertCreationInput) async throws -> Concert {
    do {
      let response: PostgrestResponse<PublicSchema.ConcertsSelect> = try await client
        .rpc("create_private_concert", params: CreatePrivateConcertParameters(input: input))
        .single()
        .execute()
      return try Concert(databaseRecord: response.value)
    } catch {
      throw ConcertRepositoryFailure(error)
    }
  }

  func updateConcert(_ input: ConcertUpdateInput) async throws -> Concert {
    do {
      let response: PostgrestResponse<PublicSchema.ConcertsSelect> = try await client
        .rpc("update_concert", params: UpdateConcertParameters(input: input))
        .single()
        .execute()
      return try Concert(databaseRecord: response.value)
    } catch {
      throw ConcertRepositoryFailure(error)
    }
  }

  func tagCollaborator(
    concertID: UUID,
    profileID: UUID,
    expectedVersion: Int64
  ) async throws -> Concert {
    try await mutateConcert(
      rpc: "tag_concert_collaborator",
      params: CollaboratorMutationParameters(
        concertID: concertID,
        profileID: profileID,
        expectedVersion: expectedVersion
      )
    )
  }

  func removeCollaborator(
    concertID: UUID,
    profileID: UUID,
    expectedVersion: Int64
  ) async throws -> Concert {
    try await mutateConcert(
      rpc: "remove_concert_collaborator",
      params: CollaboratorMutationParameters(
        concertID: concertID,
        profileID: profileID,
        expectedVersion: expectedVersion
      )
    )
  }

  func transferOwnership(
    concertID: UUID,
    newOwnerID: UUID,
    expectedVersion: Int64
  ) async throws -> Concert {
    do {
      let response: PostgrestResponse<PublicSchema.ConcertsSelect> = try await client
        .rpc(
          "transfer_concert_ownership",
          params: OwnershipTransferParameters(
            concertID: concertID,
            newOwnerID: newOwnerID,
            expectedVersion: expectedVersion
          )
        )
        .single()
        .execute()
      return try Concert(databaseRecord: response.value)
    } catch {
      throw ConcertRepositoryFailure(error)
    }
  }

  func deleteConcert(id: UUID) async throws {
    do {
      let _: PostgrestResponse<Void> = try await client
        .rpc("delete_concert", params: ConcertIDParameters(concertID: id))
        .execute()
    } catch {
      throw ConcertRepositoryFailure(error)
    }
  }

  func collaborators(concertID: UUID) async throws -> [ConcertCollaborator] {
    do {
      let response: PostgrestResponse<[ConcertCollaboratorRecord]> = try await client
        .rpc("list_concert_collaborators", params: ConcertIDParameters(concertID: concertID))
        .execute()
      return try response.value.map(ConcertCollaborator.init(databaseRecord:))
    } catch {
      throw ConcertRepositoryFailure(error)
    }
  }

  func comments(
    concertID: UUID,
    cursor: ConcertCommentCursor?
  ) async throws -> [ConcertComment] {
    do {
      let response: PostgrestResponse<[ConcertCommentRecord]> = try await client
        .rpc(
          "list_concert_comments",
          params: CommentListParameters(concertID: concertID, cursor: cursor)
        )
        .execute()
      return try response.value.map(ConcertComment.init(databaseRecord:))
    } catch {
      throw ConcertRepositoryFailure(error)
    }
  }

  func createComment(concertID: UUID, body: String) async throws -> ConcertComment {
    do {
      let response: PostgrestResponse<PublicSchema.CommentsSelect> = try await client
        .rpc("create_concert_comment", params: CommentMutationParameters(concertID: concertID, body: body))
        .single()
        .execute()
      return try ConcertComment(databaseRecord: response.value, authorLabel: .you)
    } catch {
      throw ConcertRepositoryFailure(error)
    }
  }

  func updateComment(commentID: UUID, body: String) async throws -> ConcertComment {
    do {
      let response: PostgrestResponse<PublicSchema.CommentsSelect> = try await client
        .rpc("update_concert_comment", params: CommentUpdateParameters(commentID: commentID, body: body))
        .single()
        .execute()
      return try ConcertComment(databaseRecord: response.value, authorLabel: .you)
    } catch {
      throw ConcertRepositoryFailure(error)
    }
  }

  func deleteComment(commentID: UUID) async throws {
    do {
      let _: PostgrestResponse<Void> = try await client
        .rpc("delete_concert_comment", params: CommentIDParameters(commentID: commentID))
        .execute()
    } catch {
      throw ConcertRepositoryFailure(error)
    }
  }

  func friendsActivity(cursor: FriendsActivityCursor?) async throws -> [FriendActivity] {
    do {
      let response: PostgrestResponse<[FriendActivityRecord]> = try await client
        .rpc("friends_activity_feed", params: FriendsActivityParameters(cursor: cursor))
        .execute()
      return try response.value.map(FriendActivity.init(databaseRecord:))
    } catch {
      throw ConcertRepositoryFailure(error)
    }
  }

  func profileConcertHistory(
    profileID: UUID,
    query: ConcertHistoryQuery,
    cursor: ConcertHistoryCursor?
  ) async throws -> [ConcertPreview] {
    do {
      let response: PostgrestResponse<[ProfileConcertHistoryRecord]> = try await client
        .rpc(
          "profile_concert_history",
          params: ProfileConcertHistoryParameters(
            profileID: profileID,
            query: query,
            cursor: cursor
          )
        )
        .execute()
      return try response.value.map(ConcertPreview.init(databaseRecord:))
    } catch {
      throw ConcertRepositoryFailure(error)
    }
  }

  func fetchConcertDetail(id: UUID, viewerID: UUID) async throws -> ConcertDetail {
    do {
      async let concertResponse: PostgrestResponse<PublicSchema.ConcertsSelect> = client
        .from("concerts")
        .select()
        .eq("id", value: id.uuidString)
        .single()
        .execute()
      async let artistsResponse: PostgrestResponse<[PublicSchema.ConcertArtistsSelect]> = client
        .from("concert_artists")
        .select()
        .eq("concert_id", value: id.uuidString)
        .order("lineup_position")
        .execute()
      async let setlistResponse: PostgrestResponse<[PublicSchema.SetlistItemsSelect]> = client
        .from("setlist_items")
        .select()
        .eq("concert_id", value: id.uuidString)
        .order("set_position")
        .execute()
      async let eventsResponse: PostgrestResponse<[PublicSchema.ConcertEventsSelect]> = client
        .from("concert_events")
        .select()
        .eq("concert_id", value: id.uuidString)
        .order("occurred_at")
        .execute()
      async let collaboratorResponse: PostgrestResponse<[PublicSchema.ConcertCollaboratorsSelect]> = client
        .from("concert_collaborators")
        .select()
        .eq("concert_id", value: id.uuidString)
        .execute()

      let (concertRecord, artistsRecord, setlistRecord, eventsRecord, collaboratorRecords) = try await (
        concertResponse,
        artistsResponse,
        setlistResponse,
        eventsResponse,
        collaboratorResponse
      )
      let concert = try Concert(databaseRecord: concertRecord.value)
      let isEditor = concert.ownerID == viewerID
        || collaboratorRecords.value.contains(where: { $0.profileId == viewerID })
      let loadedCollaborators = isEditor ? try await collaborators(concertID: id) : []

      return try ConcertDetail(
        concert: concert,
        artists: artistsRecord.value.map(ConcertArtist.init(databaseRecord:)),
        setlist: setlistRecord.value.map(SetlistEntry.init(databaseRecord:)),
        history: eventsRecord.value.map(ConcertTimelineEvent.init(databaseRecord:)),
        collaborators: loadedCollaborators
      )
    } catch {
      throw ConcertRepositoryFailure(error)
    }
  }

  func observeConcert(id: UUID) -> AsyncStream<Void> {
    changeStream(
      name: "concert-\(id.uuidString)",
      subscriptions: [
        ("concert_events", "concert_id=eq.\(id.uuidString)"),
        ("concerts", "id=eq.\(id.uuidString)")
      ]
    )
  }

  func observeFriendsActivity() -> AsyncStream<Void> {
    changeStream(name: "friends-activity", subscriptions: [("concert_events", nil)])
  }

  private func mutateConcert(
    rpc: String,
    params: some Encodable & Sendable
  ) async throws -> Concert {
    do {
      let response: PostgrestResponse<PublicSchema.ConcertsSelect> = try await client
        .rpc(rpc, params: params)
        .single()
        .execute()
      return try Concert(databaseRecord: response.value)
    } catch {
      throw ConcertRepositoryFailure(error)
    }
  }

  private func changeStream(
    name: String,
    subscriptions: [(table: String, filter: String?)]
  ) -> AsyncStream<Void> {
    let client = client
    return AsyncStream { continuation in
      let channel = client.channel(name)
      let listeners = subscriptions.map { subscription in
        channel.onPostgresChange(
          AnyAction.self,
          schema: "public",
          table: subscription.table,
          filter: subscription.filter
        ) { _ in
          continuation.yield()
        }
      }
      let subscriptionTask = Task {
        do {
          try await channel.subscribeWithError()
        } catch {
          continuation.finish()
        }
      }
      continuation.onTermination = { _ in
        listeners.forEach { $0.cancel() }
        subscriptionTask.cancel()
        Task { await client.removeChannel(channel) }
      }
    }
  }
}

private struct CreatePrivateConcertParameters: Encodable, Sendable {
  private let artists: [CreatePrivateConcertArtist]
  private let venueName: String
  private let concertDate: String
  private let city: String?
  private let tour: String?
  private let startsAt: String?
  private let venueTimeZone: String?
  private let setlist: [String]

  init(input: ConcertCreationInput) {
    artists = input.artists.map { CreatePrivateConcertArtist(name: $0.name, isPrimary: $0.isPrimary) }
    venueName = input.venueName
    concertDate = input.concertDate
    city = input.city
    tour = input.tour
    startsAt = input.startsAt.map(ConcertDateCoding.dateTimeString)
    venueTimeZone = input.venueTimeZone
    setlist = input.setlist
  }

  enum CodingKeys: String, CodingKey {
    case artists = "p_artists"
    case venueName = "p_venue_name"
    case concertDate = "p_concert_date"
    case city = "p_city"
    case tour = "p_tour"
    case startsAt = "p_starts_at"
    case venueTimeZone = "p_venue_time_zone"
    case setlist = "p_setlist"
  }
}

private struct UpdateConcertParameters: Encodable, Sendable {
  private let concertID: UUID
  private let expectedVersion: Int64
  private let artists: [CreatePrivateConcertArtist]
  private let venueName: String
  private let concertDate: String
  private let city: String?
  private let tour: String?
  private let startsAt: String?
  private let venueTimeZone: String?
  private let setlist: [String]
  private let visibility: ConcertVisibility

  init(input: ConcertUpdateInput) {
    concertID = input.concertID
    expectedVersion = input.expectedVersion
    artists = input.artists.map { CreatePrivateConcertArtist(name: $0.name, isPrimary: $0.isPrimary) }
    venueName = input.venueName
    concertDate = input.concertDate
    city = input.city
    tour = input.tour
    startsAt = input.startsAt.map(ConcertDateCoding.dateTimeString)
    venueTimeZone = input.venueTimeZone
    setlist = input.setlist
    visibility = input.visibility
  }

  enum CodingKeys: String, CodingKey {
    case concertID = "p_concert_id"
    case expectedVersion = "p_expected_version"
    case artists = "p_artists"
    case venueName = "p_venue_name"
    case concertDate = "p_concert_date"
    case city = "p_city"
    case tour = "p_tour"
    case startsAt = "p_starts_at"
    case venueTimeZone = "p_venue_time_zone"
    case setlist = "p_setlist"
    case visibility = "p_visibility"
  }
}

private struct CreatePrivateConcertArtist: Encodable, Sendable {
  private let name: String
  private let isPrimary: Bool

  init(name: String, isPrimary: Bool) {
    self.name = name
    self.isPrimary = isPrimary
  }

  enum CodingKeys: String, CodingKey {
    case name
    case isPrimary = "is_primary"
  }
}

private struct ConcertIDParameters: Encodable, Sendable {
  let concertID: UUID

  enum CodingKeys: String, CodingKey {
    case concertID = "p_concert_id"
  }
}

private struct CollaboratorMutationParameters: Encodable, Sendable {
  let concertID: UUID
  let profileID: UUID
  let expectedVersion: Int64

  enum CodingKeys: String, CodingKey {
    case concertID = "p_concert_id"
    case profileID = "p_profile_id"
    case expectedVersion = "p_expected_version"
  }
}

private struct OwnershipTransferParameters: Encodable, Sendable {
  let concertID: UUID
  let newOwnerID: UUID
  let expectedVersion: Int64

  enum CodingKeys: String, CodingKey {
    case concertID = "p_concert_id"
    case newOwnerID = "p_new_owner_id"
    case expectedVersion = "p_expected_version"
  }
}

private struct CommentListParameters: Encodable, Sendable {
  let concertID: UUID
  let cursorCreatedAt: String?
  let cursorID: UUID?
  let limit = 30

  init(concertID: UUID, cursor: ConcertCommentCursor?) {
    self.concertID = concertID
    cursorCreatedAt = cursor.map { ConcertDateCoding.dateTimeString($0.createdAt) }
    cursorID = cursor?.commentID
  }

  enum CodingKeys: String, CodingKey {
    case concertID = "p_concert_id"
    case cursorCreatedAt = "p_cursor_created_at"
    case cursorID = "p_cursor_id"
    case limit = "p_limit"
  }
}

private struct CommentMutationParameters: Encodable, Sendable {
  let concertID: UUID
  let body: String

  enum CodingKeys: String, CodingKey {
    case concertID = "p_concert_id"
    case body = "p_body"
  }
}

private struct CommentUpdateParameters: Encodable, Sendable {
  let commentID: UUID
  let body: String

  enum CodingKeys: String, CodingKey {
    case commentID = "p_comment_id"
    case body = "p_body"
  }
}

private struct CommentIDParameters: Encodable, Sendable {
  let commentID: UUID

  enum CodingKeys: String, CodingKey {
    case commentID = "p_comment_id"
  }
}

private struct FriendsActivityParameters: Encodable, Sendable {
  let cursorOccurredAt: String?
  let cursorID: UUID?
  let limit = 30

  init(cursor: FriendsActivityCursor?) {
    cursorOccurredAt = cursor.map { ConcertDateCoding.dateTimeString($0.occurredAt) }
    cursorID = cursor?.eventID
  }

  enum CodingKeys: String, CodingKey {
    case cursorOccurredAt = "p_cursor_occurred_at"
    case cursorID = "p_cursor_id"
    case limit = "p_limit"
  }
}

private struct ProfileConcertHistoryParameters: Encodable, Sendable {
  let profileID: UUID
  let search: String?
  let year: Int?
  let visibility: ConcertVisibility?
  let cursorDate: String?
  let cursorID: UUID?
  let limit = 30

  init(profileID: UUID, query: ConcertHistoryQuery, cursor: ConcertHistoryCursor?) {
    self.profileID = profileID
    search = query.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      ? nil
      : query.searchText
    year = query.year
    visibility = query.visibility
    cursorDate = cursor?.concertDate
    cursorID = cursor?.concertID
  }

  enum CodingKeys: String, CodingKey {
    case profileID = "p_profile_id"
    case search = "p_search"
    case year = "p_year"
    case visibility = "p_visibility"
    case cursorDate = "p_cursor_date"
    case cursorID = "p_cursor_id"
    case limit = "p_limit"
  }
}

private struct ConcertCollaboratorRecord: Decodable, Sendable {
  let id: UUID
  let username: String
  let displayName: String
  let isOwner: Bool
  let taggedAt: String

  enum CodingKeys: String, CodingKey {
    case id
    case username
    case displayName = "display_name"
    case isOwner = "is_owner"
    case taggedAt = "tagged_at"
  }
}

private struct ConcertCommentRecord: Decodable, Sendable {
  let id: UUID
  let concertID: UUID
  let authorID: UUID
  let username: String
  let displayName: String
  let body: String?
  let createdAt: String
  let updatedAt: String
  let deletedAt: String?

  enum CodingKeys: String, CodingKey {
    case id
    case concertID = "concert_id"
    case authorID = "author_id"
    case username
    case displayName = "display_name"
    case body
    case createdAt = "created_at"
    case updatedAt = "updated_at"
    case deletedAt = "deleted_at"
  }
}

private struct FriendActivityRecord: Decodable, Sendable {
  let id: UUID
  let concertID: UUID
  let actorID: UUID
  let actorUsername: String
  let actorDisplayName: String
  let eventType: String
  let occurredAt: String
  let primaryArtist: String
  let venueName: String
  let concertDate: String

  enum CodingKeys: String, CodingKey {
    case id
    case concertID = "concert_id"
    case actorID = "actor_id"
    case actorUsername = "actor_username"
    case actorDisplayName = "actor_display_name"
    case eventType = "event_type"
    case occurredAt = "occurred_at"
    case primaryArtist = "primary_artist"
    case venueName = "venue_name"
    case concertDate = "concert_date"
  }
}

private struct ProfileConcertHistoryRecord: Decodable, Sendable {
  let id: UUID
  let ownerID: UUID
  let venueName: String
  let city: String?
  let concertDate: String
  let startsAt: String?
  let venueTimeZone: String?
  let tour: String?
  let visibility: String
  let createdAt: String
  let updatedAt: String
  let lastActivityAt: String
  let primaryArtist: String

  enum CodingKeys: String, CodingKey {
    case id
    case ownerID = "owner_id"
    case venueName = "venue_name"
    case city
    case concertDate = "concert_date"
    case startsAt = "starts_at"
    case venueTimeZone = "venue_time_zone"
    case tour
    case visibility
    case createdAt = "created_at"
    case updatedAt = "updated_at"
    case lastActivityAt = "last_activity_at"
    case primaryArtist = "primary_artist"
  }
}

private enum CommentAuthorLabel {
  case you
}

private extension Concert {
  init(databaseRecord: PublicSchema.ConcertsSelect) throws {
    guard
      let visibility = ConcertVisibility(rawValue: databaseRecord.visibility.rawValue),
      let createdAt = ConcertDateCoding.dateTime(from: databaseRecord.createdAt),
      let updatedAt = ConcertDateCoding.dateTime(from: databaseRecord.updatedAt),
      let lastActivityAt = ConcertDateCoding.dateTime(from: databaseRecord.lastActivityAt)
    else {
      throw ConcertRepositoryFailure.invalidRecord
    }

    let startsAt = try databaseRecord.startsAt.map {
      guard let date = ConcertDateCoding.dateTime(from: $0) else {
        throw ConcertRepositoryFailure.invalidRecord
      }
      return date
    }

    self.init(
      id: databaseRecord.id,
      ownerID: databaseRecord.ownerId,
      venueName: databaseRecord.venueName,
      city: databaseRecord.city,
      concertDate: databaseRecord.concertDate,
      startsAt: startsAt,
      venueTimeZone: databaseRecord.venueTimeZone,
      tour: databaseRecord.tour,
      visibility: visibility,
      createdAt: createdAt,
      updatedAt: updatedAt,
      lastActivityAt: lastActivityAt,
      version: databaseRecord.version
    )
  }
}

private extension ConcertPreview {
  init(databaseRecord: ProfileConcertHistoryRecord) throws {
    guard
      let visibility = ConcertVisibility(rawValue: databaseRecord.visibility),
      let createdAt = ConcertDateCoding.dateTime(from: databaseRecord.createdAt),
      let updatedAt = ConcertDateCoding.dateTime(from: databaseRecord.updatedAt),
      let lastActivityAt = ConcertDateCoding.dateTime(from: databaseRecord.lastActivityAt)
    else {
      throw ConcertRepositoryFailure.invalidRecord
    }
    let startsAt = try databaseRecord.startsAt.map {
      guard let date = ConcertDateCoding.dateTime(from: $0) else {
        throw ConcertRepositoryFailure.invalidRecord
      }
      return date
    }
    self.init(
      concert: Concert(
        id: databaseRecord.id,
        ownerID: databaseRecord.ownerID,
        venueName: databaseRecord.venueName,
        city: databaseRecord.city,
        concertDate: databaseRecord.concertDate,
        startsAt: startsAt,
        venueTimeZone: databaseRecord.venueTimeZone,
        tour: databaseRecord.tour,
        visibility: visibility,
        createdAt: createdAt,
        updatedAt: updatedAt,
        lastActivityAt: lastActivityAt
      ),
      primaryArtistName: databaseRecord.primaryArtist
    )
  }
}

private extension ConcertArtist {
  init(databaseRecord: PublicSchema.ConcertArtistsSelect) {
    self.init(
      id: databaseRecord.id,
      name: databaseRecord.artistName,
      lineupPosition: Int(databaseRecord.lineupPosition),
      isPrimary: databaseRecord.isPrimary
    )
  }
}

private extension SetlistEntry {
  init(databaseRecord: PublicSchema.SetlistItemsSelect) {
    self.init(
      id: databaseRecord.id,
      position: Int(databaseRecord.setPosition),
      title: databaseRecord.songTitle
    )
  }
}

private extension ConcertTimelineEvent {
  init(databaseRecord: PublicSchema.ConcertEventsSelect) throws {
    guard
      let occurredAt = ConcertDateCoding.dateTime(from: databaseRecord.occurredAt),
      let kind = ConcertEventKind(rawValue: databaseRecord.eventType.rawValue)
    else {
      throw ConcertRepositoryFailure.invalidRecord
    }
    self.init(
      id: databaseRecord.id,
      actorID: databaseRecord.actorId,
      occurredAt: occurredAt,
      title: kind.timelineTitle,
      kind: kind
    )
  }
}

private extension ConcertCollaborator {
  init(databaseRecord: ConcertCollaboratorRecord) throws {
    guard let taggedAt = ConcertDateCoding.dateTime(from: databaseRecord.taggedAt) else {
      throw ConcertRepositoryFailure.invalidRecord
    }
    self.init(
      id: databaseRecord.id,
      username: databaseRecord.username,
      displayName: databaseRecord.displayName,
      isOwner: databaseRecord.isOwner,
      taggedAt: taggedAt
    )
  }
}

private extension ConcertComment {
  init(databaseRecord: ConcertCommentRecord) throws {
    guard
      let createdAt = ConcertDateCoding.dateTime(from: databaseRecord.createdAt),
      let updatedAt = ConcertDateCoding.dateTime(from: databaseRecord.updatedAt)
    else {
      throw ConcertRepositoryFailure.invalidRecord
    }
    let deletedAt = try databaseRecord.deletedAt.map {
      guard let date = ConcertDateCoding.dateTime(from: $0) else {
        throw ConcertRepositoryFailure.invalidRecord
      }
      return date
    }
    self.init(
      id: databaseRecord.id,
      concertID: databaseRecord.concertID,
      authorID: databaseRecord.authorID,
      username: databaseRecord.username,
      displayName: databaseRecord.displayName,
      body: databaseRecord.body,
      createdAt: createdAt,
      updatedAt: updatedAt,
      deletedAt: deletedAt
    )
  }

  init(databaseRecord: PublicSchema.CommentsSelect, authorLabel: CommentAuthorLabel) throws {
    guard
      let createdAt = ConcertDateCoding.dateTime(from: databaseRecord.createdAt),
      let updatedAt = ConcertDateCoding.dateTime(from: databaseRecord.updatedAt)
    else {
      throw ConcertRepositoryFailure.invalidRecord
    }
    let deletedAt = try databaseRecord.deletedAt.map {
      guard let date = ConcertDateCoding.dateTime(from: $0) else {
        throw ConcertRepositoryFailure.invalidRecord
      }
      return date
    }
    self.init(
      id: databaseRecord.id,
      concertID: databaseRecord.concertId,
      authorID: databaseRecord.authorId,
      username: "you",
      displayName: "You",
      body: databaseRecord.body,
      createdAt: createdAt,
      updatedAt: updatedAt,
      deletedAt: deletedAt
    )
  }
}

private extension FriendActivity {
  init(databaseRecord: FriendActivityRecord) throws {
    guard
      let kind = ConcertEventKind(rawValue: databaseRecord.eventType),
      let occurredAt = ConcertDateCoding.dateTime(from: databaseRecord.occurredAt)
    else {
      throw ConcertRepositoryFailure.invalidRecord
    }
    self.init(
      id: databaseRecord.id,
      concertID: databaseRecord.concertID,
      actorID: databaseRecord.actorID,
      actorUsername: databaseRecord.actorUsername,
      actorDisplayName: databaseRecord.actorDisplayName,
      eventKind: kind,
      occurredAt: occurredAt,
      primaryArtistName: databaseRecord.primaryArtist,
      venueName: databaseRecord.venueName,
      concertDate: databaseRecord.concertDate
    )
  }
}

private enum ConcertDateCoding {
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

private enum ConcertRepositoryFailure: LocalizedError {
  case conflict
  case permissionDenied
  case rateLimited
  case validation
  case unavailable
  case invalidRecord
  case unexpected

  init(_ error: Error) {
    let description = error.localizedDescription.lowercased()
    if description.contains("40001") || description.contains("changed elsewhere") {
      self = .conflict
    } else if description.contains("42501") || description.contains("permission") || description.contains("access") {
      self = .permissionDenied
    } else if description.contains("limit") || description.contains("wait a moment") {
      self = .rateLimited
    } else if description.contains("22023") || description.contains("required") || description.contains("must") {
      self = .validation
    } else if description.contains("no longer available") {
      self = .unavailable
    } else {
      self = .unexpected
    }
  }

  var errorDescription: String? {
    switch self {
    case .conflict:
      "This concert changed somewhere else. Refresh it, then try your change again."
    case .permissionDenied:
      "You no longer have access to make that change."
    case .rateLimited:
      "Take a beat before trying that again."
    case .validation:
      "A few details need another look before this can be saved."
    case .unavailable:
      "That concert is no longer available."
    case .invalidRecord, .unexpected:
      "Something didn’t load cleanly. Please try again."
    }
  }
}
