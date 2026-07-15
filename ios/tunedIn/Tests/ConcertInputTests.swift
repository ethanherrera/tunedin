import Foundation
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

  @Test
  func encodedV2CreatePayloadContainsOnlyCatalogIdentityForCatalogFields() throws {
    let artistID = try #require(UUID(uuidString: "10000000-0000-0000-0000-000000000001"))
    let placeID = try #require(UUID(uuidString: "20000000-0000-0000-0000-000000000001"))
    let songID = try #require(UUID(uuidString: "30000000-0000-0000-0000-000000000001"))
    let parameters = CreatePrivateConcertParameters(
      input: ConcertCreationInput(
        artists: [ConcertArtistInput(catalogArtistID: artistID, isPrimary: true)],
        catalogPlaceID: placeID,
        concertDate: "2026-07-15",
        catalogTourID: nil,
        startsAt: nil,
        venueTimeZone: nil,
        setlist: [songID]
      )
    )

    let data = try JSONEncoder().encode(parameters)
    let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    let artists = try #require(object["p_artists"] as? [[String: Any]])
    let setlist = try #require(object["p_setlist"] as? [[String: Any]])

    // Synthesized Encodable omits every nil optional RPC parameter.
    #expect(Set(object.keys) == [
      "p_artists", "p_catalog_place_id", "p_concert_date", "p_setlist"
    ])
    #expect(try Set(#require(artists.first).keys) == ["catalog_artist_id", "is_primary"])
    #expect(try Set(#require(setlist.first).keys) == ["catalog_song_id"])
    let payload = try #require(String(data: data, encoding: .utf8))
    #expect(!payload.contains("venue_name"))
    #expect(!payload.contains("artist_name"))
    #expect(!payload.contains("song_title"))
  }
}

@MainActor
struct ConcertDraftTests {
  @Test
  func validDraftCreatesIdentityOnlyPrivateConcertInput() throws {
    var draft = ConcertDraft()
    draft.setArtist(Self.artist(id: 1, name: "Big Thief"), for: draft.artists[0].id)
    draft.place = Self.place
    draft.tour = Self.tour
    draft.addSetlistItem(Self.song(id: 1, name: "Not"))

    let input = try #require(draft.creationInput)

    #expect(input.artists == [ConcertArtistInput(catalogArtistID: Self.id(1), isPrimary: true)])
    #expect(input.catalogPlaceID == Self.id(20))
    #expect(input.catalogTourID == Self.id(30))
    #expect(input.setlist == [Self.id(41)])
    #expect(draft.city == "Los Angeles")
  }

  @Test
  func draftCannotSaveWithoutResolvedArtistAndPlace() {
    var draft = ConcertDraft()
    #expect(!draft.canSave)

    draft.setArtist(Self.artist(id: 1, name: "Big Thief"), for: draft.artists[0].id)
    #expect(!draft.canSave)

    draft.place = Self.place
    #expect(draft.canSave)
  }

  @Test
  func draftEnforcesArtistAndSetlistLimits() {
    var draft = ConcertDraft()
    draft.setArtist(Self.artist(id: 1, name: "Headliner"), for: draft.artists[0].id)
    for index in 2 ... 14 {
      draft.addArtist(Self.artist(id: index, name: "Artist \(index)"))
    }
    for index in 1 ... 52 {
      draft.addSetlistItem(Self.song(id: index, name: "Song \(index)"))
    }

    #expect(draft.artists.count == 10)
    #expect(draft.artists.filter(\.isPrimary).count == 1)
    #expect(draft.setlist.count == 50)
  }

  @Test
  func choosingAnotherHeadlinerPreservesCatalogIdentity() {
    var draft = ConcertDraft()
    draft.setArtist(Self.artist(id: 1, name: "Big Thief"), for: draft.artists[0].id)
    draft.addArtist(Self.artist(id: 2, name: "Buck Meek"))

    draft.makePrimary(draft.artists[1].id)

    #expect(draft.artists.map { $0.selection?.id } == [Self.id(2), Self.id(1)])
    #expect(draft.artists.map(\.isPrimary) == [true, false])
  }

  @Test
  func lineupReorderingKeepsHeadlinerAtTheFirstEditablePosition() {
    var draft = ConcertDraft()
    draft.setArtist(Self.artist(id: 1, name: "Headliner"), for: draft.artists[0].id)
    draft.addArtist(Self.artist(id: 2, name: "Support One"))
    draft.addArtist(Self.artist(id: 3, name: "Support Two"))

    draft.moveArtists(from: IndexSet(integer: 0), to: 3)
    #expect(draft.artists.first?.selection?.id == Self.id(1))
    #expect(draft.artists.first?.isPrimary == true)

    draft.moveArtists(from: IndexSet(integer: 2), to: 0)
    #expect(draft.artists.first?.selection?.id == Self.id(1))
    #expect(draft.artists.map { $0.selection?.id } == [Self.id(1), Self.id(3), Self.id(2)])
  }

  @Test
  func draftRejectsDuplicateArtistCatalogIdentity() {
    var draft = ConcertDraft()
    let artist = Self.artist(id: 1, name: "Big Thief")
    draft.setArtist(artist, for: draft.artists[0].id)

    draft.addArtist(artist)
    #expect(draft.artists.count == 1)

    draft.addArtist(Self.artist(id: 2, name: "Buck Meek"))
    draft.setArtist(artist, for: draft.artists[1].id)
    #expect(draft.artists.compactMap(\.selection?.id) == [Self.id(1), Self.id(2)])
    #expect(draft.canSave == false)

    draft.place = Self.place
    #expect(draft.canSave)
  }

  @Test
  func movingSetlistKeepsCatalogIdentityAtItsNewPosition() {
    var draft = ConcertDraft()
    for index in 1 ... 3 {
      draft.addSetlistItem(Self.song(id: index, name: "Song \(index)"))
    }

    draft.moveSetlist(from: IndexSet(integer: 2), to: 0)

    #expect(draft.setlist.map(\.selection.id) == [Self.id(43), Self.id(41), Self.id(42)])
  }

  @Test
  func venueLocalDateRoundTripsForWestOfUTCEditors() throws {
    let pacific = try #require(TimeZone(identifier: "America/Los_Angeles"))
    let date = try #require(ConcertDraft.date(from: "2026-07-10", timeZone: pacific))

    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = pacific
    #expect(calendar.dateComponents([.year, .month, .day], from: date) == DateComponents(year: 2026, month: 7, day: 10))
    #expect(ConcertDraft.concertDateString(for: date, timeZone: pacific) == "2026-07-10")
    #expect(ConcertDisplay.day(from: "2026-07-10") == "10")
  }

  private static var place: CatalogPlace {
    CatalogPlace(
      id: id(20), origin: .musicBrainz, musicBrainzID: id(120),
      displayName: "Greek Theatre", sortName: nil, disambiguation: nil,
      subtitle: "Los Angeles", placeType: "Amphitheatre", address: nil,
      areaID: id(21), areaName: "Los Angeles"
    )
  }

  private static var tour: CatalogTour {
    CatalogTour(
      id: id(30), origin: .musicBrainz, musicBrainzID: id(130),
      displayName: "Somersault Slide", sortName: nil, disambiguation: nil,
      subtitle: "Big Thief", artistCredit: "Big Thief", artistIDs: [id(1)]
    )
  }

  private static func artist(id value: Int, name: String) -> CatalogArtist {
    CatalogArtist(
      id: id(value), origin: .musicBrainz, musicBrainzID: id(100 + value),
      displayName: name, sortName: name, disambiguation: nil,
      subtitle: nil, artistType: "Group", areaID: nil, areaName: nil
    )
  }

  private static func song(id value: Int, name: String) -> CatalogSong {
    CatalogSong(
      id: id(40 + value), origin: .musicBrainz, musicBrainzID: id(140 + value),
      displayName: name, sortName: nil, disambiguation: nil,
      subtitle: "Big Thief", artistCredit: "Big Thief", artistIDs: [id(1)],
      firstReleaseDate: nil, workMusicBrainzID: nil
    )
  }

  private static func id(_ value: Int) -> UUID {
    UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", value))!
  }
}
