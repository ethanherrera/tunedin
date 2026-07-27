#if DEBUG
  import Foundation

  struct DevelopmentTicketmasterDiscoveryRepository: TicketmasterDiscoveryRepository {
    func discover(
      location: TicketmasterDiscoveryLocation,
      dateRange: DateInterval,
      genre: String?,
      page: Int
    ) async throws -> TicketmasterDiscoveryPage {
      guard page == 0 else {
        return TicketmasterDiscoveryPage(events: [], page: page, hasMore: false)
      }
      let calendar = Calendar(identifier: .gregorian)
      let base = max(dateRange.start, .now)
      let fixtures = [
        event(
          id: "tm-mitski",
          name: "Mitski: The Land Is Inhospitable and So Are We",
          artist: "Mitski",
          venue: "The Greek Theatre",
          genre: "Alternative",
          location: location,
          date: calendar.date(byAdding: .day, value: 2, to: base) ?? base
        ),
        event(
          id: "tm-big-thief",
          name: "Big Thief",
          artist: "Big Thief",
          venue: "The Masonic",
          genre: "Rock",
          location: location,
          date: calendar.date(byAdding: .day, value: 5, to: base) ?? base
        ),
        event(
          id: "tm-vampire-weekend",
          name: "Vampire Weekend",
          artist: "Vampire Weekend",
          venue: "Bill Graham Civic Auditorium",
          genre: "Rock",
          location: location,
          date: calendar.date(byAdding: .day, value: 11, to: base) ?? base
        )
      ]
      .filter { dateRange.contains($0.displayDate) && (genre == nil || $0.genre == genre) }
      .sorted { $0.displayDate < $1.displayDate }
      return TicketmasterDiscoveryPage(events: fixtures, page: page, hasMore: false)
    }

    func resolveEvent(id: String) async throws -> UUID {
      switch id {
      case "tm-mitski": DevelopmentEventFixture.ticketmasterMitskiID
      case "tm-big-thief": DevelopmentEventFixture.ticketmasterBigThiefID
      case "tm-vampire-weekend": DevelopmentEventFixture.ticketmasterVampireWeekendID
      default: throw CommunityEventError.eventUnavailable
      }
    }

    private func event(
      id: String,
      name: String,
      artist: String,
      venue: String,
      genre: String,
      location: TicketmasterDiscoveryLocation,
      date: Date
    ) -> TicketmasterDiscoveryEvent {
      let calendar = Calendar(identifier: .gregorian)
      let scheduledDate = calendar.date(
        bySettingHour: 20,
        minute: 0,
        second: 0,
        of: date
      ) ?? date
      let formatter = DateFormatter()
      formatter.calendar = calendar
      formatter.locale = Locale(identifier: "en_US_POSIX")
      formatter.dateFormat = "yyyy-MM-dd"
      return TicketmasterDiscoveryEvent(
        id: id,
        name: name,
        localDate: formatter.string(from: scheduledDate),
        localTime: "20:00:00",
        dateTime: ISO8601DateFormatter().string(from: scheduledDate),
        timeZone: TimeZone.current.identifier,
        status: "active",
        venue: TicketmasterDiscoveryVenue(
          id: "\(id)-venue",
          name: venue,
          address: nil,
          city: location.city,
          stateCode: location.stateCode,
          countryCode: location.countryCode
        ),
        artists: [TicketmasterDiscoveryArtist(id: "\(id)-artist", name: artist)],
        genre: genre,
        imageURL: nil,
        ticketURL: URL(string: "https://www.ticketmaster.com/event/\(id)")!
      )
    }
  }
#endif
