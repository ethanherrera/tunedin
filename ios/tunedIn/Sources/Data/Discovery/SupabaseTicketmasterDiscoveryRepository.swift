import Foundation
import Supabase

struct SupabaseTicketmasterDiscoveryRepository: TicketmasterDiscoveryRepository {
  private let client: SupabaseClient

  init(client: SupabaseClient) {
    self.client = client
  }

  func discover(
    location: TicketmasterDiscoveryLocation,
    dateRange: DateInterval,
    genre: String?,
    page: Int
  ) async throws -> TicketmasterDiscoveryPage {
    try await withAppFailure {
      let response: TicketmasterDiscoverResponse = try await client.functions.invoke(
        "event-discovery",
        options: FunctionInvokeOptions(
          body: TicketmasterDiscoverRequest(
            location: location,
            dateRange: dateRange,
            genre: genre,
            page: page
          )
        )
      )
      return TicketmasterDiscoveryPage(
        events: response.events,
        page: response.page,
        hasMore: response.hasMore
      )
    }
  }

  func resolveEvent(id: String) async throws -> UUID {
    try await withAppFailure {
      let response: TicketmasterResolveResponse = try await client.functions.invoke(
        "event-discovery",
        options: FunctionInvokeOptions(body: TicketmasterResolveRequest(eventID: id))
      )
      return response.catalogEventID
    }
  }
}

private struct TicketmasterDiscoverRequest: Encodable, Sendable {
  let operation = "discover"
  let location: TicketmasterDiscoveryLocation
  let startDateTime: String
  let endDateTime: String
  let genre: String?
  let page: Int

  init(
    location: TicketmasterDiscoveryLocation,
    dateRange: DateInterval,
    genre: String?,
    page: Int
  ) {
    self.location = location
    startDateTime = Self.dateTime(dateRange.start)
    endDateTime = Self.dateTime(dateRange.end)
    self.genre = genre
    self.page = page
  }

  private static func dateTime(_ date: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.string(from: date)
  }
}

private struct TicketmasterDiscoverResponse: Decodable, Sendable {
  let page: Int
  let hasMore: Bool
  let events: [TicketmasterDiscoveryEvent]
}

private struct TicketmasterResolveRequest: Encodable, Sendable {
  let operation = "resolve"
  let eventID: String

  enum CodingKeys: String, CodingKey {
    case operation
    case eventID = "eventId"
  }
}

private struct TicketmasterResolveResponse: Decodable, Sendable {
  let catalogEventID: UUID

  enum CodingKeys: String, CodingKey {
    case catalogEventID = "catalogEventId"
  }
}
