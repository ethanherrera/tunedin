// swiftlint:disable file_length type_body_length

import Foundation
import Supabase

struct SupabaseConcertRepository: ConcertRepository {
  let client: SupabaseClient
  private let photoURLs = AvatarURLCache()
  private let albumPolicies = AlbumPolicyCache()

  func createPrivateConcert(_ input: ConcertCreationInput) async throws -> Concert {
    do {
      let response: PostgrestResponse<PublicSchema.ConcertsSelect> = try await client
        .rpc("create_private_concert", params: CreatePrivateConcertParameters(input: input))
        .single()
        .execute()
      return try Concert(databaseRecord: response.value)
    } catch {
      throw AppFailure(error)
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
      throw AppFailure(error)
    }
  }

  func setConcertPhoto(_ jpegData: Data, concertID: UUID) async throws -> Concert {
    let path = "concerts/\(concertID.uuidString.lowercased())/main.jpg"
    do {
      try await client.storage.from("images").upload(
        path, data: jpegData,
        options: FileOptions(cacheControl: "3600", contentType: "image/jpeg", upsert: true)
      )
      let response: PostgrestResponse<PublicSchema.ConcertsSelect> = try await client
        .rpc("set_concert_photo", params: ConcertIDParameters(concertID: concertID)).single().execute()
      await photoURLs.remove(profileID: concertID)
      return try Concert(databaseRecord: response.value)
    } catch {
      _ = try? await client.storage.from("images").remove(paths: [path])
      throw AppFailure(error)
    }
  }

  func removeConcertPhoto(concertID: UUID) async throws -> Concert {
    try await withAppFailure {
      let response: PostgrestResponse<String?> = try await client
        .rpc("remove_concert_photo", params: ConcertIDParameters(concertID: concertID)).execute()
      let path = response.value ?? "concerts/\(concertID.uuidString.lowercased())/main.jpg"
      _ = try await client.storage.from("images").remove(paths: [path])
      await photoURLs.remove(profileID: concertID)
      let userID = try await client.auth.session.user.id
      return try await fetchConcertDetail(id: concertID, viewerID: userID).concert
    }
  }

  func concertPhotoURL(concertID: UUID, objectPath: String, version: Int64) async throws -> URL {
    try await withAppFailure {
      if let url = await photoURLs.value(profileID: concertID, version: version) {
        return url
      }
      let url = try await client.storage.from("images").createSignedURL(
        path: objectPath, expiresIn: 3600, cacheNonce: String(version)
      )
      await photoURLs.insert(url, profileID: concertID, version: version)
      return url
    }
  }

  func albumPolicy() async throws -> ConcertAlbumPolicy {
    try await withAppFailure {
      if let cached = await albumPolicies.value() {
        return cached
      }
      let response: PostgrestResponse<ConcertAlbumPolicy> = try await client
        .rpc("concert_album_policy").single().execute()
      await albumPolicies.insert(response.value)
      return response.value
    }
  }

  func reserveAlbumPhoto(concertID: UUID, photoID: UUID) async throws -> ConcertPhotoReservation {
    try await withAppFailure {
      let response: PostgrestResponse<ConcertPhotoReservationRecord> = try await client
        .rpc("reserve_concert_photo", params: AlbumReservationParameters(concertID: concertID, photoID: photoID))
        .single().execute()
      return try ConcertPhotoReservation(databaseRecord: response.value)
    }
  }

  func uploadReservedAlbumPhoto(_ jpegData: Data, reservation: ConcertPhotoReservation) async throws -> ConcertAlbumPhoto {
    try await withAppFailure {
      let options = FileOptions(cacheControl: "3600", contentType: "image/jpeg")
      do {
        try await client.storage.from("images").upload(
          reservation.objectPath, data: jpegData, options: options
        )
      } catch {
        // The immutable reservation path permits a safe explicit retry after an
        // earlier request uploaded bytes but did not receive/finish attachment.
        try await client.storage.from("images").update(
          reservation.objectPath, data: jpegData, options: options
        )
      }
      let _: PostgrestResponse<ConcertPhotoReservationRecord> = try await client
        .rpc("attach_concert_photo", params: PhotoIDParameters(photoID: reservation.photoID)).single().execute()
      let photos = try await albumPhotos(concertID: reservation.concertID, cursor: nil)
      guard let attached = photos.first(where: { $0.id == reservation.photoID }) else {
        throw AppFailure.unexpected
      }
      return attached
    }
  }

  func albumPhotos(concertID: UUID, cursor: ConcertAlbumPhotoCursor?) async throws -> [ConcertAlbumPhoto] {
    try await withAppFailure {
      let response: PostgrestResponse<[ConcertAlbumPhotoRecord]> = try await client
        .rpc("list_concert_photos", params: AlbumListParameters(concertID: concertID, cursor: cursor)).execute()
      return try response.value.map(ConcertAlbumPhoto.init(databaseRecord:))
    }
  }

  func albumPhotoURL(photoID: UUID, objectPath: String, version: Int64) async throws -> URL {
    try await withAppFailure {
      if let url = await photoURLs.value(profileID: photoID, version: version) {
        return url
      }
      let url = try await client.storage.from("images").createSignedURL(
        path: objectPath, expiresIn: 3600, cacheNonce: String(version)
      )
      await photoURLs.insert(url, profileID: photoID, version: version)
      return url
    }
  }

  func updateAlbumPhotoCaption(photoID: UUID, caption: String?) async throws -> ConcertAlbumPhoto {
    try await withAppFailure {
      let response: PostgrestResponse<ConcertPhotoReservationRecord> = try await client
        .rpc("update_concert_photo_caption", params: AlbumCaptionParameters(photoID: photoID, caption: caption))
        .single().execute()
      let record = response.value
      let currentUser = try await client.auth.session.user.id
      guard let attachedAt = record.attachedAt.flatMap(ConcertDateCoding.dateTime(from:)) else {
        throw AppFailure.unexpected
      }
      return ConcertAlbumPhoto(
        id: record.id,
        concertID: record.concertID,
        uploaderID: record.uploaderID,
        username: record.uploaderID == currentUser ? "you" : "",
        displayName: record.uploaderID == currentUser ? "You" : "",
        objectPath: record.objectPath,
        caption: record.caption,
        version: record.version,
        attachedAt: attachedAt
      )
    }
  }

  func deleteAlbumPhoto(photoID: UUID) async throws {
    try await withAppFailure {
      let prepared: PostgrestResponse<String> = try await client
        .rpc("prepare_concert_photo_deletion", params: PhotoIDParameters(photoID: photoID)).single().execute()
      _ = try await client.storage.from("images").remove(paths: [prepared.value])
      let _: PostgrestResponse<Void> = try await client
        .rpc("finalize_concert_photo_deletion", params: PhotoIDParameters(photoID: photoID)).execute()
      await photoURLs.remove(profileID: photoID)
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
      throw AppFailure(error)
    }
  }

  func deleteConcert(id: UUID) async throws {
    do {
      let paths: PostgrestResponse<[ConcertDeletionPathRecord]> = try await client
        .rpc("prepare_concert_deletion", params: ConcertIDParameters(concertID: id)).execute()
      if !paths.value.isEmpty {
        _ = try await client.storage.from("images").remove(paths: paths.value.map(\.objectPath))
      }
      let _: PostgrestResponse<Void> = try await client
        .rpc("finalize_concert_deletion", params: ConcertIDParameters(concertID: id))
        .execute()
    } catch {
      throw AppFailure(error)
    }
  }

  func collaborators(concertID: UUID) async throws -> [ConcertCollaborator] {
    do {
      let response: PostgrestResponse<[ConcertCollaboratorRecord]> = try await client
        .rpc("list_concert_collaborators", params: ConcertIDParameters(concertID: concertID))
        .execute()
      return try response.value.map(ConcertCollaborator.init(databaseRecord:))
    } catch {
      throw AppFailure(error)
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
      throw AppFailure(error)
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
      throw AppFailure(error)
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
      throw AppFailure(error)
    }
  }

  func deleteComment(commentID: UUID) async throws {
    do {
      let _: PostgrestResponse<Void> = try await client
        .rpc("delete_concert_comment", params: CommentIDParameters(commentID: commentID))
        .execute()
    } catch {
      throw AppFailure(error)
    }
  }

  func friendsActivity(cursor: FriendsActivityCursor?) async throws -> [FriendActivity] {
    do {
      let response: PostgrestResponse<[FriendActivityRecord]> = try await client
        .rpc("friends_activity_feed", params: FriendsActivityParameters(cursor: cursor))
        .execute()
      return try response.value.map(FriendActivity.init(databaseRecord:))
    } catch {
      throw AppFailure(error)
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
      throw AppFailure(error)
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
      throw AppFailure(error)
    }
  }

  func observeConcert(id: UUID) -> AsyncStream<Void> {
    changeStream(
      name: "concert-\(id.uuidString)",
      subscriptions: [
        ("concert_events", "concert_id=eq.\(id.uuidString)"),
        ("concerts", "id=eq.\(id.uuidString)"),
        ("concert_photos", "concert_id=eq.\(id.uuidString)")
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
      throw AppFailure(error)
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

private struct PhotoIDParameters: Encodable, Sendable {
  let photoID: UUID
  enum CodingKeys: String, CodingKey { case photoID = "p_photo_id" }
}

private struct AlbumReservationParameters: Encodable, Sendable {
  let concertID: UUID
  let photoID: UUID
  enum CodingKeys: String, CodingKey {
    case concertID = "p_concert_id"
    case photoID = "p_photo_id"
  }
}

private struct AlbumCaptionParameters: Encodable, Sendable {
  let photoID: UUID
  let caption: String?
  enum CodingKeys: String, CodingKey {
    case photoID = "p_photo_id"
    case caption = "p_caption"
  }
}

private struct AlbumListParameters: Encodable, Sendable {
  let concertID: UUID
  let cursorAttachedAt: String?
  let cursorID: UUID?
  let limit = 30
  init(concertID: UUID, cursor: ConcertAlbumPhotoCursor?) {
    self.concertID = concertID
    cursorAttachedAt = cursor.map { ConcertDateCoding.dateTimeString($0.attachedAt) }
    cursorID = cursor?.photoID
  }

  enum CodingKeys: String, CodingKey {
    case concertID = "p_concert_id"
    case cursorAttachedAt = "p_cursor_attached_at"
    case cursorID = "p_cursor_id"
    case limit = "p_limit"
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
  let sort: String
  let cursorDate: String?
  let cursorUpdatedAt: String?
  let cursorText: String?
  let cursorID: UUID?
  let limit = 30

  init(profileID: UUID, query: ConcertHistoryQuery, cursor: ConcertHistoryCursor?) {
    self.profileID = profileID
    search = query.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      ? nil
      : query.searchText
    year = query.year
    visibility = query.visibility
    sort = query.sort.rawValue
    cursorDate = cursor?.concertDate
    cursorUpdatedAt = cursor?.updatedAt.map(ConcertDateCoding.dateTimeString)
    cursorText = cursor?.text
    cursorID = cursor?.concertID
  }

  enum CodingKeys: String, CodingKey {
    case profileID = "p_profile_id"
    case search = "p_search"
    case year = "p_year"
    case visibility = "p_visibility"
    case sort = "p_sort"
    case cursorDate = "p_cursor_date"
    case cursorUpdatedAt = "p_cursor_updated_at"
    case cursorText = "p_cursor_text"
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

private struct ConcertDeletionPathRecord: Decodable, Sendable {
  let objectPath: String
  enum CodingKeys: String, CodingKey { case objectPath = "object_path" }
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

private struct ConcertPhotoReservationRecord: Decodable, Sendable {
  let id: UUID
  let concertID: UUID
  let uploaderID: UUID
  let objectPath: String
  let caption: String?
  let version: Int64
  let attachedAt: String?
  let expiresAt: String
  enum CodingKeys: String, CodingKey {
    case id
    case concertID = "concert_id"
    case uploaderID = "uploader_id"
    case objectPath = "object_path"
    case caption, version
    case attachedAt = "attached_at"
    case expiresAt = "expires_at"
  }
}

private struct ConcertAlbumPhotoRecord: Decodable, Sendable {
  let id: UUID
  let concertID: UUID
  let uploaderID: UUID
  let username: String
  let displayName: String
  let objectPath: String
  let caption: String?
  let version: Int64
  let attachedAt: String
  enum CodingKeys: String, CodingKey {
    case id
    case concertID = "concert_id"
    case uploaderID = "uploader_id"
    case username
    case displayName = "display_name"
    case objectPath = "object_path"
    case caption, version
    case attachedAt = "attached_at"
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
  let changedFields: [String]
  let setlistPreview: [String]
  let setlistCount: Int
  let photoID: UUID?
  let photoObjectPath: String?
  let photoVersion: Int64

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
    case changedFields = "changed_fields"
    case setlistPreview = "setlist_preview"
    case setlistCount = "setlist_count"
    case photoID = "photo_id"
    case photoObjectPath = "photo_object_path"
    case photoVersion = "photo_version"
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
  let photoObjectPath: String?
  let photoVersion: Int64

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
    case photoObjectPath = "photo_object_path"
    case photoVersion = "photo_version"
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
      throw AppFailure.unexpected
    }

    let startsAt = try databaseRecord.startsAt.map {
      guard let date = ConcertDateCoding.dateTime(from: $0) else {
        throw AppFailure.unexpected
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
      version: databaseRecord.version,
      photoObjectPath: databaseRecord.photoObjectPath,
      photoVersion: databaseRecord.photoVersion
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
      throw AppFailure.unexpected
    }
    let startsAt = try databaseRecord.startsAt.map {
      guard let date = ConcertDateCoding.dateTime(from: $0) else {
        throw AppFailure.unexpected
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
        lastActivityAt: lastActivityAt,
        photoObjectPath: databaseRecord.photoObjectPath,
        photoVersion: databaseRecord.photoVersion
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
      throw AppFailure.unexpected
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
      throw AppFailure.unexpected
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
      throw AppFailure.unexpected
    }
    let deletedAt = try databaseRecord.deletedAt.map {
      guard let date = ConcertDateCoding.dateTime(from: $0) else {
        throw AppFailure.unexpected
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
      throw AppFailure.unexpected
    }
    let deletedAt = try databaseRecord.deletedAt.map {
      guard let date = ConcertDateCoding.dateTime(from: $0) else {
        throw AppFailure.unexpected
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

private extension ConcertPhotoReservation {
  init(databaseRecord: ConcertPhotoReservationRecord) throws {
    guard let expiresAt = ConcertDateCoding.dateTime(from: databaseRecord.expiresAt) else {
      throw AppFailure.unexpected
    }
    self.init(
      photoID: databaseRecord.id,
      concertID: databaseRecord.concertID,
      objectPath: databaseRecord.objectPath,
      expiresAt: expiresAt
    )
  }
}

private extension ConcertAlbumPhoto {
  init(databaseRecord: ConcertAlbumPhotoRecord) throws {
    guard let attachedAt = ConcertDateCoding.dateTime(from: databaseRecord.attachedAt) else {
      throw AppFailure.unexpected
    }
    self.init(
      id: databaseRecord.id,
      concertID: databaseRecord.concertID,
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

private extension FriendActivity {
  init(databaseRecord: FriendActivityRecord) throws {
    guard
      let kind = ConcertEventKind(rawValue: databaseRecord.eventType),
      let occurredAt = ConcertDateCoding.dateTime(from: databaseRecord.occurredAt)
    else {
      throw AppFailure.unexpected
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
    changedFields = databaseRecord.changedFields
    setlistPreview = databaseRecord.setlistPreview
    setlistCount = databaseRecord.setlistCount
    photoID = databaseRecord.photoID
    photoObjectPath = databaseRecord.photoObjectPath
    photoVersion = databaseRecord.photoVersion
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
