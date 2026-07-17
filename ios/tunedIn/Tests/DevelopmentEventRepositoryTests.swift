#if DEBUG
  import Foundation
  import Testing
  @testable import tunedIn

  struct DevelopmentEventRepositoryTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test
    func fixturesCoverDiscoveryAndMemoryStatesWithoutConflatingAttendanceAndPost() async throws {
      let repository = DevelopmentEventRepository(now: now)
      let viewerID = DevelopmentSocialFixture.currentUserID

      let events = try await repository.searchEvents(query: "", viewerID: viewerID)

      #expect(events.contains(where: { $0.listing == .listed && $0.phase(at: now) == .upcoming }))
      #expect(events.contains(where: { $0.listing == .unlisted }))
      #expect(events.contains(where: { $0.phase(at: now) == .cancelled }))
      let memory = try #require(events.first(where: { $0.id == DevelopmentEventFixture.mitskiMemoryID }))
      #expect(memory.currentUserAttendance == .went)
      #expect(memory.postCount == 10)
      #expect(memory.averagePostScore == 8.9)

      let detail = try await repository.eventDetail(id: memory.id, viewerID: viewerID)
      #expect(detail.attendances.contains(where: { $0.profile.id == viewerID && $0.status == .went }))
      #expect(!detail.postPreviews.contains(where: { $0.author.id == viewerID }))
      #expect(detail.summary.canCreatePost(at: now))
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

      #expect(memberResults.contains(where: { $0.id == DevelopmentEventFixture.bigThiefMasonicID }))
      #expect(!publicResults.contains(where: { $0.id == DevelopmentEventFixture.bigThiefMasonicID }))
    }

    @Test
    func fixturesIncludePurposefullyEmptyAndPackedConcerts() async throws {
      let repository = DevelopmentEventRepository(now: now)
      let viewerID = DevelopmentSocialFixture.currentUserID

      let packedUpcoming = try await repository.eventDetail(
        id: DevelopmentEventFixture.mitskiGreekID,
        viewerID: viewerID
      )
      let packedMemory = try await repository.eventDetail(
        id: DevelopmentEventFixture.mitskiMemoryID,
        viewerID: viewerID
      )
      let emptyUpcoming = try await repository.eventDetail(
        id: DevelopmentEventFixture.emptyUpcomingID,
        viewerID: viewerID
      )
      let emptyMemory = try await repository.eventDetail(
        id: DevelopmentEventFixture.emptyMemoryID,
        viewerID: viewerID
      )

      #expect(packedUpcoming.attendances.count == 10)
      #expect(packedUpcoming.posts.count == 12)
      #expect(packedMemory.attendances.count == 11)
      #expect(packedMemory.postPreviews.count == 10)
      #expect(emptyUpcoming.attendances.isEmpty)
      #expect(emptyUpcoming.posts.isEmpty)
      #expect(emptyMemory.attendances.isEmpty)
      #expect(emptyMemory.postPreviews.isEmpty)
    }

    @Test
    func packedConcertCollectionsPageWithoutDuplicates() async throws {
      let repository = DevelopmentEventRepository(now: now)
      let viewerID = DevelopmentSocialFixture.currentUserID

      let firstPosts = try await repository.eventPosts(
        eventID: DevelopmentEventFixture.mitskiMemoryID,
        viewerID: viewerID,
        cursor: nil,
        limit: 4
      )
      let secondPosts = try await repository.eventPosts(
        eventID: DevelopmentEventFixture.mitskiMemoryID,
        viewerID: viewerID,
        cursor: firstPosts.nextCursor,
        limit: 4
      )
      let firstPeople = try await repository.eventAttendances(
        eventID: DevelopmentEventFixture.mitskiMemoryID,
        viewerID: viewerID,
        cursor: nil,
        limit: 6
      )
      let secondPeople = try await repository.eventAttendances(
        eventID: DevelopmentEventFixture.mitskiMemoryID,
        viewerID: viewerID,
        cursor: firstPeople.nextCursor,
        limit: 6
      )

      #expect(firstPosts.items.count == 4)
      #expect(secondPosts.items.count == 4)
      #expect(Set(firstPosts.items.map(\.id)).isDisjoint(with: secondPosts.items.map(\.id)))
      #expect(firstPeople.items.count == 6)
      #expect(secondPeople.items.count == 5)
      #expect(Set(firstPeople.items.map(\.id)).isDisjoint(with: secondPeople.items.map(\.id)))
      #expect(secondPeople.nextCursor == nil)
    }

    @Test
    func attendanceMutationDoesNotCreateAPost() async throws {
      let repository = DevelopmentEventRepository(now: now)
      let viewerID = DevelopmentSocialFixture.currentUserID
      let eventID = DevelopmentEventFixture.mitskiGreekID

      let detail = try await repository.setAttendance(
        eventID: eventID,
        viewerID: viewerID,
        status: .going,
        audience: .friends
      )

      #expect(detail.summary.currentUserAttendance == .going)
      #expect(detail.postPreviews.isEmpty)
    }

    @Test
    func wentAttendanceCanCreateAPersonalPostWithItsOwnAudience() async throws {
      let repository = DevelopmentEventRepository(now: now)
      let viewerID = DevelopmentSocialFixture.currentUserID

      let detail = try await repository.savePost(
        eventID: DevelopmentEventFixture.mitskiMemoryID,
        authorID: viewerID,
        input: EventPostInput(
          score: 9.5,
          performanceScore: 9.0,
          note: "A night I want to remember.",
          audience: .privateOnly
        )
      )

      let post = try #require(detail.postPreviews.first(where: { $0.author.id == viewerID }))
      #expect(post.score == 9.5)
      #expect(post.performanceScore == 9.0)
      #expect(post.audience == .privateOnly)
      #expect(detail.summary.currentUserAttendance == .went)
    }

    @Test
    func duplicateCreationReturnsTheCanonicalEventCandidate() async throws {
      let repository = DevelopmentEventRepository(now: now)
      let catalog = DevelopmentMusicCatalogRepository()
      let artistEntity = try #require(await catalog.entity(id: DevelopmentMusicCatalogFixture.mitskiID))
      let placeEntity = try #require(
        await catalog.entity(id: DevelopmentMusicCatalogFixture.greekTheatreBerkeleyID)
      )
      guard case let .artist(artist) = artistEntity else {
        Issue.record("Expected the fixture to resolve to an artist")
        return
      }
      guard case let .place(place) = placeEntity else {
        Issue.record("Expected the fixture to resolve to a place")
        return
      }
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

      let candidates = try await repository.duplicateCandidates(
        for: input,
        viewerID: DevelopmentSocialFixture.currentUserID
      )
      #expect(candidates.first?.id == DevelopmentEventFixture.mitskiGreekID)

      do {
        _ = try await repository.createEvent(input, creatorID: DevelopmentSocialFixture.currentUserID)
        Issue.record("Expected duplicate creation to be rejected")
      } catch let CommunityEventError.duplicateEvent(eventID) {
        #expect(eventID == DevelopmentEventFixture.mitskiGreekID)
      }
    }

    @Test
    func creatingAnEventDoesNotCreateAttendanceAndUsesFourHourUnlock() async throws {
      let repository = DevelopmentEventRepository(now: now)
      let catalog = DevelopmentMusicCatalogRepository()
      let artistEntity = try #require(
        await catalog.entity(id: DevelopmentMusicCatalogFixture.vampireWeekendID)
      )
      let placeEntity = try #require(
        await catalog.entity(id: DevelopmentMusicCatalogFixture.masonicID)
      )
      guard case let .artist(artist) = artistEntity,
            case let .place(place) = placeEntity
      else {
        Issue.record("Expected resolved catalog fixtures")
        return
      }
      let startsAt = now.addingTimeInterval(60 * 86400)
      let detail = try await repository.createEvent(
        CommunityEventCreationInput(
          artists: [artist],
          place: place,
          tour: nil,
          eventDate: startsAt,
          startsAt: startsAt,
          timeZoneIdentifier: "America/Los_Angeles",
          listing: .listed
        ),
        creatorID: DevelopmentSocialFixture.currentUserID
      )

      #expect(detail.summary.currentUserAttendance == nil)
      #expect(detail.attendances.isEmpty)
      #expect(detail.summary.memoryUnlockAt == startsAt.addingTimeInterval(4 * 3600))
    }

    @Test
    func aReadyPhotoCanBeTheOnlyPostContent() async throws {
      let repository = DevelopmentEventRepository(now: now)
      let viewerID = DevelopmentSocialFixture.currentUserID
      let postID = try await repository.preparePhotoPost(
        eventID: DevelopmentEventFixture.mitskiMemoryID,
        authorID: viewerID,
        audience: .friends
      )
      let detail = try await repository.savePost(
        eventID: DevelopmentEventFixture.mitskiMemoryID,
        authorID: viewerID,
        input: EventPostInput(
          score: nil,
          performanceScore: nil,
          note: nil,
          audience: .friends,
          hasReadyPhoto: true
        )
      )

      let post = try #require(detail.postPreviews.first(where: { $0.id == postID }))
      #expect(post.photoCount == 1)
      #expect(post.score == nil)
      #expect(post.note == nil)
    }
  }
#endif
