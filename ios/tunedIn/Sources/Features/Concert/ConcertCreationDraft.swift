import Foundation

@MainActor
struct ConcertDraft {
  struct Artist: Identifiable, Equatable {
    let id: UUID
    var name: String
    var isPrimary: Bool
  }

  struct SetlistItem: Identifiable, Equatable {
    let id: UUID
    var title: String
  }

  var artists = [Artist(id: UUID(), name: "", isPrimary: true)]
  var venueName = ""
  var concertDate = Date()
  var city = ""
  var isTourExpanded = false
  var tour = ""
  var hasStartTime = false
  var startTime = Date()
  var venueTimeZoneIdentifier = ConcertDraft.defaultTimeZoneIdentifier
  var setlist: [SetlistItem] = []
  var hasAttemptedSave = false

  init() {}

  init(detail: ConcertDetail) {
    artists = detail.artists.map {
      Artist(id: $0.id, name: $0.name, isPrimary: $0.isPrimary)
    }
    venueName = detail.concert.venueName
    concertDate = Self.date(from: detail.concert.concertDate) ?? Date()
    city = detail.concert.city ?? ""
    isTourExpanded = detail.concert.tour != nil
    tour = detail.concert.tour ?? ""
    hasStartTime = detail.concert.startsAt != nil
    startTime = detail.concert.startsAt ?? Date()
    venueTimeZoneIdentifier = detail.concert.venueTimeZone ?? Self.defaultTimeZoneIdentifier
    setlist = detail.setlist.map { SetlistItem(id: $0.id, title: $0.title) }
  }

  var hasEnteredContent: Bool {
    artists.contains { !ConcertInput.normalizedText($0.name).isEmpty }
      || !ConcertInput.normalizedText(venueName).isEmpty
      || !ConcertInput.normalizedText(city).isEmpty
      || !ConcertInput.normalizedText(tour).isEmpty
      || hasStartTime
      || setlist.contains { !ConcertInput.normalizedText($0.title).isEmpty }
  }

  var canSave: Bool {
    guard
      !artists.isEmpty,
      artists.count <= 10,
      artists.filter(\.isPrimary).count == 1,
      artists.allSatisfy({ ConcertInput.isValidRequiredText($0.name, maximumLength: 160) }),
      ConcertInput.isValidRequiredText(venueName, maximumLength: 160),
      ConcertInput.isValidOptionalText(city, maximumLength: 100),
      ConcertInput.isValidOptionalText(tour, maximumLength: 160),
      setlist.count <= 50,
      setlist.allSatisfy({ ConcertInput.isValidRequiredText($0.title, maximumLength: 160) })
    else {
      return false
    }

    return !hasStartTime || TimeZone(identifier: venueTimeZoneIdentifier) != nil
  }

  var creationInput: ConcertCreationInput? {
    guard canSave else { return nil }

    return ConcertCreationInput(
      artists: artists.map {
        ConcertArtistInput(
          name: ConcertInput.normalizedText($0.name),
          isPrimary: $0.isPrimary
        )
      },
      venueName: ConcertInput.normalizedText(venueName),
      concertDate: Self.concertDateString(for: concertDate),
      city: Self.optionalNormalizedText(city),
      tour: Self.optionalNormalizedText(tour),
      startsAt: hasStartTime ? venueStartDate() : nil,
      venueTimeZone: hasStartTime ? venueTimeZoneIdentifier : nil,
      setlist: setlist.map { ConcertInput.normalizedText($0.title) }
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
      venueName: input.venueName,
      concertDate: input.concertDate,
      city: input.city,
      tour: input.tour,
      startsAt: input.startsAt,
      venueTimeZone: input.venueTimeZone,
      setlist: input.setlist,
      visibility: visibility
    )
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

  mutating func addArtist() {
    guard artists.count < 10 else { return }
    artists.append(Artist(id: UUID(), name: "", isPrimary: false))
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
  }

  mutating func addSetlistItem() {
    guard setlist.count < 50 else { return }
    setlist.append(SetlistItem(id: UUID(), title: ""))
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

  private static func optionalNormalizedText(_ value: String) -> String? {
    let normalized = ConcertInput.normalizedText(value)
    return normalized.isEmpty ? nil : normalized
  }

  /// A concert date is a venue-local calendar day, not an instant in UTC.
  /// Keep picker values at midnight in the user's calendar so an edit does not
  /// move the selected day west of UTC before it is saved again.
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
