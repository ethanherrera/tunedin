#if DEBUG
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
          artists: [ConcertArtistInput(name: "Mitski", isPrimary: true)],
          venueName: "The Greek Theatre",
          concertDate: "2025-09-18",
          city: "Berkeley",
          tour: "The Land Is Inhospitable Tour",
          startsAt: nil,
          venueTimeZone: nil,
          setlist: ["First Love / Late Spring", "My Love Mine All Mine", "Heaven"],
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
          artists: [ConcertArtistInput(name: "Mitski", isPrimary: true)],
          venueName: "The Greek Theatre",
          concertDate: "2025-09-18",
          city: "Berkeley",
          tour: "The Land Is Inhospitable Tour",
          startsAt: nil,
          venueTimeZone: nil,
          setlist: ["First Love / Late Spring", "My Love Mine All Mine", "I Bet on Losing Dogs"],
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
  }
#endif
