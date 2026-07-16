#if DEBUG
  import Foundation
  import Testing
  @testable import tunedIn

  struct DevelopmentEventRepositoryTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test
    func fixturesCoverDiscoveryAndMemoryStatesWithoutConflatingAttendanceAndDiary() async throws {
      let repository = DevelopmentEventRepository(now: now)
      let viewerID = DevelopmentSocialFixture.currentUserID

      let events = try await repository.searchEvents(query: "", viewerID: viewerID)

      #expect(events.contains(where: { $0.listing == .listed && $0.phase(at: now) == .upcoming }))
      #expect(events.contains(where: { $0.listing == .unlisted }))
      #expect(events.contains(where: { $0.phase(at: now) == .cancelled }))
      let memory = try #require(events.first(where: { $0.phase(at: now) == .memories }))
      #expect(memory.currentUserAttendance == .went)
      #expect(memory.diaryCount == 2)

      let detail = try await repository.eventDetail(id: memory.id, viewerID: viewerID)
      #expect(detail.attendances.contains(where: { $0.profile.id == viewerID && $0.status == .went }))
      #expect(!detail.diaryPreviews.contains(where: { $0.author.id == viewerID }))
      #expect(detail.summary.canCreateDiary(at: now))
    }

    @Test
    func unlistedEventsStayOutOfPublicDiscoveryUnlessViewerHasAccess() async throws {
      let repository = DevelopmentEventRepository(now: now)

      let memberResults = try await repository.searchEvents(
        query: "Big Thief",
        viewerID: DevelopmentSocialFixture.currentUserID
      )
      let publicResults = try await repository.searchEvents(
        query: "Big Thief",
        viewerID: DevelopmentSocialFixture.noaID
      )

      #expect(memberResults.count == 1)
      #expect(publicResults.isEmpty)
    }

    @Test
    func attendanceMutationDoesNotCreateADiary() async throws {
      let repository = DevelopmentEventRepository(now: now)
      let viewerID = DevelopmentSocialFixture.currentUserID
      let eventID = DevelopmentEventFixture.vampireWeekendCancelledID

      let detail = try await repository.setAttendance(
        eventID: eventID,
        viewerID: viewerID,
        status: .going,
        audience: .friends
      )

      #expect(detail.summary.currentUserAttendance == .going)
      #expect(detail.diaryPreviews.isEmpty)
    }

    @Test
    func duplicateCreationReturnsTheCanonicalEventCandidate() async throws {
      let repository = DevelopmentEventRepository(now: now)
      let catalog = DevelopmentMusicCatalogRepository()
      let artist = try #require(await catalog.entity(id: DevelopmentMusicCatalogFixture.mitskiID)?.artist)
      let place = try #require(
        await catalog.entity(id: DevelopmentMusicCatalogFixture.greekTheatreBerkeleyID)?.place
      )
      let existing = try #require(
        await repository.searchEvents(
          query: "Mitski",
          viewerID: DevelopmentSocialFixture.currentUserID
        ).first(where: { $0.phase(at: now) == .upcoming })
      )
      let input = CommunityEventCreationInput(
        artists: [artist],
        place: place,
        tour: nil,
        eventDate: existing.eventDate,
        startsAt: existing.startsAt,
        timeZoneIdentifier: existing.timeZoneIdentifier,
        listing: .listed
      )

      do {
        _ = try await repository.createEvent(input, creatorID: DevelopmentSocialFixture.currentUserID)
        Issue.record("Expected duplicate creation to be rejected")
      } catch let CommunityEventError.duplicateEvent(eventID) {
        #expect(eventID == DevelopmentEventFixture.mitskiGreekID)
      }
    }
  }
#endif
