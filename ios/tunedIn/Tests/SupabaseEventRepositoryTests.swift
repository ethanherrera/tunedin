import Foundation
import Testing
@testable import tunedIn

struct SupabaseEventRepositoryContractTests {
  @Test
  func phaseOneCapabilitiesExposeOnlyImplementedDiscoveryBehavior() async {
    let repository = PhaseOneEventRepositoryDouble()

    #expect(repository.capabilities == .phase1Discovery)
    #expect(repository.capabilities.contains(.discovery))
    #expect(!repository.capabilities.contains(.plans))
    #expect(!repository.capabilities.contains(.attendance))
    #expect(!repository.capabilities.contains(.conversation))
    #expect(!repository.capabilities.contains(.invitations))
    #expect(!repository.capabilities.contains(.diaries))

    await #expect(throws: CommunityEventError.featureUnavailable("Plans")) {
      try await repository.plans(viewerID: UUID())
    }
    await #expect(throws: CommunityEventError.featureUnavailable("Going and Went")) {
      try await repository.setAttendance(
        eventID: UUID(),
        viewerID: UUID(),
        status: .going,
        audience: .friends
      )
    }
  }

  @Test
  func searchAndDetailParametersUseExactRPCContractKeys() throws {
    let eventID = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
    let search = try encodedObject(
      SearchCatalogEventsParameters(query: "Mitski", filters: ["phase": "upcoming"], limit: 25)
    )
    let detail = try encodedObject(CatalogEventIDParameters(eventID: eventID))

    #expect(Set(search.keys) == ["p_query", "p_filters", "p_limit"])
    #expect(search["p_query"] as? String == "Mitski")
    #expect(search["p_filters"] as? [String: String] == ["phase": "upcoming"])
    #expect(search["p_limit"] as? Int == 25)
    #expect(Set(detail.keys) == ["p_event_id"])
    #expect(detail["p_event_id"] as? String == eventID.uuidString)
  }

  @Test
  func creationParametersUseCatalogIDsAndVenueLocalDate() throws {
    let artistID = UUID(uuidString: "20000000-0000-0000-0000-000000000001")!
    let placeID = UUID(uuidString: "30000000-0000-0000-0000-000000000001")!
    let areaID = UUID(uuidString: "40000000-0000-0000-0000-000000000001")!
    let instant = try #require(CommunityEventDateCoding.dateTime(from: "2026-07-17T02:30:00Z"))
    let input = CommunityEventCreationInput(
      artists: [artist(id: artistID, name: "Mitski")],
      place: place(id: placeID, areaID: areaID),
      tour: nil,
      eventDate: instant,
      startsAt: nil,
      timeZoneIdentifier: "America/New_York",
      listing: .listed
    )

    let object = try encodedObject(CreateCatalogEventParameters(input: input))
    let artists = try #require(object["p_artists"] as? [[String: Any]])

    #expect(Set(object.keys) == [
      "p_artists", "p_catalog_place_id", "p_event_date", "p_time_zone_identifier", "p_listing"
    ])
    #expect(object["p_catalog_place_id"] as? String == placeID.uuidString)
    #expect(object["p_event_date"] as? String == "2026-07-16")
    #expect(object["p_time_zone_identifier"] as? String == "America/New_York")
    #expect(object["p_listing"] as? String == "listed")
    #expect(artists.count == 1)
    #expect(artists.first?["catalog_artist_id"] as? String == artistID.uuidString)
    #expect(artists.first?["is_primary"] as? Bool == true)
  }

  @Test
  func eventRecordMapsBackendSnapshotsWithoutProviderData() throws {
    let data = Data(
      #"""
      {
        "event_id":"50000000-0000-0000-0000-000000000001",
        "artists":[
          {
            "catalog_artist_id":"20000000-0000-0000-0000-000000000001",
            "display_name":"Mitski",
            "position":0,
            "is_headliner":true
          }
        ],
        "catalog_place_id":"30000000-0000-0000-0000-000000000001",
        "catalog_area_id":"40000000-0000-0000-0000-000000000001",
        "catalog_tour_id":null,
        "venue_name":"The Anthem",
        "area_name":"Washington, D.C.",
        "event_date":"2026-09-17",
        "starts_at":"2026-09-17T23:30:00Z",
        "time_zone_identifier":"America/New_York",
        "memory_unlock_at":"2026-09-18T08:00:00Z",
        "lifecycle":"scheduled",
        "listing":"listed",
        "integrity":"community_added",
        "row_state":"active",
        "source_label":"Community made"
      }
      """#.utf8
    )
    let record = try JSONDecoder().decode(CatalogEventRPCRecord.self, from: data)
    let summary = try CommunityEventSummary(databaseRecord: record)

    #expect(summary.id == UUID(uuidString: "50000000-0000-0000-0000-000000000001"))
    #expect(summary.title == "Mitski")
    #expect(summary.venueName == "The Anthem")
    #expect(summary.areaName == "Washington, D.C.")
    #expect(summary.timeZoneIdentifier == "America/New_York")
    #expect(summary.sourceLabel == "Community made")
    #expect(summary.currentUserAttendance == nil)
    #expect(summary.friendPreviews.isEmpty)
    #expect(summary.publicGoingCount == 0)
    #expect(summary.diaryCount == 0)
  }

  @Test
  func changingVenueTimeZonePreservesTheEnteredWallClockTime() throws {
    let losAngeles = try #require(TimeZone(identifier: "America/Los_Angeles"))
    let newYork = try #require(TimeZone(identifier: "America/New_York"))
    let original = try #require(CommunityEventDateCoding.dateTime(from: "2026-09-18T02:30:00Z"))

    let shifted = CommunityEventDateCoding.preservingWallClockTime(
      original,
      from: losAngeles,
      to: newYork
    )

    #expect(CommunityEventDateCoding.dateTimeString(shifted) == "2026-09-17T23:30:00.000Z")
  }

  private func encodedObject(_ value: some Encodable) throws -> [String: Any] {
    let data = try JSONEncoder().encode(value)
    return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
  }

  private func artist(id: UUID, name: String) -> CatalogArtist {
    CatalogArtist(
      id: id,
      origin: .musicBrainz,
      musicBrainzID: UUID(),
      displayName: name,
      sortName: name,
      disambiguation: nil,
      subtitle: nil,
      artistType: "Person",
      areaID: nil,
      areaName: nil
    )
  }

  private func place(id: UUID, areaID: UUID) -> CatalogPlace {
    CatalogPlace(
      id: id,
      origin: .musicBrainz,
      musicBrainzID: UUID(),
      displayName: "The Anthem",
      sortName: "The Anthem",
      disambiguation: nil,
      subtitle: "Washington, D.C.",
      placeType: "Venue",
      address: nil,
      areaID: areaID,
      areaName: "Washington, D.C."
    )
  }
}

private struct PhaseOneEventRepositoryDouble: EventRepository {
  let capabilities = EventRepositoryCapabilities.phase1Discovery

  func searchEvents(query _: String, viewerID _: UUID) async throws -> [CommunityEventSummary] {
    []
  }

  func eventDetail(id _: UUID, viewerID _: UUID) async throws -> CommunityEventDetail {
    throw CommunityEventError.eventUnavailable
  }

  func createEvent(
    _ input: CommunityEventCreationInput,
    creatorID _: UUID
  ) async throws -> CommunityEventDetail {
    throw CommunityEventError.invalidEvent(input.artists.isEmpty ? "Artist required" : "Test only")
  }
}
