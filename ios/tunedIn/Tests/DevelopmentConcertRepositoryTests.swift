#if DEBUG
  import Foundation
  import Testing
  @testable import tunedIn

  struct DevelopmentConcertRepositoryTests {
    @Test
    func collaborationAndNotesAdvanceTheFixtureConcert() async throws {
      let repository = DevelopmentConcertRepository()
      let archive = try await repository.profileConcertHistory(
        profileID: DevelopmentSocialFixture.currentUserID,
        query: ConcertHistoryQuery(),
        cursor: nil
      )
      let mitski = try #require(archive.first(where: { $0.primaryArtistName == "Mitski" }))
      let original = try await repository.fetchConcertDetail(
        id: mitski.id,
        viewerID: DevelopmentSocialFixture.currentUserID
      )

      let tagged = try await repository.tagCollaborator(
        concertID: original.concert.id,
        profileID: DevelopmentSocialFixture.avaID,
        expectedVersion: original.concert.version
      )
      #expect(tagged.version == original.concert.version + 1)

      let afterTag = try await repository.fetchConcertDetail(
        id: original.concert.id,
        viewerID: DevelopmentSocialFixture.currentUserID
      )
      #expect(afterTag.collaborators.contains(where: { $0.id == DevelopmentSocialFixture.avaID }))

      let note = try await repository.createComment(
        concertID: original.concert.id,
        body: "  That encore landed perfectly. "
      )
      #expect(note.body == "That encore landed perfectly.")

      let updatedNote = try await repository.updateComment(
        commentID: note.id,
        body: "That encore really landed."
      )
      #expect(updatedNote.body == "That encore really landed.")

      let updatedConcert = try await repository.updateConcert(
        ConcertUpdateInput(
          concertID: original.concert.id,
          expectedVersion: afterTag.concert.version,
          artists: original.artists.map {
            ConcertArtistInput(catalogArtistID: $0.catalogArtistID, isPrimary: $0.isPrimary)
          },
          catalogPlaceID: original.concert.catalogPlaceID,
          concertDate: "2025-09-18",
          catalogTourID: original.concert.catalogTourID,
          startsAt: nil,
          venueTimeZone: nil,
          setlist: Array(original.setlist.prefix(2).map(\.catalogSongID)) + [DevelopmentMusicCatalogFixture.heavenID],
          visibility: .friends
        )
      )
      #expect(updatedConcert.version == afterTag.concert.version + 1)

      let finalDetail = try await repository.fetchConcertDetail(
        id: original.concert.id,
        viewerID: DevelopmentSocialFixture.currentUserID
      )
      #expect(finalDetail.setlist.map(\.title).last == "Heaven")
      #expect(finalDetail.history.contains(where: { $0.kind == .setlistUpdated }))
      #expect(finalDetail.history.contains(where: { $0.kind == .commentUpdated }))
    }

    @Test
    func ownerCanMakeASharedConcertPrivateAndRevokeEditors() async throws {
      let repository = DevelopmentConcertRepository()
      let archive = try await repository.profileConcertHistory(
        profileID: DevelopmentSocialFixture.currentUserID,
        query: ConcertHistoryQuery(),
        cursor: nil
      )
      let mitski = try #require(archive.first(where: { $0.primaryArtistName == "Mitski" }))
      let original = try await repository.fetchConcertDetail(
        id: mitski.id,
        viewerID: DevelopmentSocialFixture.currentUserID
      )

      let privateConcert = try await repository.updateConcert(
        ConcertUpdateInput(
          concertID: original.concert.id,
          expectedVersion: original.concert.version,
          artists: original.artists.map {
            ConcertArtistInput(catalogArtistID: $0.catalogArtistID, isPrimary: $0.isPrimary)
          },
          catalogPlaceID: original.concert.catalogPlaceID,
          concertDate: "2025-09-18",
          catalogTourID: original.concert.catalogTourID,
          startsAt: nil,
          venueTimeZone: nil,
          setlist: original.setlist.map(\.catalogSongID),
          visibility: .private
        )
      )
      #expect(privateConcert.visibility == .private)

      let finalDetail = try await repository.fetchConcertDetail(
        id: original.concert.id,
        viewerID: DevelopmentSocialFixture.currentUserID
      )
      #expect(finalDetail.collaborators.isEmpty)
    }

    @Test
    func archiveAppliesYearAndEverySupportedSort() async throws {
      let repository = DevelopmentConcertRepository()

      let newest = try await repository.profileConcertHistory(
        profileID: DevelopmentSocialFixture.currentUserID,
        query: ConcertHistoryQuery(sort: .newest),
        cursor: nil
      )
      #expect(newest.map(\.primaryArtistName) == ["Mitski", "Vampire Weekend"])

      let oldest = try await repository.profileConcertHistory(
        profileID: DevelopmentSocialFixture.currentUserID,
        query: ConcertHistoryQuery(sort: .oldest),
        cursor: nil
      )
      #expect(oldest.map(\.primaryArtistName) == ["Vampire Weekend", "Mitski"])

      let recentlyUpdated = try await repository.profileConcertHistory(
        profileID: DevelopmentSocialFixture.currentUserID,
        query: ConcertHistoryQuery(sort: .recentlyUpdated),
        cursor: nil
      )
      #expect(recentlyUpdated.map(\.primaryArtistName) == ["Mitski", "Vampire Weekend"])

      let artist = try await repository.profileConcertHistory(
        profileID: DevelopmentSocialFixture.currentUserID,
        query: ConcertHistoryQuery(sort: .artist),
        cursor: nil
      )
      #expect(artist.map(\.primaryArtistName) == ["Mitski", "Vampire Weekend"])

      let venue = try await repository.profileConcertHistory(
        profileID: DevelopmentSocialFixture.currentUserID,
        query: ConcertHistoryQuery(sort: .venue),
        cursor: nil
      )
      #expect(venue.map(\.concert.venueName) == ["The Greek Theatre", "The Masonic"])

      let year = try await repository.profileConcertHistory(
        profileID: DevelopmentSocialFixture.currentUserID,
        query: ConcertHistoryQuery(year: 2024),
        cursor: nil
      )
      #expect(year.isEmpty)
    }

    @Test
    func communityDiaryFixturesReuseAlbumAndCommentInfrastructure() async throws {
      let repository = DevelopmentConcertRepository()
      let diaryID = try #require(UUID(uuidString: "ED000000-0000-0000-0000-000000000001"))
      let photoID = UUID()

      let reservation = try await repository.reserveAlbumPhoto(concertID: diaryID, photoID: photoID)
      #expect(reservation.concertID == diaryID)
      #expect(try await repository.comments(concertID: diaryID, cursor: nil).isEmpty)

      let comment = try await repository.createComment(concertID: diaryID, body: "Fixture memory comment")
      #expect(comment.concertID == diaryID)
      #expect(try await repository.comments(concertID: diaryID, cursor: nil).map(\.id) == [comment.id])
    }
  }
#endif
