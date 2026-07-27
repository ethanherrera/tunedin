import Foundation
import SwiftUI

protocol TicketmasterDiscoveryRepository: Sendable {
  func discover(
    location: TicketmasterDiscoveryLocation,
    dateRange: DateInterval,
    genre: String?,
    page: Int
  ) async throws -> TicketmasterDiscoveryPage

  func resolveEvent(id: String) async throws -> UUID
}

extension EnvironmentValues {
  @Entry var ticketmasterDiscoveryRepository: any TicketmasterDiscoveryRepository =
    UnavailableTicketmasterDiscoveryRepository()
}

private struct UnavailableTicketmasterDiscoveryRepository: TicketmasterDiscoveryRepository {
  func discover(
    location _: TicketmasterDiscoveryLocation,
    dateRange _: DateInterval,
    genre _: String?,
    page _: Int
  ) async throws -> TicketmasterDiscoveryPage {
    throw CommunityEventError.featureUnavailable("Ticketmaster discovery")
  }

  func resolveEvent(id _: String) async throws -> UUID {
    throw CommunityEventError.featureUnavailable("Ticketmaster discovery")
  }
}
