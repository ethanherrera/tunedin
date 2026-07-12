#if DEBUG
  // The development repository deliberately mirrors the full collaboration surface.
  // swiftlint:disable type_body_length
  import Foundation

  actor DevelopmentConcertRepository: ConcertRepository {
    private var details: [UUID: ConcertDetail]
    private var commentsByConcert: [UUID: [ConcertComment]] = [:]
    private var albumPhotosByConcert: [UUID: [ConcertAlbumPhoto]] = [:]

    init() {
      details = Dictionary(uniqueKeysWithValues: Self.seededDetails.map { ($0.concert.id, $0) })
      commentsByConcert[Self.mitskiID] = [
        ConcertComment(
          id: UUID(),
          concertID: Self.mitskiID,
          authorID: DevelopmentSocialFixture.morganID,
          username: "morgan_moon",
          displayName: "Morgan Moon",
          body: "The room felt like it was holding its breath.",
          createdAt: Date(timeIntervalSince1970: 1_758_205_600),
          updatedAt: Date(timeIntervalSince1970: 1_758_205_600),
          deletedAt: nil
        )
      ]
    }

    func createPrivateConcert(_ input: ConcertCreationInput) async throws -> Concert {
      let now = Date()
      let concert = Concert(
        id: UUID(),
        ownerID: DevelopmentSocialFixture.currentUserID,
        venueName: input.venueName,
        city: input.city,
        concertDate: input.concertDate,
        startsAt: input.startsAt,
        venueTimeZone: input.venueTimeZone,
        tour: input.tour,
        visibility: .private,
        createdAt: now,
        updatedAt: now,
        lastActivityAt: now
      )
      let artists = input.artists.enumerated().map { index, artist in
        ConcertArtist(
          id: UUID(),
          name: artist.name,
          lineupPosition: index + 1,
          isPrimary: artist.isPrimary
        )
      }
      let setlist = input.setlist.enumerated().map { index, title in
        SetlistEntry(id: UUID(), position: index + 1, title: title)
      }
      details[concert.id] = ConcertDetail(
        concert: concert,
        artists: artists,
        setlist: setlist,
        history: [
          ConcertTimelineEvent(
            id: UUID(),
            actorID: DevelopmentSocialFixture.currentUserID,
            occurredAt: now,
            title: ConcertEventKind.concertCreated.timelineTitle
          )
        ]
      )
      return concert
    }

    func setConcertPhoto(_: Data, concertID: UUID) async throws -> Concert {
      guard let detail = details[concertID] else { throw DevelopmentConcertRepositoryError.notFound }
      return detail.concert
    }

    func removeConcertPhoto(concertID: UUID) async throws -> Concert {
      guard let detail = details[concertID] else { throw DevelopmentConcertRepositoryError.notFound }
      return detail.concert
    }

    nonisolated func concertPhotoURL(concertID _: UUID, objectPath _: String, version _: Int64) async throws -> URL {
      throw DevelopmentConcertRepositoryError.notFound
    }

    nonisolated func albumPolicy() async throws -> ConcertAlbumPolicy {
      ConcertAlbumPolicy(
        policyVersion: 1,
        concertPhotoLimit: 100,
        contributorPhotoLimit: 30,
        reservationLimit24Hours: 10,
        pickerBatchLimit: 10,
        captionCharacterLimit: 300,
        attachedFileByteLimit: 2_097_152,
        pendingReservationLifetimeSeconds: 3600
      )
    }

    func reserveAlbumPhoto(concertID: UUID, photoID: UUID) async throws -> ConcertPhotoReservation {
      _ = try detail(for: concertID)
      return ConcertPhotoReservation(
        photoID: photoID,
        concertID: concertID,
        objectPath: "concerts/\(concertID.uuidString.lowercased())/album/\(photoID.uuidString.lowercased()).jpg",
        expiresAt: Date().addingTimeInterval(3600)
      )
    }

    func uploadReservedAlbumPhoto(_: Data, reservation: ConcertPhotoReservation) async throws -> ConcertAlbumPhoto {
      let photo = ConcertAlbumPhoto(
        id: reservation.photoID,
        concertID: reservation.concertID,
        uploaderID: DevelopmentSocialFixture.currentUserID,
        username: "you",
        displayName: "You",
        objectPath: reservation.objectPath,
        caption: nil,
        version: 1,
        attachedAt: Date()
      )
      albumPhotosByConcert[reservation.concertID, default: []].insert(photo, at: 0)
      return photo
    }

    func albumPhotos(concertID: UUID, cursor: ConcertAlbumPhotoCursor?) async throws -> [ConcertAlbumPhoto] {
      let photos = albumPhotosByConcert[concertID] ?? []
      guard let cursor else { return Array(photos.prefix(30)) }
      return Array(photos.drop(while: { $0.id != cursor.photoID }).dropFirst().prefix(30))
    }

    nonisolated func albumPhotoURL(photoID _: UUID, objectPath _: String, version _: Int64) async throws -> URL {
      throw DevelopmentConcertRepositoryError.notFound
    }

    func updateAlbumPhotoCaption(photoID: UUID, caption: String?) async throws -> ConcertAlbumPhoto {
      for concertID in albumPhotosByConcert.keys {
        guard let index = albumPhotosByConcert[concertID]?.firstIndex(where: { $0.id == photoID }),
              let photo = albumPhotosByConcert[concertID]?[index] else { continue }
        let updated = ConcertAlbumPhoto(
          id: photo.id,
          concertID: photo.concertID,
          uploaderID: photo.uploaderID,
          username: photo.username,
          displayName: photo.displayName,
          objectPath: photo.objectPath,
          caption: caption,
          version: photo.version + 1,
          attachedAt: photo.attachedAt
        )
        albumPhotosByConcert[concertID]?[index] = updated
        return updated
      }
      throw DevelopmentConcertRepositoryError.notFound
    }

    func deleteAlbumPhoto(photoID: UUID) async throws {
      for concertID in albumPhotosByConcert.keys {
        albumPhotosByConcert[concertID]?.removeAll(where: { $0.id == photoID })
      }
    }

    func updateConcert(_ input: ConcertUpdateInput) async throws -> Concert {
      var detail = try detail(for: input.concertID)
      try assertCurrentVersion(detail.concert, expected: input.expectedVersion)
      let role = currentRole(in: detail)
      guard role != .viewer else {
        throw DevelopmentConcertRepositoryError.permissionDenied
      }
      if detail.concert.visibility != .private, input.visibility == .private, role != .owner {
        throw DevelopmentConcertRepositoryError.ownerRequired
      }

      let now = Date()
      let updatedConcert = Concert(
        id: detail.concert.id,
        ownerID: detail.concert.ownerID,
        venueName: input.venueName,
        city: input.city,
        concertDate: input.concertDate,
        startsAt: input.startsAt,
        venueTimeZone: input.venueTimeZone,
        tour: input.tour,
        visibility: input.visibility,
        createdAt: detail.concert.createdAt,
        updatedAt: now,
        lastActivityAt: now,
        version: detail.concert.version + 1
      )
      let artists = input.artists.enumerated().map { index, artist in
        ConcertArtist(
          id: detail.artists[safe: index]?.id ?? UUID(),
          name: artist.name,
          lineupPosition: index + 1,
          isPrimary: artist.isPrimary
        )
      }
      let setlist = input.setlist.enumerated().map { index, title in
        SetlistEntry(id: detail.setlist[safe: index]?.id ?? UUID(), position: index + 1, title: title)
      }
      let kind: ConcertEventKind = input.setlist != detail.setlist.map(\.title)
        ? .setlistUpdated
        : .concertUpdated
      detail = ConcertDetail(
        concert: updatedConcert,
        artists: artists,
        setlist: setlist,
        history: detail.history + [timelineEvent(kind: kind, at: now)],
        collaborators: input.visibility == .private ? [] : detail.collaborators
      )
      details[input.concertID] = detail
      return updatedConcert
    }

    func tagCollaborator(
      concertID: UUID,
      profileID: UUID,
      expectedVersion: Int64
    ) async throws -> Concert {
      var detail = try detail(for: concertID)
      try assertCurrentVersion(detail.concert, expected: expectedVersion)
      guard currentRole(in: detail).canManagePeople else {
        throw DevelopmentConcertRepositoryError.permissionDenied
      }
      guard detail.concert.visibility != .private else {
        throw DevelopmentConcertRepositoryError.privateConcert
      }
      guard profileID != detail.concert.ownerID else { return detail.concert }

      if !detail.collaborators.contains(where: { $0.id == profileID }) {
        guard let profile = Self.socialProfile(id: profileID) else {
          throw DevelopmentConcertRepositoryError.notFound
        }
        detail = ConcertDetail(
          concert: bumped(detail.concert),
          artists: detail.artists,
          setlist: detail.setlist,
          history: detail.history + [timelineEvent(kind: .collaboratorTagged)],
          collaborators: detail.collaborators + [
            ConcertCollaborator(
              id: profile.id,
              username: profile.username,
              displayName: profile.displayName,
              isOwner: false,
              taggedAt: Date()
            )
          ]
        )
        details[concertID] = detail
      }
      return detail.concert
    }

    func removeCollaborator(
      concertID: UUID,
      profileID: UUID,
      expectedVersion: Int64
    ) async throws -> Concert {
      var detail = try detail(for: concertID)
      try assertCurrentVersion(detail.concert, expected: expectedVersion)
      guard currentRole(in: detail) == .owner else {
        throw DevelopmentConcertRepositoryError.ownerRequired
      }
      detail = ConcertDetail(
        concert: bumped(detail.concert),
        artists: detail.artists,
        setlist: detail.setlist,
        history: detail.history + [timelineEvent(kind: .collaboratorRemoved)],
        collaborators: detail.collaborators.filter { $0.id != profileID }
      )
      details[concertID] = detail
      return detail.concert
    }

    func transferOwnership(
      concertID: UUID,
      newOwnerID: UUID,
      expectedVersion: Int64
    ) async throws -> Concert {
      var detail = try detail(for: concertID)
      try assertCurrentVersion(detail.concert, expected: expectedVersion)
      guard currentRole(in: detail) == .owner else {
        throw DevelopmentConcertRepositoryError.ownerRequired
      }
      guard let newOwner = detail.collaborators.first(where: { $0.id == newOwnerID }) else {
        throw DevelopmentConcertRepositoryError.notFound
      }

      let formerOwner = Self.currentCollaborator(isOwner: false)
      let concert = Concert(
        id: detail.concert.id,
        ownerID: newOwnerID,
        venueName: detail.concert.venueName,
        city: detail.concert.city,
        concertDate: detail.concert.concertDate,
        startsAt: detail.concert.startsAt,
        venueTimeZone: detail.concert.venueTimeZone,
        tour: detail.concert.tour,
        visibility: detail.concert.visibility,
        createdAt: detail.concert.createdAt,
        updatedAt: Date(),
        lastActivityAt: Date(),
        version: detail.concert.version + 1
      )
      detail = ConcertDetail(
        concert: concert,
        artists: detail.artists,
        setlist: detail.setlist,
        history: detail.history + [timelineEvent(kind: .ownershipTransferred)],
        collaborators: detail.collaborators.filter { $0.id != newOwnerID } + [formerOwner]
      )
      details[concertID] = detail
      return concert
    }

    func deleteConcert(id: UUID) async throws {
      let detail = try detail(for: id)
      guard currentRole(in: detail) == .owner else {
        throw DevelopmentConcertRepositoryError.ownerRequired
      }
      details[id] = nil
      commentsByConcert[id] = nil
    }

    func collaborators(concertID: UUID) async throws -> [ConcertCollaborator] {
      let detail = try detail(for: concertID)
      guard currentRole(in: detail).canManagePeople else {
        throw DevelopmentConcertRepositoryError.permissionDenied
      }
      return [Self.ownerCollaborator(for: detail.concert)] + detail.collaborators
    }

    func comments(
      concertID: UUID,
      cursor: ConcertCommentCursor?
    ) async throws -> [ConcertComment] {
      let detail = try detail(for: concertID)
      guard canView(detail) else { throw DevelopmentConcertRepositoryError.permissionDenied }
      let sorted = (commentsByConcert[concertID] ?? []).sorted {
        if $0.createdAt == $1.createdAt {
          return $0.id.uuidString > $1.id.uuidString
        }
        return $0.createdAt > $1.createdAt
      }
      let afterCursor = sorted.filter { comment in
        guard let cursor else { return true }
        return comment.createdAt < cursor.createdAt
          || (comment.createdAt == cursor.createdAt && comment.id.uuidString < cursor.commentID.uuidString)
      }
      return Array(afterCursor.prefix(30))
    }

    func createComment(concertID: UUID, body: String) async throws -> ConcertComment {
      let detail = try detail(for: concertID)
      guard canView(detail) else { throw DevelopmentConcertRepositoryError.permissionDenied }
      let text = ConcertInput.normalizedText(body)
      guard ConcertInput.isValidRequiredText(text, maximumLength: 1000) else {
        throw DevelopmentConcertRepositoryError.invalidComment
      }
      let now = Date()
      let comment = ConcertComment(
        id: UUID(),
        concertID: concertID,
        authorID: DevelopmentSocialFixture.currentUserID,
        username: DevelopmentSocialFixture.currentProfile.username,
        displayName: DevelopmentSocialFixture.currentProfile.displayName,
        body: text,
        createdAt: now,
        updatedAt: now,
        deletedAt: nil
      )
      commentsByConcert[concertID, default: []].append(comment)
      appendHistory(kind: .commentAdded, to: concertID)
      return comment
    }

    func updateComment(commentID: UUID, body: String) async throws -> ConcertComment {
      let text = ConcertInput.normalizedText(body)
      guard ConcertInput.isValidRequiredText(text, maximumLength: 1000) else {
        throw DevelopmentConcertRepositoryError.invalidComment
      }
      guard let concertID = commentsByConcert.first(where: { _, comments in
        comments.contains(where: { $0.id == commentID })
      })?.key,
        let index = commentsByConcert[concertID]?.firstIndex(where: { $0.id == commentID }),
        let existing = commentsByConcert[concertID]?[index],
        existing.authorID == DevelopmentSocialFixture.currentUserID,
        !existing.isDeleted
      else { throw DevelopmentConcertRepositoryError.commentAuthorRequired }

      let updated = ConcertComment(
        id: existing.id,
        concertID: existing.concertID,
        authorID: existing.authorID,
        username: existing.username,
        displayName: existing.displayName,
        body: text,
        createdAt: existing.createdAt,
        updatedAt: Date(),
        deletedAt: nil
      )
      commentsByConcert[concertID]?[index] = updated
      appendHistory(kind: .commentUpdated, to: concertID)
      return updated
    }

    func deleteComment(commentID: UUID) async throws {
      guard let concertID = commentsByConcert.first(where: { _, comments in
        comments.contains(where: { $0.id == commentID })
      })?.key,
        let index = commentsByConcert[concertID]?.firstIndex(where: { $0.id == commentID }),
        let existing = commentsByConcert[concertID]?[index],
        existing.authorID == DevelopmentSocialFixture.currentUserID,
        !existing.isDeleted
      else { throw DevelopmentConcertRepositoryError.commentAuthorRequired }

      commentsByConcert[concertID]?[index] = ConcertComment(
        id: existing.id,
        concertID: existing.concertID,
        authorID: existing.authorID,
        username: existing.username,
        displayName: existing.displayName,
        body: nil,
        createdAt: existing.createdAt,
        updatedAt: Date(),
        deletedAt: Date()
      )
      appendHistory(kind: .commentDeleted, to: concertID)
    }

    func friendsActivity(cursor: FriendsActivityCursor?) async throws -> [FriendActivity] {
      let activities = details.values.flatMap { detail -> [FriendActivity] in
        guard detail.concert.ownerID == DevelopmentSocialFixture.morganID,
              detail.concert.visibility == .friends
        else { return [] }
        let artist = detail.artists.first(where: \.isPrimary)?.name ?? "A concert"
        return detail.history.map { event in
          FriendActivity(
            id: event.id,
            concertID: detail.concert.id,
            actorID: DevelopmentSocialFixture.morganID,
            actorUsername: "morgan_moon",
            actorDisplayName: "Morgan Moon",
            eventKind: event.kind,
            occurredAt: event.occurredAt,
            primaryArtistName: artist,
            venueName: detail.concert.venueName,
            concertDate: detail.concert.concertDate
          )
        }
      }
      .sorted {
        if $0.occurredAt == $1.occurredAt {
          return $0.id.uuidString > $1.id.uuidString
        }
        return $0.occurredAt > $1.occurredAt
      }
      let afterCursor = activities.filter { activity in
        guard let cursor else { return true }
        return activity.occurredAt < cursor.occurredAt
          || (activity.occurredAt == cursor.occurredAt && activity.id.uuidString < cursor.eventID.uuidString)
      }
      return Array(afterCursor.prefix(30))
    }

    func profileConcertHistory(
      profileID: UUID,
      query: ConcertHistoryQuery,
      cursor: ConcertHistoryCursor?
    ) async throws -> [ConcertPreview] {
      let normalizedSearch = query.searchText
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()

      let previews = details.values.compactMap { detail -> ConcertPreview? in
        let isProfileConcert = detail.concert.ownerID == profileID
          || detail.collaborators.contains(where: { $0.id == profileID })
        guard isProfileConcert else { return nil }
        guard canView(detail) || profileID == DevelopmentSocialFixture.currentUserID else { return nil }
        guard query.year.map({ detail.concert.concertDate.hasPrefix(String($0)) }) ?? true else {
          return nil
        }
        guard query.visibility.map({ detail.concert.visibility == $0 }) ?? true else { return nil }

        let artist = detail.artists.first(where: \.isPrimary)?.name ?? "Unknown artist"
        let searchableValues = [artist, detail.concert.venueName, detail.concert.city, detail.concert.tour]
          .compactMap { $0?.lowercased() }
        guard normalizedSearch.isEmpty || searchableValues.contains(where: { $0.contains(normalizedSearch) }) else {
          return nil
        }
        return ConcertPreview(concert: detail.concert, primaryArtistName: artist)
      }
      .sorted {
        if $0.concert.concertDate == $1.concert.concertDate {
          return $0.id.uuidString > $1.id.uuidString
        }
        return $0.concert.concertDate > $1.concert.concertDate
      }

      guard let cursor else { return Array(previews.prefix(30)) }
      let remaining = previews.drop(while: {
        $0.concert.concertDate > cursor.concertDate
          || ($0.concert.concertDate == cursor.concertDate && $0.id.uuidString >= cursor.concertID.uuidString)
      })
      return Array(remaining.prefix(30))
    }

    func fetchConcertDetail(id: UUID, viewerID: UUID) async throws -> ConcertDetail {
      let detail = try detail(for: id)
      guard canView(detail, viewerID: viewerID) else { throw DevelopmentConcertRepositoryError.notFound }
      return detail
    }

    nonisolated func observeConcert(id _: UUID) -> AsyncStream<Void> {
      AsyncStream { continuation in continuation.finish() }
    }

    nonisolated func observeFriendsActivity() -> AsyncStream<Void> {
      AsyncStream { continuation in continuation.finish() }
    }

    private func detail(for id: UUID) throws -> ConcertDetail {
      guard let detail = details[id] else { throw DevelopmentConcertRepositoryError.notFound }
      return detail
    }

    private func currentRole(in detail: ConcertDetail) -> ConcertViewerRole {
      if detail.concert.ownerID == DevelopmentSocialFixture.currentUserID {
        return .owner
      }
      if detail.collaborators.contains(where: { $0.id == DevelopmentSocialFixture.currentUserID }) {
        return .editor
      }
      return .viewer
    }

    private func canView(_ detail: ConcertDetail, viewerID: UUID = DevelopmentSocialFixture.currentUserID) -> Bool {
      detail.concert.ownerID == viewerID
        || detail.collaborators.contains(where: { $0.id == viewerID })
        || detail.concert.visibility == .friends
    }

    private func assertCurrentVersion(_ concert: Concert, expected: Int64) throws {
      guard concert.version == expected else { throw DevelopmentConcertRepositoryError.conflict }
    }

    private func bumped(_ concert: Concert) -> Concert {
      Concert(
        id: concert.id,
        ownerID: concert.ownerID,
        venueName: concert.venueName,
        city: concert.city,
        concertDate: concert.concertDate,
        startsAt: concert.startsAt,
        venueTimeZone: concert.venueTimeZone,
        tour: concert.tour,
        visibility: concert.visibility,
        createdAt: concert.createdAt,
        updatedAt: Date(),
        lastActivityAt: Date(),
        version: concert.version + 1
      )
    }

    private func appendHistory(kind: ConcertEventKind, to concertID: UUID) {
      guard var detail = details[concertID] else { return }
      detail = ConcertDetail(
        concert: detail.concert,
        artists: detail.artists,
        setlist: detail.setlist,
        history: detail.history + [timelineEvent(kind: kind)],
        collaborators: detail.collaborators
      )
      details[concertID] = detail
    }

    private func timelineEvent(kind: ConcertEventKind, at date: Date = Date()) -> ConcertTimelineEvent {
      ConcertTimelineEvent(
        id: UUID(),
        actorID: DevelopmentSocialFixture.currentUserID,
        occurredAt: date,
        title: kind.timelineTitle,
        kind: kind
      )
    }

    private static func socialProfile(id: UUID) -> SocialProfile? {
      if id == DevelopmentSocialFixture.currentUserID {
        return DevelopmentSocialFixture.currentProfile
      }
      return DevelopmentSocialFixture.profiles.first(where: { $0.id == id })
    }

    private static func ownerCollaborator(for concert: Concert) -> ConcertCollaborator {
      let profile = socialProfile(id: concert.ownerID) ?? DevelopmentSocialFixture.currentProfile
      return ConcertCollaborator(
        id: profile.id,
        username: profile.username,
        displayName: profile.displayName,
        isOwner: true,
        taggedAt: concert.createdAt
      )
    }

    private static func currentCollaborator(isOwner: Bool) -> ConcertCollaborator {
      ConcertCollaborator(
        id: DevelopmentSocialFixture.currentUserID,
        username: DevelopmentSocialFixture.currentProfile.username,
        displayName: DevelopmentSocialFixture.currentProfile.displayName,
        isOwner: isOwner,
        taggedAt: Date()
      )
    }

    private static let mitskiID = UUID(uuidString: "D1000000-0000-0000-0000-000000000001")!

    private static let seededDetails: [ConcertDetail] = [
      detail(
        id: "D1000000-0000-0000-0000-000000000001",
        ownerID: DevelopmentSocialFixture.currentUserID,
        artist: "Mitski",
        venue: "The Greek Theatre",
        city: "Berkeley",
        date: "2025-09-18",
        tour: "The Land Is Inhospitable Tour",
        visibility: .collaborators,
        setlist: ["First Love / Late Spring", "My Love Mine All Mine", "I Bet on Losing Dogs"],
        collaborators: [
          ConcertCollaborator(
            id: DevelopmentSocialFixture.morganID,
            username: "morgan_moon",
            displayName: "Morgan Moon",
            isOwner: false,
            taggedAt: Date(timeIntervalSince1970: 1_758_205_600)
          )
        ]
      ),
      detail(
        id: "D1000000-0000-0000-0000-000000000002",
        ownerID: DevelopmentSocialFixture.currentUserID,
        artist: "Vampire Weekend",
        venue: "The Masonic",
        city: "San Francisco",
        date: "2025-05-29",
        tour: nil,
        visibility: .private,
        setlist: ["Oxford Comma", "Hannah Hunt", "This Life"]
      ),
      detail(
        id: "D1000000-0000-0000-0000-000000000003",
        ownerID: DevelopmentSocialFixture.morganID,
        artist: "Japanese Breakfast",
        venue: "The Fillmore",
        city: "San Francisco",
        date: "2025-10-04",
        tour: "Melancholy Tour",
        visibility: .friends,
        setlist: ["Be Sweet", "Paprika", "Posing in Bondage"]
      ),
      detail(
        id: "D1000000-0000-0000-0000-000000000004",
        ownerID: DevelopmentSocialFixture.morganID,
        artist: "Big Thief",
        venue: "Fox Theater",
        city: "Oakland",
        date: "2025-03-12",
        tour: nil,
        visibility: .friends,
        setlist: ["Simulation Swarm", "Vampire Empire", "Not"]
      )
    ]

    // swiftlint:disable:next function_parameter_count
    private static func detail(
      id rawID: String,
      ownerID: UUID,
      artist: String,
      venue: String,
      city: String,
      date: String,
      tour: String?,
      visibility: ConcertVisibility,
      setlist: [String],
      collaborators: [ConcertCollaborator] = []
    ) -> ConcertDetail {
      let id = UUID(uuidString: rawID)!
      guard let concertDay = ISO8601DateFormatter().date(from: "\(date)T12:00:00Z") else {
        fatalError("Development fixture has an invalid concert date: \(date)")
      }
      let createdAt = concertDay.addingTimeInterval(86400)
      let concert = Concert(
        id: id,
        ownerID: ownerID,
        venueName: venue,
        city: city,
        concertDate: date,
        startsAt: nil,
        venueTimeZone: nil,
        tour: tour,
        visibility: visibility,
        createdAt: createdAt,
        updatedAt: createdAt,
        lastActivityAt: createdAt
      )
      return ConcertDetail(
        concert: concert,
        artists: [ConcertArtist(id: UUID(), name: artist, lineupPosition: 1, isPrimary: true)],
        setlist: setlist.enumerated().map { index, title in
          SetlistEntry(id: UUID(), position: index + 1, title: title)
        },
        history: [
          ConcertTimelineEvent(
            id: UUID(),
            actorID: ownerID,
            occurredAt: createdAt,
            title: ConcertEventKind.concertCreated.timelineTitle
          )
        ],
        collaborators: collaborators
      )
    }
  }

  private enum DevelopmentConcertRepositoryError: LocalizedError {
    case notFound
    case permissionDenied
    case ownerRequired
    case conflict
    case privateConcert
    case invalidComment
    case commentAuthorRequired

    var errorDescription: String? {
      switch self {
      case .notFound:
        "That concert is no longer available."
      case .permissionDenied:
        "You no longer have permission to change this concert."
      case .ownerRequired:
        "Only the concert owner can do that."
      case .conflict:
        "This concert changed elsewhere. Refresh and try again."
      case .privateConcert:
        "Choose Collaborators or Friends before adding someone."
      case .invalidComment:
        "Write a comment before sharing it."
      case .commentAuthorRequired:
        "Only the person who wrote this note can change it."
      }
    }
  }

  private extension Array {
    subscript(safe index: Index) -> Element? {
      indices.contains(index) ? self[index] : nil
    }
  }
  // swiftlint:enable type_body_length
#endif
