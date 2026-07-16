import Foundation

enum ConcertCatalogPickerTarget: Identifiable, Equatable {
  case artist(UUID)
  case place
  case song(UUID?)
  case tour

  var id: String {
    switch self {
    case let .artist(id): "artist-\(id.uuidString)"
    case .place: "place"
    case let .song(id): "song-\(id?.uuidString ?? "new")"
    case .tour: "tour"
    }
  }
}

@MainActor
struct ConcertDraft: @MainActor Equatable {
  struct Artist: Identifiable, Equatable {
    let id: UUID
    var selection: CatalogArtist?
    var isPrimary: Bool

    var name: String {
      selection?.displayName ?? ""
    }
  }

  struct SetlistItem: Identifiable, Equatable {
    let id: UUID
    var selection: CatalogSong

    var title: String {
      selection.displayName
    }
  }

  var artists = [Artist(id: UUID(), selection: nil, isPrimary: true)]
  var place: CatalogPlace?
  var concertDate = Date()
  var isTourExpanded = false
  var tour: CatalogTour?
  var hasStartTime = false
  var startTime = Date()
  var venueTimeZoneIdentifier = ConcertDraft.defaultTimeZoneIdentifier
  var setlist: [SetlistItem] = []
  var hasAttemptedSave = false

  init() {}

  init(detail: ConcertDetail) {
    artists = detail.artists.map { artist in
      Artist(
        id: artist.id,
        selection: CatalogArtist(
          id: artist.catalogArtistID,
          origin: .legacyImport,
          musicBrainzID: nil,
          displayName: artist.name,
          sortName: nil,
          disambiguation: nil,
          subtitle: nil,
          artistType: nil,
          areaID: nil,
          areaName: nil
        ),
        isPrimary: artist.isPrimary
      )
    }
    if artists.isEmpty {
      artists = [Artist(id: UUID(), selection: nil, isPrimary: true)]
    } else if let primaryIndex = artists.firstIndex(where: \.isPrimary), primaryIndex != 0 {
      artists.insert(artists.remove(at: primaryIndex), at: 0)
    }

    place = CatalogPlace(
      id: detail.concert.catalogPlaceID,
      origin: .legacyImport,
      musicBrainzID: nil,
      displayName: detail.concert.venueName,
      sortName: nil,
      disambiguation: nil,
      subtitle: detail.concert.city,
      placeType: nil,
      address: nil,
      areaID: detail.concert.catalogAreaID,
      areaName: detail.concert.city
    )
    concertDate = Self.date(from: detail.concert.concertDate) ?? Date()
    if let catalogTourID = detail.concert.catalogTourID, let tourName = detail.concert.tour {
      tour = CatalogTour(
        id: catalogTourID,
        origin: .legacyImport,
        musicBrainzID: nil,
        displayName: tourName,
        sortName: nil,
        disambiguation: nil,
        subtitle: nil,
        artistCredit: nil,
        artistIDs: artists.compactMap { $0.selection?.id }
      )
    }
    isTourExpanded = tour != nil
    hasStartTime = detail.concert.startsAt != nil
    startTime = detail.concert.startsAt ?? Date()
    venueTimeZoneIdentifier = detail.concert.venueTimeZone ?? Self.defaultTimeZoneIdentifier
    setlist = detail.setlist.map { item in
      SetlistItem(
        id: item.id,
        selection: CatalogSong(
          id: item.catalogSongID,
          origin: .legacyImport,
          musicBrainzID: nil,
          displayName: item.title,
          sortName: nil,
          disambiguation: nil,
          subtitle: nil,
          artistCredit: nil,
          artistIDs: artists.compactMap { $0.selection?.id },
          firstReleaseDate: nil,
          workMusicBrainzID: nil
        )
      )
    }
  }

  static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.artists == rhs.artists
      && lhs.place == rhs.place
      && lhs.concertDate == rhs.concertDate
      && lhs.tour == rhs.tour
      && lhs.hasStartTime == rhs.hasStartTime
      && (!lhs.hasStartTime || lhs.startTime == rhs.startTime)
      && (!lhs.hasStartTime || lhs.venueTimeZoneIdentifier == rhs.venueTimeZoneIdentifier)
      && lhs.setlist == rhs.setlist
  }

  var venueName: String {
    place?.displayName ?? ""
  }

  var city: String {
    place?.areaName ?? ""
  }

  var tourName: String {
    tour?.displayName ?? ""
  }

  var selectedCatalogArtists: [CatalogArtist] {
    artists.compactMap(\.selection)
  }

  var primaryArtist: CatalogArtist? {
    artists.first(where: \.isPrimary)?.selection
  }

  var hasEnteredContent: Bool {
    artists.contains { $0.selection != nil }
      || place != nil
      || tour != nil
      || hasStartTime
      || !setlist.isEmpty
  }

  var canSave: Bool {
    guard
      !artists.isEmpty,
      artists.count <= 10,
      artists.filter(\.isPrimary).count == 1,
      artists.allSatisfy({ $0.selection != nil }),
      Set(artists.compactMap { $0.selection?.id }).count == artists.count,
      place != nil,
      setlist.count <= 50
    else {
      return false
    }
    return !hasStartTime || TimeZone(identifier: venueTimeZoneIdentifier) != nil
  }

  var creationInput: ConcertCreationInput? {
    guard canSave, let place else { return nil }
    return ConcertCreationInput(
      artists: artists.compactMap { artist in
        artist.selection.map {
          ConcertArtistInput(catalogArtistID: $0.id, isPrimary: artist.isPrimary)
        }
      },
      catalogPlaceID: place.id,
      concertDate: Self.concertDateString(for: concertDate),
      catalogTourID: tour?.id,
      startsAt: hasStartTime ? venueStartDate() : nil,
      venueTimeZone: hasStartTime ? venueTimeZoneIdentifier : nil,
      setlist: setlist.map(\.selection.id)
    )
  }

  func updateInput(
    concertID: UUID,
    expectedVersion: Int64,
    visibility: ConcertVisibility
  ) -> ConcertUpdateInput? {
    guard let input = creationInput else { return nil }
    return ConcertUpdateInput(
      concertID: concertID,
      expectedVersion: expectedVersion,
      artists: input.artists,
      catalogPlaceID: input.catalogPlaceID,
      concertDate: input.concertDate,
      catalogTourID: input.catalogTourID,
      startsAt: input.startsAt,
      venueTimeZone: input.venueTimeZone,
      setlist: input.setlist,
      visibility: visibility
    )
  }

  mutating func setArtist(_ artist: CatalogArtist, for id: UUID) {
    guard !artists.contains(where: { $0.id != id && $0.selection?.id == artist.id }) else { return }
    guard let index = artists.firstIndex(where: { $0.id == id }) else { return }
    artists[index].selection = artist
  }

  mutating func addArtist(_ artist: CatalogArtist) {
    guard artists.count < 10, !artists.contains(where: { $0.selection?.id == artist.id }) else { return }
    if artists.count == 1, artists[0].selection == nil {
      artists[0].selection = artist
    } else {
      artists.append(Artist(id: UUID(), selection: artist, isPrimary: false))
    }
  }

  mutating func makePrimary(_ id: UUID) {
    guard let selectedIndex = artists.firstIndex(where: { $0.id == id }) else { return }
    var selectedArtist = artists.remove(at: selectedIndex)
    selectedArtist.isPrimary = true
    artists = artists.map { artist in
      var artist = artist
      artist.isPrimary = false
      return artist
    }
    artists.insert(selectedArtist, at: 0)
  }

  mutating func removeArtist(_ id: UUID) {
    guard artists.count > 1, let index = artists.firstIndex(where: { $0.id == id }) else { return }
    let removedPrimary = artists[index].isPrimary
    artists.remove(at: index)
    if removedPrimary, let firstIndex = artists.indices.first {
      artists[firstIndex].isPrimary = true
    }
  }

  mutating func moveArtists(from source: IndexSet, to destination: Int) {
    artists.move(fromOffsets: source, toOffset: destination)
    if let primaryIndex = artists.firstIndex(where: \.isPrimary), primaryIndex != 0 {
      artists.insert(artists.remove(at: primaryIndex), at: 0)
    }
  }

  mutating func addSetlistItem(_ song: CatalogSong) {
    guard setlist.count < 50 else { return }
    setlist.append(SetlistItem(id: UUID(), selection: song))
  }

  mutating func replaceSetlistItem(_ id: UUID, with song: CatalogSong) {
    guard let index = setlist.firstIndex(where: { $0.id == id }) else { return }
    setlist[index].selection = song
  }

  mutating func removeSetlistItem(_ id: UUID) {
    setlist.removeAll { $0.id == id }
  }

  mutating func moveSetlist(from source: IndexSet, to destination: Int) {
    setlist.move(fromOffsets: source, toOffset: destination)
  }

  private func venueStartDate() -> Date? {
    guard let timeZone = TimeZone(identifier: venueTimeZoneIdentifier) else { return nil }
    let dayComponents = Calendar.current.dateComponents([.year, .month, .day], from: concertDate)
    let timeComponents = Calendar.current.dateComponents([.hour, .minute], from: startTime)
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    return calendar.date(
      from: DateComponents(
        timeZone: timeZone,
        year: dayComponents.year,
        month: dayComponents.month,
        day: dayComponents.day,
        hour: timeComponents.hour,
        minute: timeComponents.minute
      )
    )
  }

  /// A concert date is a venue-local calendar day, not an instant in UTC.
  static func concertDateString(for date: Date, timeZone: TimeZone = .current) -> String {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = timeZone
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter.string(from: date)
  }

  static func date(from value: String, timeZone: TimeZone = .current) -> Date? {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = timeZone
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter.date(from: value)
  }

  private static let defaultTimeZoneIdentifier: String = {
    let identifier = TimeZone.current.identifier
    return identifier == "GMT" ? "UTC" : identifier
  }()
}
