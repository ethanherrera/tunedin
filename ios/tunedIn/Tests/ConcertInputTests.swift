import Testing
@testable import tunedIn

struct ConcertInputTests {
  @Test
  func textNormalizesBeforeValidationAndRejectsControlCharacters() {
    #expect(ConcertInput.normalizedText("  The   National  ") == "The National")
    #expect(ConcertInput.isValidRequiredText("  Greek   Theatre ", maximumLength: 160))
    #expect(!ConcertInput.isValidRequiredText("\n", maximumLength: 160))
    #expect(!ConcertInput.isValidOptionalText("Los\u{0007} Angeles", maximumLength: 100))
  }
}

@MainActor
struct ConcertDraftTests {
  @Test
  func validDraftCreatesNormalizedPrivateConcertInput() throws {
    var draft = ConcertDraft()
    draft.artists[0].name = "  Big   Thief "
    draft.venueName = "  Greek   Theatre "
    draft.city = " Los   Angeles "
    draft.tour = "  Somersault  Slide  "
    draft.addSetlistItem()
    draft.setlist[0].title = "  Not  "

    let input = try #require(draft.creationInput)

    #expect(input.artists == [ConcertArtistInput(name: "Big Thief", isPrimary: true)])
    #expect(input.venueName == "Greek Theatre")
    #expect(input.city == "Los Angeles")
    #expect(input.tour == "Somersault Slide")
    #expect(input.setlist == ["Not"])
  }

  @Test
  func draftEnforcesArtistAndSetlistLimits() {
    var draft = ConcertDraft()

    for _ in 0 ..< 12 {
      draft.addArtist()
    }
    for _ in 0 ..< 52 {
      draft.addSetlistItem()
    }

    #expect(draft.artists.count == 10)
    #expect(draft.artists.filter(\.isPrimary).count == 1)
    #expect(draft.setlist.count == 50)
  }
}
