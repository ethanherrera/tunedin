import Foundation

struct TicketmasterDiscoveryLocation: Codable, Equatable, Hashable, Identifiable, Sendable {
  let city: String
  let stateCode: String?
  let countryCode: String

  var id: String {
    [city, stateCode, countryCode].compactMap(\.self).joined(separator: "-")
  }

  var displayName: String {
    [city, stateCode].compactMap(\.self).joined(separator: ", ")
  }

  static let sanFrancisco = Self(city: "San Francisco", stateCode: "CA", countryCode: "US")
  static let losAngeles = Self(city: "Los Angeles", stateCode: "CA", countryCode: "US")
  static let newYork = Self(city: "New York", stateCode: "NY", countryCode: "US")
  static let chicago = Self(city: "Chicago", stateCode: "IL", countryCode: "US")
  static let austin = Self(city: "Austin", stateCode: "TX", countryCode: "US")

  static let featured: [Self] = [.sanFrancisco, .losAngeles, .newYork, .chicago, .austin]
}

struct TicketmasterDiscoveryDateRange: Equatable, Hashable, Sendable {
  let startDate: Date
  let endDate: Date

  init(
    startDate: Date,
    endDate: Date,
    calendar: Calendar = .current
  ) {
    let normalizedStart = calendar.startOfDay(for: startDate)
    let normalizedEnd = calendar.startOfDay(for: endDate)
    self.startDate = normalizedStart
    self.endDate = max(normalizedStart, normalizedEnd)
  }

  static func nextThirtyDays(
    now: Date = .now,
    calendar: Calendar = .current
  ) -> Self {
    let start = calendar.startOfDay(for: now)
    let end = calendar.date(byAdding: .day, value: 29, to: start) ?? start
    return Self(startDate: start, endDate: end, calendar: calendar)
  }

  var title: String {
    if Calendar.current.isDate(startDate, inSameDayAs: endDate) {
      return startDate.formatted(.dateTime.month(.abbreviated).day())
    }
    return "\(startDate.formatted(.dateTime.month(.abbreviated).day()))–"
      + "\(endDate.formatted(.dateTime.month(.abbreviated).day()))"
  }

  func interval(calendar: Calendar = .current) -> DateInterval {
    DateInterval(
      start: calendar.startOfDay(for: startDate),
      end: calendar.date(
        byAdding: .day,
        value: 1,
        to: calendar.startOfDay(for: endDate)
      ) ?? endDate
    )
  }
}

struct TicketmasterDiscoveryArtist: Codable, Equatable, Hashable, Identifiable, Sendable {
  let id: String
  let name: String
}

struct TicketmasterDiscoveryVenue: Codable, Equatable, Hashable, Identifiable, Sendable {
  let id: String
  let name: String
  let address: String?
  let city: String
  let stateCode: String?
  let countryCode: String
}

struct TicketmasterDiscoveryEvent: Codable, Equatable, Identifiable, Sendable {
  let id: String
  let name: String
  let localDate: String
  let localTime: String?
  let dateTime: String?
  let timeZone: String?
  let status: String
  let venue: TicketmasterDiscoveryVenue
  let artists: [TicketmasterDiscoveryArtist]
  let genre: String?
  let imageURL: URL?
  let ticketURL: URL

  var displayDate: Date {
    if let dateTime {
      let formatter = ISO8601DateFormatter()
      if let parsed = formatter.date(from: dateTime) {
        return parsed
      }
    }
    return CommunityEventDateCoding.date(from: localDate) ?? .distantFuture
  }

  var headlinerName: String {
    artists.first?.name ?? name
  }
}

struct TicketmasterDiscoveryPage: Equatable, Sendable {
  let events: [TicketmasterDiscoveryEvent]
  let page: Int
  let hasMore: Bool
}
