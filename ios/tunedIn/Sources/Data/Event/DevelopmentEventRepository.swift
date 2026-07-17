#if DEBUG
  import Foundation

  // The development actor owns the complete cross-phase fixture matrix.
  // swiftlint:disable file_length type_body_length

  enum DevelopmentEventFixture {
    static let mitskiGreekID = UUID(uuidString: "E0000000-0000-0000-0000-000000000001")!
    static let bigThiefMasonicID = UUID(uuidString: "E0000000-0000-0000-0000-000000000002")!
    static let vampireWeekendCancelledID = UUID(uuidString: "E0000000-0000-0000-0000-000000000003")!
    static let mitskiMemoryID = UUID(uuidString: "E0000000-0000-0000-0000-000000000004")!
    static let duplicateMitskiID = UUID(uuidString: "E0000000-0000-0000-0000-000000000005")!
    static let emptyUpcomingID = UUID(uuidString: "E0000000-0000-0000-0000-000000000006")!
    static let emptyMemoryID = UUID(uuidString: "E0000000-0000-0000-0000-000000000007")!
  }

  actor DevelopmentEventRepository: EventRepository {
    nonisolated let capabilities = EventRepositoryCapabilities.complete

    private struct StoredEvent: Sendable {
      var summary: CommunityEventSummary
      var attendances: [EventAttendance]
      var comments: [EventComment]
      var postPreviews: [EventPostPreview]
      var invitedProfileIDs: Set<UUID>
    }

    private var events: [UUID: StoredEvent]
    private var nextCreatedEventValue = 100
    private var nextPostValue = 100
    private var preparedPostIDs: [UUID: UUID] = [:]
    private let now: Date

    init(now: Date = .now) {
      self.now = now
      events = Self.makeFixtures(now: now)
    }

    func searchEvents(query: String, viewerID: UUID) async throws -> [CommunityEventSummary] {
      let normalized = CatalogInput.normalizedText(query).lowercased()
      return visibleEvents(viewerID: viewerID)
        .filter { stored in
          normalized.isEmpty
            || stored.summary.title.lowercased().contains(normalized)
            || stored.summary.venueName.lowercased().contains(normalized)
            || stored.summary.areaName.lowercased().contains(normalized)
        }
        .map { refreshedSummary($0, viewerID: viewerID) }
        .sorted(by: Self.eventSort)
    }

    func duplicateCandidates(
      for input: CommunityEventCreationInput,
      viewerID: UUID
    ) async throws -> [CommunityEventSummary] {
      guard let headlinerID = input.artists.first?.id else { return [] }
      let calendar = Calendar(identifier: .gregorian)
      return visibleEvents(viewerID: viewerID)
        .filter { stored in
          guard stored.summary.artists.first(where: \.isHeadliner)?.catalogArtistID == headlinerID else {
            return false
          }
          let matchingLocation = stored.summary.catalogPlaceID == input.place.id
            || stored.summary.catalogAreaID == input.place.areaID
          let dayDistance = abs(
            calendar.dateComponents(
              [.day],
              from: calendar.startOfDay(for: input.eventDate),
              to: calendar.startOfDay(for: stored.summary.eventDate)
            ).day ?? .max
          )
          return matchingLocation && dayDistance <= 2
        }
        .map { refreshedSummary($0, viewerID: viewerID) }
        .sorted { lhs, rhs in
          if lhs.catalogPlaceID == input.place.id, rhs.catalogPlaceID != input.place.id {
            return true
          }
          return lhs.eventDate < rhs.eventDate
        }
        .prefix(5)
        .map(\.self)
    }

    func eventDetail(id: UUID, viewerID: UUID) async throws -> CommunityEventDetail {
      guard let stored = events[id], canView(stored, viewerID: viewerID) else {
        throw CommunityEventError.eventUnavailable
      }
      return detail(from: stored, viewerID: viewerID)
    }

    func plans(viewerID: UUID) async throws -> [CommunityEventSummary] {
      visibleEvents(viewerID: viewerID)
        .filter { stored in
          stored.attendances.contains {
            $0.profile.id == viewerID && ($0.status == .going || $0.status == .went)
          }
        }
        .map { refreshedSummary($0, viewerID: viewerID) }
        .sorted(by: Self.eventSort)
    }

    func activityFeed(viewerID: UUID) async throws -> [EventActivity] {
      guard viewerID == DevelopmentSocialFixture.currentUserID else { return [] }
      let morgan = Self.profile(DevelopmentSocialFixture.morganID)
      let ava = Self.profile(DevelopmentSocialFixture.avaID)
      let upcoming = try summary(id: DevelopmentEventFixture.mitskiGreekID, viewerID: viewerID)
      let memory = try summary(id: DevelopmentEventFixture.mitskiMemoryID, viewerID: viewerID)

      return [
        EventActivity(
          id: Self.uuid(value: 1, prefix: "EA"),
          kind: .markedGoing,
          actor: morgan,
          event: upcoming,
          post: nil,
          occurredAt: now.addingTimeInterval(-3600),
          message: "is going to " + upcoming.headlinerName
        ),
        EventActivity(
          id: Self.uuid(value: 2, prefix: "EA"),
          kind: .postPublished,
          actor: ava,
          event: memory,
          post: events[DevelopmentEventFixture.mitskiMemoryID]?.postPreviews.first,
          occurredAt: now.addingTimeInterval(-86400),
          message: "posted about " + memory.headlinerName
        )
      ]
    }

    func setAttendance(
      eventID: UUID,
      viewerID: UUID,
      status: EventAttendanceStatus?,
      audience: EventAudience
    ) async throws -> CommunityEventDetail {
      guard var stored = events[eventID], canView(stored, viewerID: viewerID) else {
        throw CommunityEventError.eventUnavailable
      }
      if status == .going,
         stored.summary.lifecycle == .cancelled || stored.summary.phase(at: now) == .memories
      {
        throw CommunityEventError.invalidEvent("Going is available only before the concert.")
      }
      if let status, status != .going,
         stored.summary.lifecycle == .cancelled || stored.summary.phase(at: now) != .memories
      {
        throw CommunityEventError.invalidEvent("Went can be confirmed only after the concert.")
      }
      stored.attendances.removeAll(where: { $0.profile.id == viewerID })
      if let status {
        stored.attendances.append(
          EventAttendance(
            profile: Self.profile(viewerID),
            status: status,
            audience: audience,
            updatedAt: now
          )
        )
      }
      stored.summary = refreshedSummary(stored, viewerID: viewerID)
      events[eventID] = stored
      return detail(from: stored, viewerID: viewerID)
    }

    func confirmCancelledPerformance(
      eventID: UUID,
      viewerID: UUID,
      audience: EventAudience
    ) async throws -> CommunityEventDetail {
      guard var stored = events[eventID], canView(stored, viewerID: viewerID) else {
        throw CommunityEventError.eventUnavailable
      }
      guard stored.summary.lifecycle == .cancelled, now >= stored.summary.memoryUnlockAt else {
        throw CommunityEventError.invalidEvent(
          "Confirm a cancelled performance only after its scheduled show time."
        )
      }
      stored.attendances.removeAll(where: { $0.profile.id == viewerID })
      stored.attendances.append(
        EventAttendance(
          profile: Self.profile(viewerID),
          status: .went,
          audience: audience,
          updatedAt: now
        )
      )
      stored.summary = refreshedSummary(stored, viewerID: viewerID)
      events[eventID] = stored
      return detail(from: stored, viewerID: viewerID)
    }

    func addComment(
      eventID: UUID,
      authorID: UUID,
      parentCommentID: UUID?,
      body: String,
      audience: EventAudience
    ) async throws -> EventComment {
      guard var stored = events[eventID], canView(stored, viewerID: authorID) else {
        throw CommunityEventError.eventUnavailable
      }
      let normalized = CatalogInput.normalizedText(body)
      guard !normalized.isEmpty, normalized.count <= 500 else {
        throw CommunityEventError.invalidEvent("Comments must be between 1 and 500 characters.")
      }
      nextPostValue += 1
      let post = EventComment(
        id: Self.uuid(value: nextPostValue, prefix: "EC"),
        parentCommentID: parentCommentID,
        author: Self.profile(authorID),
        body: normalized,
        audience: audience,
        createdAt: now,
        isDeleted: false
      )
      stored.comments.append(post)
      events[eventID] = stored
      return post
    }

    func inviteCandidates(eventID: UUID, viewerID: UUID) async throws -> [EventInviteCandidate] {
      guard let stored = events[eventID], canView(stored, viewerID: viewerID) else {
        throw CommunityEventError.eventUnavailable
      }
      return DevelopmentSocialFixture.profiles
        .filter { $0.relationship == .friends }
        .map { profile in
          EventInviteCandidate(
            profile: profile,
            attendanceStatus: stored.attendances.first(where: { $0.profile.id == profile.id })?.status,
            isAlreadyInvited: stored.invitedProfileIDs.contains(profile.id)
          )
        }
    }

    func sendInvitations(eventID: UUID, senderID: UUID, recipientIDs: [UUID]) async throws {
      guard var stored = events[eventID], canView(stored, viewerID: senderID) else {
        throw CommunityEventError.eventUnavailable
      }
      let friendIDs = Set(DevelopmentSocialFixture.profiles.filter { $0.relationship == .friends }.map(\.id))
      guard Set(recipientIDs).isSubset(of: friendIDs) else {
        throw CommunityEventError.invitationUnavailable
      }
      stored.invitedProfileIDs.formUnion(recipientIDs)
      events[eventID] = stored
    }

    func pendingInvitations(viewerID _: UUID) async throws -> [EventInvitation] {
      []
    }

    func respondToInvitation(
      invitationID _: UUID,
      viewerID _: UUID,
      response _: EventInvitationResponse,
      audience _: EventAudience
    ) async throws {
      throw CommunityEventError.invitationUnavailable
    }

    func savePost(
      eventID: UUID,
      authorID: UUID,
      input: EventPostInput
    ) async throws -> CommunityEventDetail {
      guard var stored = events[eventID], canView(stored, viewerID: authorID) else {
        throw CommunityEventError.eventUnavailable
      }
      let summary = refreshedSummary(stored, viewerID: authorID)
      guard summary.phase(at: now) == .memories
        || (summary.lifecycle == .cancelled && now >= summary.memoryUnlockAt)
      else {
        throw CommunityEventError.invalidEvent("Posts unlock after the concert.")
      }
      guard summary.currentUserAttendance == .went else {
        throw CommunityEventError.invalidEvent("Mark that you went before creating a post.")
      }
      if let score = input.score, !(0 ... 10).contains(score) {
        throw CommunityEventError.invalidEvent("Scores must be between 0 and 10.")
      }
      if let performanceScore = input.performanceScore, !(0 ... 10).contains(performanceScore) {
        throw CommunityEventError.invalidEvent("Performance scores must be between 0 and 10.")
      }
      let note = input.note.flatMap(CatalogInput.optionalNormalizedText)
      if let note, note.count > 4000 {
        throw CommunityEventError.invalidEvent("Post reviews can be up to 4,000 characters.")
      }
      guard input.score != nil || input.performanceScore != nil || note != nil || input.hasReadyPhoto else {
        throw CommunityEventError.invalidEvent("Add a score, review, or photo before sharing your post.")
      }
      let existing = stored.postPreviews.first(where: { $0.author.id == authorID })
      stored.postPreviews.removeAll(where: { $0.author.id == authorID })
      stored.postPreviews.append(
        EventPostPreview(
          id: existing?.id ?? preparedPostIDs[eventID]
            ?? Self.uuid(value: nextCreatedEventValue + 1, prefix: "ED"),
          author: Self.profile(authorID),
          score: input.score,
          performanceScore: input.performanceScore,
          note: note,
          photoCount: max(existing?.photoCount ?? 0, input.hasReadyPhoto ? 1 : 0),
          videoCount: existing?.videoCount ?? 0,
          commentCount: existing?.commentCount ?? 0,
          audience: input.audience,
          publishedAt: now
        )
      )
      nextCreatedEventValue += 1
      stored.summary = refreshedSummary(stored, viewerID: authorID)
      events[eventID] = stored
      return detail(from: stored, viewerID: authorID)
    }

    func preparePhotoPost(
      eventID: UUID,
      authorID: UUID,
      audience _: EventAudience
    ) async throws -> UUID {
      guard let stored = events[eventID], canView(stored, viewerID: authorID) else {
        throw CommunityEventError.eventUnavailable
      }
      if let existing = stored.postPreviews.first(where: { $0.author.id == authorID }) {
        return existing.id
      }
      if let prepared = preparedPostIDs[eventID] {
        return prepared
      }
      nextCreatedEventValue += 1
      let postID = Self.uuid(value: nextCreatedEventValue, prefix: "ED")
      preparedPostIDs[eventID] = postID
      return postID
    }

    func profileHistory(profileID: UUID, viewerID: UUID) async throws -> CommunityProfileHistory {
      var going: [CommunityEventSummary] = []
      var went: [CommunityEventSummary] = []
      var posts: [EventProfilePost] = []
      for stored in visibleEvents(viewerID: viewerID) {
        if let attendance = stored.attendances.first(where: { $0.profile.id == profileID }),
           canRead(attendance: attendance, viewerID: viewerID)
        {
          if attendance.status == .going {
            going.append(refreshedSummary(stored, viewerID: viewerID))
          } else {
            went.append(refreshedSummary(stored, viewerID: viewerID))
          }
        }
        for post in stored.postPreviews where post.author.id == profileID
          && canRead(post: post, viewerID: viewerID)
        {
          posts.append(
            EventProfilePost(
              event: refreshedSummary(stored, viewerID: viewerID),
              post: post
            )
          )
        }
      }
      return CommunityProfileHistory(
        going: going.sorted(by: { $0.eventDate < $1.eventDate }),
        went: went.sorted(by: { $0.eventDate > $1.eventDate }),
        posts: posts.sorted(by: { $0.post.publishedAt > $1.post.publishedAt })
      )
    }

    func createEvent(
      _ input: CommunityEventCreationInput,
      creatorID: UUID
    ) async throws -> CommunityEventDetail {
      guard !input.artists.isEmpty else {
        throw CommunityEventError.invalidEvent("Choose at least one artist.")
      }
      guard let areaID = input.place.areaID, let areaName = input.place.areaName else {
        throw CommunityEventError.invalidEvent("Choose a venue with a city or area.")
      }

      if let duplicate = events.values.first(where: { stored in
        stored.summary.rowState == .active
          && stored.summary.artists.first?.catalogArtistID == input.artists.first?.id
          && stored.summary.catalogPlaceID == input.place.id
          && Calendar(identifier: .gregorian).isDate(stored.summary.eventDate, inSameDayAs: input.eventDate)
      }) {
        throw CommunityEventError.duplicateEvent(duplicate.summary.id)
      }

      nextCreatedEventValue += 1
      let id = Self.uuid(value: nextCreatedEventValue, prefix: "EE")
      let unlockAt = Self.memoryUnlockAt(for: input)
      let artists = input.artists.enumerated().map { index, artist in
        CommunityEventArtist(
          catalogArtistID: artist.id,
          displayName: artist.displayName,
          position: index,
          isHeadliner: index == 0
        )
      }
      let summary = CommunityEventSummary(
        id: id,
        artists: artists,
        cover: nil,
        catalogPlaceID: input.place.id,
        catalogAreaID: areaID,
        catalogTourID: input.tour?.id,
        venueName: input.place.displayName,
        areaName: areaName,
        eventDate: input.eventDate,
        startsAt: input.startsAt,
        timeZoneIdentifier: input.timeZoneIdentifier,
        memoryUnlockAt: unlockAt,
        lifecycle: input.eventDate < now ? .completed : .scheduled,
        listing: input.listing,
        integrity: .communityAdded,
        rowState: .active,
        sourceLabel: "Community made",
        currentUserAttendance: nil,
        currentUserAudience: nil,
        friendPreviews: [],
        publicGoingCount: 0,
        publicWentCount: 0,
        postCount: 0,
        averagePostScore: nil,
        duplicateCandidateEventID: nil
      )
      let stored = StoredEvent(
        summary: summary,
        attendances: [],
        comments: [],
        postPreviews: [],
        invitedProfileIDs: input.listing == .unlisted ? [creatorID] : []
      )
      events[id] = stored
      return detail(from: stored, viewerID: creatorID)
    }

    func setEventCover(
      _ jpegData: Data,
      eventID: UUID,
      creatorID: UUID
    ) async throws -> CommunityEventDetail {
      guard !jpegData.isEmpty, var stored = events[eventID] else {
        throw CommunityEventError.eventUnavailable
      }
      stored.summary = stored.summary.replacingCover(
        CommunityEventCover(
          source: .community,
          objectPath: "event-covers/\(eventID.uuidString.lowercased())/cover.jpg",
          remoteURL: nil,
          providerName: nil,
          attribution: nil,
          sourcePageURL: nil,
          licenseName: nil,
          licenseURL: nil,
          version: (stored.summary.cover?.version ?? 0) + 1
        )
      )
      events[eventID] = stored
      return detail(from: stored, viewerID: creatorID)
    }

    func eventCoverURL(eventID _: UUID, objectPath _: String, version _: Int64) async throws -> URL {
      throw CommunityEventError.featureUnavailable("Development concert cover bytes")
    }

    func reportEvent(
      eventID: UUID,
      reporterID: UUID,
      reason _: EventReportReason,
      note _: String?
    ) async throws {
      guard let stored = events[eventID], canView(stored, viewerID: reporterID) else {
        throw CommunityEventError.eventUnavailable
      }
    }

    private func visibleEvents(viewerID: UUID) -> [StoredEvent] {
      events.values.filter { canView($0, viewerID: viewerID) }
    }

    private func canView(_ stored: StoredEvent, viewerID: UUID) -> Bool {
      guard stored.summary.rowState == .active else { return false }
      if stored.summary.listing == .listed {
        return true
      }
      return stored.attendances.contains(where: { $0.profile.id == viewerID })
        || stored.invitedProfileIDs.contains(viewerID)
    }

    private func summary(id: UUID, viewerID: UUID) throws -> CommunityEventSummary {
      guard let stored = events[id], canView(stored, viewerID: viewerID) else {
        throw CommunityEventError.eventUnavailable
      }
      return refreshedSummary(stored, viewerID: viewerID)
    }

    private func detail(from stored: StoredEvent, viewerID: UUID) -> CommunityEventDetail {
      CommunityEventDetail(
        summary: refreshedSummary(stored, viewerID: viewerID),
        attendances: stored.attendances.filter { attendance in
          canRead(attendance: attendance, viewerID: viewerID)
        },
        comments: stored.comments.filter { $0.author.id == viewerID || $0.audience != .privateOnly },
        postPreviews: stored.postPreviews.filter { canRead(post: $0, viewerID: viewerID) }
      )
    }

    private func canRead(attendance: EventAttendance, viewerID: UUID) -> Bool {
      attendance.profile.id == viewerID
        || attendance.audience == .community
        || (attendance.audience == .friends && attendance.profile.relationship == .friends)
    }

    private func canRead(post: EventPostPreview, viewerID: UUID) -> Bool {
      post.author.id == viewerID
        || post.audience == .community
        || (post.audience == .friends && post.author.relationship == .friends)
    }

    private func refreshedSummary(_ stored: StoredEvent, viewerID: UUID) -> CommunityEventSummary {
      let ownAttendance = stored.attendances.first(where: { $0.profile.id == viewerID })
      let friends = stored.attendances.filter {
        $0.profile.relationship == .friends && $0.profile.id != viewerID && $0.audience != .privateOnly
      }
      let visiblePosts = stored.postPreviews.filter { canRead(post: $0, viewerID: viewerID) }
      let visibleScores = visiblePosts.compactMap(\.score)
      return CommunityEventSummary(
        id: stored.summary.id,
        artists: stored.summary.artists,
        cover: stored.summary.cover,
        catalogPlaceID: stored.summary.catalogPlaceID,
        catalogAreaID: stored.summary.catalogAreaID,
        catalogTourID: stored.summary.catalogTourID,
        venueName: stored.summary.venueName,
        areaName: stored.summary.areaName,
        eventDate: stored.summary.eventDate,
        startsAt: stored.summary.startsAt,
        timeZoneIdentifier: stored.summary.timeZoneIdentifier,
        memoryUnlockAt: stored.summary.memoryUnlockAt,
        lifecycle: stored.summary.lifecycle,
        listing: stored.summary.listing,
        integrity: stored.summary.integrity,
        rowState: stored.summary.rowState,
        sourceLabel: stored.summary.sourceLabel,
        currentUserAttendance: ownAttendance?.status,
        currentUserAudience: ownAttendance?.audience,
        friendPreviews: friends.map { EventFriendPreview(profile: $0.profile, status: $0.status) },
        publicGoingCount: stored.attendances.filter { $0.status == .going && $0.audience == .community }.count,
        publicWentCount: stored.attendances.filter { $0.status == .went && $0.audience == .community }.count,
        postCount: visiblePosts.count,
        averagePostScore: visibleScores.isEmpty
          ? nil
          : visibleScores.reduce(0, +) / Double(visibleScores.count),
        duplicateCandidateEventID: stored.summary.duplicateCandidateEventID
      )
    }

    private static func eventSort(lhs: CommunityEventSummary, rhs: CommunityEventSummary) -> Bool {
      lhs.eventDate < rhs.eventDate
    }

    // swiftlint:disable:next function_body_length
    private static func makeFixtures(now: Date) -> [UUID: StoredEvent] {
      let current = profile(DevelopmentSocialFixture.currentUserID)
      let morgan = profile(DevelopmentSocialFixture.morganID)
      let ava = profile(DevelopmentSocialFixture.avaID)
      let packedFriends = DevelopmentSocialFixture.profiles.filter { $0.relationship == .friends }
      let calendar = Calendar(identifier: .gregorian)
      func fixtureDate(daysFromNow: Int, hour: Int, minute: Int = 30) -> Date {
        let shifted = calendar.date(byAdding: .day, value: daysFromNow, to: now) ?? now
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: shifted) ?? shifted
      }
      let future = fixtureDate(daysFromNow: 18, hour: 19)
      let soon = fixtureDate(daysFromNow: 7, hour: 20)
      let cancelledDate = fixtureDate(daysFromNow: 28, hour: 19)
      let past = fixtureDate(daysFromNow: -45, hour: 20)
      let emptyFuture = fixtureDate(daysFromNow: 42, hour: 19)
      let emptyPast = fixtureDate(daysFromNow: -90, hour: 20)

      let upcoming = baseSummary(
        id: DevelopmentEventFixture.mitskiGreekID,
        artistID: DevelopmentMusicCatalogFixture.mitskiID,
        artist: "Mitski",
        placeID: DevelopmentMusicCatalogFixture.greekTheatreBerkeleyID,
        areaID: DevelopmentMusicCatalogFixture.berkeleyAreaID,
        venue: "The Greek Theatre",
        area: "Berkeley",
        eventDate: future,
        lifecycle: .scheduled,
        listing: .listed,
        duplicateCandidateEventID: DevelopmentEventFixture.duplicateMitskiID
      )
      let unlisted = baseSummary(
        id: DevelopmentEventFixture.bigThiefMasonicID,
        artistID: DevelopmentMusicCatalogFixture.bigThiefID,
        artist: "Big Thief",
        placeID: DevelopmentMusicCatalogFixture.masonicID,
        areaID: DevelopmentMusicCatalogFixture.sanFranciscoAreaID,
        venue: "The Masonic",
        area: "San Francisco",
        eventDate: soon,
        lifecycle: .scheduled,
        listing: .unlisted
      )
      let cancelled = baseSummary(
        id: DevelopmentEventFixture.vampireWeekendCancelledID,
        artistID: DevelopmentMusicCatalogFixture.vampireWeekendID,
        artist: "Vampire Weekend",
        placeID: DevelopmentMusicCatalogFixture.greekTheatreBerkeleyID,
        areaID: DevelopmentMusicCatalogFixture.berkeleyAreaID,
        venue: "The Greek Theatre",
        area: "Berkeley",
        eventDate: cancelledDate,
        lifecycle: .cancelled,
        listing: .listed
      )
      let memory = baseSummary(
        id: DevelopmentEventFixture.mitskiMemoryID,
        artistID: DevelopmentMusicCatalogFixture.mitskiID,
        artist: "Mitski",
        placeID: DevelopmentMusicCatalogFixture.masonicID,
        areaID: DevelopmentMusicCatalogFixture.sanFranciscoAreaID,
        venue: "The Masonic",
        area: "San Francisco",
        eventDate: past,
        lifecycle: .completed,
        listing: .listed
      )
      let emptyUpcoming = baseSummary(
        id: DevelopmentEventFixture.emptyUpcomingID,
        artistID: DevelopmentMusicCatalogFixture.bigThiefID,
        artist: "Big Thief",
        placeID: DevelopmentMusicCatalogFixture.greekTheatreBerkeleyID,
        areaID: DevelopmentMusicCatalogFixture.berkeleyAreaID,
        venue: "The Greek Theatre",
        area: "Berkeley",
        eventDate: emptyFuture,
        lifecycle: .scheduled,
        listing: .listed
      )
      let emptyMemory = baseSummary(
        id: DevelopmentEventFixture.emptyMemoryID,
        artistID: DevelopmentMusicCatalogFixture.vampireWeekendID,
        artist: "Vampire Weekend",
        placeID: DevelopmentMusicCatalogFixture.masonicID,
        areaID: DevelopmentMusicCatalogFixture.sanFranciscoAreaID,
        venue: "The Masonic",
        area: "San Francisco",
        eventDate: emptyPast,
        lifecycle: .completed,
        listing: .listed
      )
      let duplicate = CommunityEventSummary(
        id: DevelopmentEventFixture.duplicateMitskiID,
        artists: upcoming.artists,
        cover: upcoming.cover,
        catalogPlaceID: upcoming.catalogPlaceID,
        catalogAreaID: upcoming.catalogAreaID,
        catalogTourID: nil,
        venueName: upcoming.venueName,
        areaName: upcoming.areaName,
        eventDate: future,
        startsAt: upcoming.startsAt,
        timeZoneIdentifier: upcoming.timeZoneIdentifier,
        memoryUnlockAt: upcoming.memoryUnlockAt,
        lifecycle: .scheduled,
        listing: .unlisted,
        integrity: .disputed,
        rowState: .merged,
        sourceLabel: "Community made",
        currentUserAttendance: nil,
        currentUserAudience: nil,
        friendPreviews: [],
        publicGoingCount: 0,
        publicWentCount: 0,
        postCount: 0,
        averagePostScore: nil,
        duplicateCandidateEventID: DevelopmentEventFixture.mitskiGreekID
      )

      let upcomingAttendance = [
        EventAttendance(profile: current, status: .going, audience: .friends, updatedAt: now)
      ] + packedFriends.enumerated().map { index, friend in
        EventAttendance(
          profile: friend,
          status: .going,
          audience: index.isMultiple(of: 2) ? .friends : .community,
          updatedAt: now.addingTimeInterval(TimeInterval(index * 60))
        )
      }
      let unlistedAttendance = [
        EventAttendance(profile: current, status: .going, audience: .friends, updatedAt: now),
        EventAttendance(profile: morgan, status: .going, audience: .friends, updatedAt: now)
      ]
      let memoryAttendance = [
        EventAttendance(profile: current, status: .went, audience: .friends, updatedAt: past),
        EventAttendance(profile: ava, status: .went, audience: .community, updatedAt: past)
      ] + packedFriends.enumerated().map { index, friend in
        EventAttendance(
          profile: friend,
          status: .went,
          audience: index.isMultiple(of: 2) ? .friends : .community,
          updatedAt: past.addingTimeInterval(TimeInterval(index * 60))
        )
      }
      let packedPostNotes = [
        "The crowd knew every word, even before the first chorus landed.",
        "I keep replaying the lights during the final song.",
        "The set started quietly and just kept getting bigger.",
        "Best sound I have heard in this room all year.",
        "The surprise song completely changed the energy.",
        "A loud, warm, wonderfully messy night.",
        "The encore was worth losing my voice for.",
        "Still thinking about that transition into the closer."
      ]
      let memoryPosts = [
        EventPostPreview(
          id: uuid(value: 1, prefix: "ED"),
          author: ava,
          score: 9.5,
          performanceScore: 9.0,
          note: "The room went completely still for the quiet songs.",
          photoCount: 6,
          videoCount: 1,
          commentCount: 4,
          audience: .community,
          publishedAt: past.addingTimeInterval(10 * 3600)
        ),
        EventPostPreview(
          id: uuid(value: 2, prefix: "ED"),
          author: morgan,
          score: 9.0,
          performanceScore: 9.5,
          note: "A perfect closer and an even better crowd.",
          photoCount: 3,
          videoCount: 0,
          commentCount: 2,
          audience: .friends,
          publishedAt: past.addingTimeInterval(12 * 3600)
        )
      ] + packedFriends.filter { $0.id != DevelopmentSocialFixture.morganID }
        .enumerated()
        .map { index, friend in
          EventPostPreview(
            id: uuid(value: index + 3, prefix: "ED"),
            author: friend,
            score: 8.0 + Double(index % 5) * 0.5,
            performanceScore: 8.5 + Double(index % 4) * 0.5,
            note: packedPostNotes[index],
            photoCount: index % 3 + 1,
            videoCount: index.isMultiple(of: 4) ? 1 : 0,
            commentCount: index + 1,
            audience: index.isMultiple(of: 2) ? .friends : .community,
            publishedAt: past.addingTimeInterval(TimeInterval((index + 13) * 3600))
          )
        }
      let packedPostBodies = [
        "I really hope we get First Love / Late Spring.",
        "Who wants to meet by the north entrance?",
        "The opener's new record is so good live.",
        "Manifesting a surprise song in the encore.",
        "I found a few face-value tickets this morning.",
        "Taking the early train if anyone wants to join.",
        "This will be my first time at the Greek.",
        "Do we think doors are actually at 6:30?",
        "Already building the pre-show playlist."
      ]
      let upcomingPosts = packedFriends.enumerated().map { index, friend in
        EventComment(
          id: uuid(value: index + 1, prefix: "EC"),
          parentCommentID: nil,
          author: friend,
          body: packedPostBodies[index],
          audience: index.isMultiple(of: 2) ? .friends : .community,
          createdAt: now.addingTimeInterval(TimeInterval(-((index + 2) * 1800))),
          isDeleted: false
        )
      } + [
        EventComment(
          id: uuid(value: 20, prefix: "EC"),
          parentCommentID: uuid(value: 2, prefix: "EC"),
          author: morgan,
          body: "Yes, let's make a group chat for the meetup.",
          audience: .friends,
          createdAt: now.addingTimeInterval(-1200),
          isDeleted: false
        ),
        EventComment(
          id: uuid(value: 21, prefix: "EC"),
          parentCommentID: uuid(value: 4, prefix: "EC"),
          author: profile(DevelopmentSocialFixture.miaID),
          body: "I would lose it if that happens.",
          audience: .friends,
          createdAt: now.addingTimeInterval(-900),
          isDeleted: false
        ),
        EventComment(
          id: uuid(value: 22, prefix: "EC"),
          parentCommentID: uuid(value: 8, prefix: "EC"),
          author: profile(DevelopmentSocialFixture.zoeID),
          body: "The venue email says doors at 6:30, music at 7:30.",
          audience: .community,
          createdAt: now.addingTimeInterval(-600),
          isDeleted: false
        )
      ]

      return [
        upcoming.id: StoredEvent(
          summary: upcoming,
          attendances: upcomingAttendance,
          comments: upcomingPosts,
          postPreviews: [],
          invitedProfileIDs: []
        ),
        unlisted.id: StoredEvent(
          summary: unlisted,
          attendances: unlistedAttendance,
          comments: [],
          postPreviews: [],
          invitedProfileIDs: [DevelopmentSocialFixture.currentUserID]
        ),
        cancelled.id: StoredEvent(
          summary: cancelled,
          attendances: [],
          comments: [],
          postPreviews: [],
          invitedProfileIDs: []
        ),
        memory.id: StoredEvent(
          summary: memory,
          attendances: memoryAttendance,
          comments: [],
          postPreviews: memoryPosts,
          invitedProfileIDs: []
        ),
        emptyUpcoming.id: StoredEvent(
          summary: emptyUpcoming,
          attendances: [],
          comments: [],
          postPreviews: [],
          invitedProfileIDs: []
        ),
        emptyMemory.id: StoredEvent(
          summary: emptyMemory,
          attendances: [],
          comments: [],
          postPreviews: [],
          invitedProfileIDs: []
        ),
        duplicate.id: StoredEvent(
          summary: duplicate,
          attendances: [],
          comments: [],
          postPreviews: [],
          invitedProfileIDs: []
        )
      ]
    }

    // swiftlint:disable:next function_parameter_count
    private static func baseSummary(
      id: UUID,
      artistID: UUID,
      artist: String,
      placeID: UUID,
      areaID: UUID,
      venue: String,
      area: String,
      eventDate: Date,
      lifecycle: CommunityEventLifecycle,
      listing: CommunityEventListing,
      duplicateCandidateEventID: UUID? = nil
    ) -> CommunityEventSummary {
      CommunityEventSummary(
        id: id,
        artists: [
          CommunityEventArtist(
            catalogArtistID: artistID,
            displayName: artist,
            position: 0,
            isHeadliner: true
          )
        ],
        cover: nil,
        catalogPlaceID: placeID,
        catalogAreaID: areaID,
        catalogTourID: artist == "Mitski" ? DevelopmentMusicCatalogFixture.landTourID : nil,
        venueName: venue,
        areaName: area,
        eventDate: eventDate,
        startsAt: eventDate,
        timeZoneIdentifier: "America/Los_Angeles",
        memoryUnlockAt: eventDate.addingTimeInterval(4 * 3600),
        lifecycle: lifecycle,
        listing: listing,
        integrity: .communityAdded,
        rowState: .active,
        sourceLabel: "Community made",
        currentUserAttendance: nil,
        currentUserAudience: nil,
        friendPreviews: [],
        publicGoingCount: 0,
        publicWentCount: 0,
        postCount: 0,
        averagePostScore: nil,
        duplicateCandidateEventID: duplicateCandidateEventID
      )
    }

    private static func profile(_ id: UUID) -> SocialProfile {
      if id == DevelopmentSocialFixture.currentUserID {
        return DevelopmentSocialFixture.currentProfile
      }
      return DevelopmentSocialFixture.profiles.first(where: { $0.id == id })
        ?? SocialProfile(
          id: id,
          username: "listener",
          displayName: "Concert listener",
          relationship: .none
        )
    }

    private static func memoryUnlockAt(for input: CommunityEventCreationInput) -> Date {
      if let startsAt = input.startsAt {
        return startsAt.addingTimeInterval(4 * 3600)
      }
      var calendar = Calendar(identifier: .gregorian)
      calendar.timeZone = TimeZone(identifier: input.timeZoneIdentifier) ?? .gmt
      let startOfDay = calendar.startOfDay(for: input.eventDate)
      let nextDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? startOfDay
      return calendar.date(bySettingHour: 3, minute: 0, second: 0, of: nextDay) ?? nextDay
    }

    private static func uuid(value: Int, prefix: String) -> UUID {
      let sanitizedPrefix = String(prefix.prefix(2)).uppercased()
      return UUID(uuidString: "\(sanitizedPrefix)000000-0000-0000-0000-\(String(format: "%012d", value))")!
    }
  }
#endif
