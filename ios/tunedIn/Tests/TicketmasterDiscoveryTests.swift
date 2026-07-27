import Foundation
import Testing
@testable import tunedIn

struct TicketmasterDiscoveryTests {
  @Test
  func discoveryDateRangeIncludesTheEntireEndDate() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try #require(TimeZone(identifier: "America/Los_Angeles"))
    let now = Date(timeIntervalSince1970: 1_775_004_300)
    let end = try #require(calendar.date(byAdding: .day, value: 6, to: now))

    let interval = TicketmasterDiscoveryDateRange(
      startDate: now,
      endDate: end,
      calendar: calendar
    ).interval(calendar: calendar)

    #expect(interval.start == calendar.startOfDay(for: now))
    #expect(calendar.dateComponents([.day], from: interval.start, to: interval.end).day == 7)
  }

  @Test
  func discoveryDateRangeClampsAnInvalidEndToItsBeginning() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try #require(TimeZone(identifier: "America/Los_Angeles"))
    let now = Date(timeIntervalSince1970: 1_775_004_300)
    let yesterday = try #require(calendar.date(byAdding: .day, value: -1, to: now))

    let range = TicketmasterDiscoveryDateRange(
      startDate: now,
      endDate: yesterday,
      calendar: calendar
    )

    #expect(range.startDate == range.endDate)
  }

  @Test
  func discoveryArtworkUsesStableOpaqueCacheIdentity() {
    let first = AppMediaResource.discoveryArtwork(externalID: "G5vYZbfixture")
    let second = AppMediaResource.discoveryArtwork(externalID: "G5vYZbfixture")
    let other = AppMediaResource.discoveryArtwork(externalID: "G5vYZbother")

    #expect(first == second)
    #expect(first != other)
    #expect(first.cacheRequest.url?.host == "media-cache.tunedin.invalid")
    #expect(first.cacheRequest.url?.absoluteString.contains("G5vYZbfixture") == false)
  }

  #if DEBUG
    @Test
    func developmentDiscoveryResolvesToTicketmasterSpecificFixture() async throws {
      let repository = DevelopmentTicketmasterDiscoveryRepository()
      let eventID = try await repository.resolveEvent(id: "tm-big-thief")

      #expect(eventID == DevelopmentEventFixture.ticketmasterBigThiefID)

      let eventRepository = DevelopmentEventRepository()
      let detail = try await eventRepository.eventDetail(
        id: eventID,
        viewerID: DevelopmentSocialFixture.currentUserID
      )
      #expect(detail.summary.sourceLabel == "Ticketmaster")
      #expect(detail.summary.sourceURL?.host == "www.ticketmaster.com")
    }
  #endif
}
