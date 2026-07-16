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
  }

  actor DevelopmentEventRepository: EventRepository {
    nonisolated let capabilities = EventRepositoryCapabilities.complete

    private struct StoredEvent: Sendable {
      var summary: CommunityEventSummary
      var attendances: [EventAttendance]
      var posts: [EventPost]
      var diaryPreviews: [EventDiaryPreview]
      var invitedProfileIDs: Set<UUID>
    }

    private var events: [UUID: StoredEvent]
    private var nextCreatedEventValue = 100
    private var nextPostValue = 100
    private var preparedDiaryIDs: [UUID: UUID] = [:]
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
          if lhs.catalogPlaceID == input.place.id, rhs.catalogPlaceID != input.place.id { return true }
          return lhs.eventDate < rhs.eventDate
        }
        .prefix(5)
        .map { $0 }
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
          diary: nil,
          occurredAt: now.addingTimeInterval(-3_600),
          message: "is going to " + upcoming.headlinerName
        ),
        EventActivity(
          id: Self.uuid(value: 2, prefix: "EA"),
          kind: .diaryPublished,
          actor: ava,
          event: memory,
          diary: events[DevelopmentEventFixture.mitskiMemoryID]?.diaryPreviews.first,
          occurredAt: now.addingTimeInterval(-86_400),
          message: "shared a memory from " + memory.headlinerName
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
         stored.summary.lifecycle == .cancelled || stored.summary.phase(at: now) == .memories {
        throw CommunityEventError.invalidEvent("Going is available only before the concert.")
      }
      if let status, status != .going,
         stored.summary.lifecycle == .cancelled || stored.summary.phase(at: now) != .memories {
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

    func addPost(
      eventID: UUID,
      authorID: UUID,
      parentPostID: UUID?,
      body: String,
      audience: EventAudience
    ) async throws -> EventPost {
      guard var stored = events[eventID], canView(stored, viewerID: authorID) else {
        throw CommunityEventError.eventUnavailable
      }
      let normalized = CatalogInput.normalizedText(body)
      guard !normalized.isEmpty, normalized.count <= 500 else {
        throw CommunityEventError.invalidEvent("Comments must be between 1 and 500 characters.")
      }
      nextPostValue += 1
      let post = EventPost(
        id: Self.uuid(value: nextPostValue, prefix: "EC"),
        parentPostID: parentPostID,
        author: Self.profile(authorID),
        body: normalized,
        audience: audience,
        createdAt: now,
        isDeleted: false
      )
      stored.posts.append(post)
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

    func saveDiary(
      eventID: UUID,
      authorID: UUID,
      input: EventDiaryInput
    ) async throws -> CommunityEventDetail {
      guard var stored = events[eventID], canView(stored, viewerID: authorID) else {
        throw CommunityEventError.eventUnavailable
      }
      let summary = refreshedSummary(stored, viewerID: authorID)
      guard summary.phase(at: now) == .memories
        || (summary.lifecycle == .cancelled && now >= summary.memoryUnlockAt)
      else {
        throw CommunityEventError.invalidEvent("Diaries unlock after the concert.")
      }
      guard summary.currentUserAttendance == .went else {
        throw CommunityEventError.invalidEvent("Mark that you went before creating a diary.")
      }
      if let score = input.score, !(0 ... 10).contains(score) {
        throw CommunityEventError.invalidEvent("Scores must be between 0 and 10.")
      }
      if let performanceScore = input.performanceScore, !(0 ... 10).contains(performanceScore) {
        throw CommunityEventError.invalidEvent("Performance scores must be between 0 and 10.")
      }
      let note = input.note.flatMap(CatalogInput.optionalNormalizedText)
      if let note, note.count > 4_000 {
        throw CommunityEventError.invalidEvent("Diary notes can be up to 4,000 characters.")
      }
      guard input.score != nil || input.performanceScore != nil || note != nil || input.hasReadyPhoto else {
        throw CommunityEventError.invalidEvent("Add a score, note, or photo before sharing your diary.")
      }
      let existing = stored.diaryPreviews.first(where: { $0.author.id == authorID })
      stored.diaryPreviews.removeAll(where: { $0.author.id == authorID })
      stored.diaryPreviews.append(
        EventDiaryPreview(
          id: existing?.id ?? preparedDiaryIDs[eventID]
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

    func preparePhotoDiary(
      eventID: UUID,
      authorID: UUID,
      audience _: EventAudience
    ) async throws -> UUID {
      guard let stored = events[eventID], canView(stored, viewerID: authorID) else {
        throw CommunityEventError.eventUnavailable
      }
      if let existing = stored.diaryPreviews.first(where: { $0.author.id == authorID }) {
        return existing.id
      }
      if let prepared = preparedDiaryIDs[eventID] { return prepared }
      nextCreatedEventValue += 1
      let diaryID = Self.uuid(value: nextCreatedEventValue, prefix: "ED")
      preparedDiaryIDs[eventID] = diaryID
      return diaryID
    }

    func profileHistory(profileID: UUID, viewerID: UUID) async throws -> CommunityProfileHistory {
      var going: [CommunityEventSummary] = []
      var went: [CommunityEventSummary] = []
      var diaries: [EventProfileDiary] = []
      for stored in visibleEvents(viewerID: viewerID) {
        if let attendance = stored.attendances.first(where: { $0.profile.id == profileID }),
           canRead(attendance: attendance, viewerID: viewerID) {
          if attendance.status == .going {
            going.append(refreshedSummary(stored, viewerID: viewerID))
          } else {
            went.append(refreshedSummary(stored, viewerID: viewerID))
          }
        }
        for diary in stored.diaryPreviews where diary.author.id == profileID
          && canRead(diary: diary, viewerID: viewerID) {
          diaries.append(
            EventProfileDiary(
              event: refreshedSummary(stored, viewerID: viewerID),
              diary: diary
            )
          )
        }
      }
      return CommunityProfileHistory(
        going: going.sorted(by: { $0.eventDate < $1.eventDate }),
        went: went.sorted(by: { $0.eventDate > $1.eventDate }),
        diaries: diaries.sorted(by: { $0.diary.publishedAt > $1.diary.publishedAt })
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
        diaryCount: 0,
        averageDiaryScore: nil,
        duplicateCandidateEventID: nil
      )
      let stored = StoredEvent(
        summary: summary,
        attendances: [],
        posts: [],
        diaryPreviews: [],
        invitedProfileIDs: input.listing == .unlisted ? [creatorID] : []
      )
      events[id] = stored
      return detail(from: stored, viewerID: creatorID)
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
      if stored.summary.listing == .listed { return true }
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
        posts: stored.posts.filter { $0.author.id == viewerID || $0.audience != .privateOnly },
        diaryPreviews: stored.diaryPreviews.filter { canRead(diary: $0, viewerID: viewerID) }
      )
    }

    private func canRead(attendance: EventAttendance, viewerID: UUID) -> Bool {
      attendance.profile.id == viewerID
        || attendance.audience == .community
        || (attendance.audience == .friends && attendance.profile.relationship == .friends)
    }

    private func canRead(diary: EventDiaryPreview, viewerID: UUID) -> Bool {
      diary.author.id == viewerID
        || diary.audience == .community
        || (diary.audience == .friends && diary.author.relationship == .friends)
    }

    private func refreshedSummary(_ stored: StoredEvent, viewerID: UUID) -> CommunityEventSummary {
      let ownAttendance = stored.attendances.first(where: { $0.profile.id == viewerID })
      let friends = stored.attendances.filter {
        $0.profile.relationship == .friends && $0.profile.id != viewerID && $0.audience != .privateOnly
      }
      let visibleDiaries = stored.diaryPreviews.filter { canRead(diary: $0, viewerID: viewerID) }
      let visibleScores = visibleDiaries.compactMap(\.score)
      return CommunityEventSummary(
        id: stored.summary.id,
        artists: stored.summary.artists,
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
        diaryCount: visibleDiaries.count,
        averageDiaryScore: visibleScores.isEmpty
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
      let calendar = Calendar(identifier: .gregorian)
      func fixtureDate(daysFromNow: Int, hour: Int, minute: Int = 30) -> Date {
        let shifted = calendar.date(byAdding: .day, value: daysFromNow, to: now) ?? now
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: shifted) ?? shifted
      }
      let future = fixtureDate(daysFromNow: 18, hour: 19)
      let soon = fixtureDate(daysFromNow: 7, hour: 20)
      let cancelledDate = fixtureDate(daysFromNow: 28, hour: 19)
      let past = fixtureDate(daysFromNow: -45, hour: 20)

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
      let duplicate = CommunityEventSummary(
        id: DevelopmentEventFixture.duplicateMitskiID,
        artists: upcoming.artists,
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
        diaryCount: 0,
        averageDiaryScore: nil,
        duplicateCandidateEventID: DevelopmentEventFixture.mitskiGreekID
      )

      let upcomingAttendance = [
        EventAttendance(profile: current, status: .going, audience: .friends, updatedAt: now),
        EventAttendance(profile: morgan, status: .going, audience: .community, updatedAt: now)
      ]
      let unlistedAttendance = [
        EventAttendance(profile: current, status: .going, audience: .friends, updatedAt: now),
        EventAttendance(profile: morgan, status: .going, audience: .friends, updatedAt: now)
      ]
      let memoryAttendance = [
        EventAttendance(profile: current, status: .went, audience: .friends, updatedAt: past),
        EventAttendance(profile: ava, status: .went, audience: .community, updatedAt: past)
      ]
      let memoryDiaries = [
        EventDiaryPreview(
          id: uuid(value: 1, prefix: "ED"),
          author: ava,
          score: 9.5,
          performanceScore: 9.0,
          note: "The room went completely still for the quiet songs.",
          photoCount: 6,
          videoCount: 1,
          commentCount: 4,
          audience: .community,
          publishedAt: past.addingTimeInterval(10 * 3_600)
        ),
        EventDiaryPreview(
          id: uuid(value: 2, prefix: "ED"),
          author: morgan,
          score: 9.0,
          performanceScore: 9.5,
          note: "A perfect closer and an even better crowd.",
          photoCount: 3,
          videoCount: 0,
          commentCount: 2,
          audience: .friends,
          publishedAt: past.addingTimeInterval(12 * 3_600)
        )
      ]
      let upcomingPosts = [
        EventPost(
          id: uuid(value: 1, prefix: "EC"),
          parentPostID: nil,
          author: morgan,
          body: "I really hope we get First Love / Late Spring.",
          audience: .friends,
          createdAt: now.addingTimeInterval(-7_200),
          isDeleted: false
        )
      ]

      return [
        upcoming.id: StoredEvent(
          summary: upcoming,
          attendances: upcomingAttendance,
          posts: upcomingPosts,
          diaryPreviews: [],
          invitedProfileIDs: []
        ),
        unlisted.id: StoredEvent(
          summary: unlisted,
          attendances: unlistedAttendance,
          posts: [],
          diaryPreviews: [],
          invitedProfileIDs: [DevelopmentSocialFixture.currentUserID]
        ),
        cancelled.id: StoredEvent(
          summary: cancelled,
          attendances: [],
          posts: [],
          diaryPreviews: [],
          invitedProfileIDs: []
        ),
        memory.id: StoredEvent(
          summary: memory,
          attendances: memoryAttendance,
          posts: [],
          diaryPreviews: memoryDiaries,
          invitedProfileIDs: []
        ),
        duplicate.id: StoredEvent(
          summary: duplicate,
          attendances: [],
          posts: [],
          diaryPreviews: [],
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
        catalogPlaceID: placeID,
        catalogAreaID: areaID,
        catalogTourID: artist == "Mitski" ? DevelopmentMusicCatalogFixture.landTourID : nil,
        venueName: venue,
        areaName: area,
        eventDate: eventDate,
        startsAt: eventDate,
        timeZoneIdentifier: "America/Los_Angeles",
        memoryUnlockAt: eventDate.addingTimeInterval(4 * 3_600),
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
        diaryCount: 0,
        averageDiaryScore: nil,
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
        return startsAt.addingTimeInterval(4 * 3_600)
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
