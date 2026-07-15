import Foundation
import Testing
@testable import tunedIn

struct MusicCatalogContractTests {
  @Test
  func decodesRequiredOriginAndStructuredMetadata() throws {
    let data = Data(
      #"""
      {
        "source":"tunedin",
        "origin":"musicbrainz",
        "kind":"song",
        "catalogId":"10000000-0000-0000-0000-000000000001",
        "musicBrainzId":"20000000-0000-0000-0000-000000000001",
        "displayName":"Under Pressure",
        "sortName":null,
        "disambiguation":"studio recording",
        "subtitle":"Queen & David Bowie · 1981",
        "metadata":{
          "artistCredit":[
            {
              "artistCatalogId":"30000000-0000-0000-0000-000000000001",
              "artistMusicBrainzId":"40000000-0000-0000-0000-000000000001",
              "name":"Queen",
              "canonicalName":"Queen",
              "joinPhrase":" & "
            },
            {
              "artistCatalogId":"30000000-0000-0000-0000-000000000002",
              "artistMusicBrainzId":"40000000-0000-0000-0000-000000000002",
              "name":"David Bowie",
              "canonicalName":"David Bowie",
              "joinPhrase":""
            }
          ],
          "firstReleaseDate":"1981"
        }
      }
      """#.utf8
    )

    let result = try JSONDecoder().decode(CatalogResult.self, from: data)
    let entity = try CatalogEntity(resolved: result)

    #expect(result.origin == .musicBrainz)
    guard case let .song(song) = entity else {
      Issue.record("Expected a song")
      return
    }
    #expect(song.artistCredit == "Queen & David Bowie")
    #expect(try song.artistIDs == [
      #require(UUID(uuidString: "30000000-0000-0000-0000-000000000001")),
      #require(UUID(uuidString: "30000000-0000-0000-0000-000000000002"))
    ])
  }

  @Test(arguments: [CatalogOrigin.tunedInCustom, .legacyImport, .legacyClient])
  func decodesEveryLocalOrigin(origin: CatalogOrigin) throws {
    let json = #"""
    {
      "source":"tunedin",
      "origin":"\#(origin.rawValue)",
      "kind":"artist",
      "catalogId":"10000000-0000-0000-0000-000000000001",
      "musicBrainzId":null,
      "displayName":"Local artist",
      "sortName":null,
      "disambiguation":null,
      "subtitle":null,
      "metadata":{}
    }
    """#

    let result = try JSONDecoder().decode(CatalogResult.self, from: Data(json.utf8))
    #expect(result.origin == origin)
    #expect(result.source == .tunedIn)
  }

  @Test
  func searchRequestOmitsOptionalFieldsAndUsesExactContractKeys() throws {
    let request = CatalogGatewaySearchRequest(
      entity: .artist,
      query: "Phoenix",
      offset: nil,
      artistContextIDs: nil
    )
    let encoded = try JSONEncoder().encode(request)
    let object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])

    #expect(Set(object.keys) == ["operation", "entity", "query"])
    #expect(object["operation"] as? String == "search")
    #expect(object["entity"] as? String == "artist")
  }

  @Test
  func resolveRequestUsesExactContractKeys() throws {
    let musicBrainzID = try #require(UUID(uuidString: "10000000-0000-0000-0000-000000000001"))
    let request = CatalogGatewayResolveRequest(entity: .place, musicBrainzID: musicBrainzID)
    let object = try encodedObject(request)

    #expect(Set(object.keys) == ["operation", "entity", "musicBrainzId"])
    #expect(object["operation"] as? String == "resolve")
    #expect(object["entity"] as? String == "place")
    #expect(object["musicBrainzId"] as? String == musicBrainzID.uuidString)
  }

  @Test
  func customArtistAreaAndPlaceParametersUseOnlyBackendContractKeys() throws {
    let areaID = try #require(UUID(uuidString: "10000000-0000-0000-0000-000000000001"))
    let parentAreaID = try #require(UUID(uuidString: "10000000-0000-0000-0000-000000000002"))

    let artist = try encodedObject(
      CustomArtistParameters(
        input: CustomCatalogArtistInput(
          name: "  The   Artist  ", artistType: "Group", disambiguation: " local act ",
          areaID: areaID, areaName: "Ignored display value"
        )
      )
    )
    #expect(Set(artist.keys) == ["p_name", "p_artist_type", "p_disambiguation", "p_area_id"])
    #expect(artist["p_name"] as? String == "The Artist")
    #expect(artist["p_area_id"] as? String == areaID.uuidString)
    #expect(artist["area_name"] == nil)

    let area = try encodedObject(
      CustomAreaParameters(
        input: CustomCatalogAreaInput(
          name: "Berkeley", countryCode: "US", parentAreaID: parentAreaID
        )
      )
    )
    #expect(Set(area.keys) == ["p_name", "p_country_code", "p_parent_area_id"])

    let place = try encodedObject(
      CustomPlaceParameters(
        input: CustomCatalogPlaceInput(
          name: "The Greek Theatre", placeType: "Amphitheatre", address: "2001 Gayley Road",
          areaID: areaID, areaName: "Ignored display value"
        )
      )
    )
    #expect(Set(place.keys) == ["p_name", "p_place_type", "p_address", "p_area_id"])
    #expect(place["area_name"] == nil)
  }

  @Test
  func customSongAndTourParametersUseOnlyCatalogArtistIDs() throws {
    let firstArtistID = try #require(UUID(uuidString: "20000000-0000-0000-0000-000000000001"))
    let secondArtistID = try #require(UUID(uuidString: "20000000-0000-0000-0000-000000000002"))

    let song = try encodedObject(
      CustomSongParameters(
        input: CustomCatalogSongInput(
          title: "Song", artistIDs: [firstArtistID, secondArtistID],
          artistNames: ["Ignored", "Display values"]
        )
      )
    )
    #expect(Set(song.keys) == ["p_title", "p_artist_ids"])
    #expect(song["artist_names"] == nil)

    let tour = try encodedObject(
      CustomTourParameters(
        input: CustomCatalogTourInput(
          name: "Tour", artistIDs: [secondArtistID, firstArtistID],
          artistNames: ["Ignored", "Display values"]
        )
      )
    )
    #expect(Set(tour.keys) == ["p_name", "p_artist_ids"])
    #expect(tour["artist_names"] == nil)
  }

  @Test
  func resolvedPlaceCarriesStructuredAreaIdentity() throws {
    let areaID = try #require(UUID(uuidString: "30000000-0000-0000-0000-000000000001"))
    let result = CatalogResult(
      source: .tunedIn,
      origin: .musicBrainz,
      kind: .place,
      catalogID: UUID(uuidString: "20000000-0000-0000-0000-000000000001"),
      musicBrainzID: UUID(uuidString: "10000000-0000-0000-0000-000000000001"),
      displayName: "The Greek Theatre",
      sortName: nil,
      disambiguation: nil,
      subtitle: "Berkeley",
      metadata: [
        "areaCatalogId": .string(areaID.uuidString),
        "areaName": .string("Berkeley")
      ]
    )

    guard case let .place(place) = try CatalogEntity(resolved: result) else {
      Issue.record("Expected a place")
      return
    }
    #expect(place.areaID == areaID)
    #expect(place.areaName == "Berkeley")
  }

  private func encodedObject(_ value: some Encodable) throws -> [String: Any] {
    let data = try JSONEncoder().encode(value)
    return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
  }
}

@MainActor
struct CatalogSearchModelTests {
  @Test
  func rejectsStaleResponsesAfterQueryChanges() async throws {
    let repository = CatalogSearchTestRepository()
    await repository.setDelay(.milliseconds(80), for: "old")
    await repository.setResults([Self.result(name: "Old")], for: "old")
    await repository.setResults([Self.result(name: "New")], for: "new")
    let model = CatalogSearchModel(
      repository: repository,
      kind: .artist,
      debounceDuration: .zero
    )

    model.updateQuery("old")
    try await Task.sleep(for: .milliseconds(5))
    model.updateQuery("new")
    try await waitUntil { model.phase == .results }

    #expect(model.results.map(\.displayName) == ["New"])
  }

  @Test
  func paginatesWithoutDuplicatingExistingResults() async throws {
    let first = (0 ..< 15).map { Self.result(name: "Artist \($0)", id: $0 + 1) }
    let last = Self.result(name: "Artist 15", id: 16)
    let repository = CatalogSearchTestRepository()
    await repository.setPage(first, query: "artist", offset: 0, hasMore: true)
    await repository.setPage([first[0], last], query: "artist", offset: 15, hasMore: false)
    let model = CatalogSearchModel(repository: repository, kind: .artist, debounceDuration: .zero)

    model.updateQuery("artist")
    try await waitUntil { model.phase == .results }
    await model.loadMore()

    #expect(model.results.count == 16)
    #expect(model.results.last?.displayName == "Artist 15")
    #expect(!model.hasMore)
  }

  @Test
  func songSearchPassesTheFullLineupContext() async throws {
    let headlinerID = try #require(UUID(uuidString: "40000000-0000-0000-0000-000000000001"))
    let supportID = try #require(UUID(uuidString: "40000000-0000-0000-0000-000000000002"))
    let repository = CatalogSearchTestRepository()
    await repository.setResults([Self.result(name: "Lineup song", kind: .song)], for: "song")
    let model = CatalogSearchModel(
      repository: repository,
      kind: .song,
      artistContextIDs: [headlinerID, supportID],
      debounceDuration: .zero
    )

    model.updateQuery("song")
    try await waitUntil { model.phase == .results }

    let contexts = await repository.searchArtistContexts
    #expect(contexts == [[headlinerID, supportID]])
  }

  @Test
  func paginationAdvancesByGatewayPageSizeAfterShortDeduplicatedPage() async throws {
    let duplicate = Self.result(name: "Artist 1", id: 1)
    let next = Self.result(name: "Artist 2", id: 2)
    let repository = CatalogSearchTestRepository()
    await repository.setPage([duplicate], query: "artist", offset: 0, hasMore: true)
    await repository.setPage([duplicate, next], query: "artist", offset: 15, hasMore: false)
    let model = CatalogSearchModel(repository: repository, kind: .artist, debounceDuration: .zero)

    model.updateQuery("artist")
    try await waitUntil { model.phase == .results }
    await model.loadMore()

    #expect(model.results.map(\.displayName) == ["Artist 1", "Artist 2"])
    let searchOffsets = await repository.searchOffsets
    #expect(searchOffsets == [0, 15])
  }

  @Test
  func paginationFailureKeepsExistingResultsSelectable() async throws {
    let first = Self.result(name: "Saved artist")
    let repository = CatalogSearchTestRepository()
    await repository.setPage([first], query: "artist", offset: 0, hasMore: true)
    await repository.setPageError(.offline, query: "artist", offset: 15)
    let model = CatalogSearchModel(repository: repository, kind: .artist, debounceDuration: .zero)

    model.updateQuery("artist")
    try await waitUntil { model.phase == .results }
    await model.loadMore()

    #expect(model.phase == .results)
    #expect(model.results.map(\.displayName) == ["Saved artist"])
    #expect(model.paginationErrorMessage != nil)
    #expect(model.hasMore)
  }

  @Test
  func exposesOfflineAndRateLimitedStates() async throws {
    let repository = CatalogSearchTestRepository()
    await repository.setError(.offline, for: "offline")
    await repository.setError(.rateLimited(retryAfterSeconds: 4), for: "busy")
    let model = CatalogSearchModel(repository: repository, kind: .artist, debounceDuration: .zero)

    model.updateQuery("offline")
    try await waitUntil { model.phase == .offline }

    model.updateQuery("busy")
    try await waitUntil {
      model.phase == .rateLimited(retryAfterSeconds: 4)
    }
  }

  @Test
  func selectingCandidateRequiresResolution() async throws {
    let repository = CatalogSearchTestRepository()
    let candidate = Self.result(name: "Phoenix", source: .musicBrainz, catalogID: nil)
    try await repository.setResolved(Self.artistEntity(name: "Phoenix"), for: #require(candidate.musicBrainzID))
    let model = CatalogSearchModel(repository: repository, kind: .artist, debounceDuration: .zero)

    let resolved = await model.resolve(candidate)

    #expect(resolved?.id == Self.artistEntity(name: "Phoenix").id)
    let resolveCallCount = await repository.resolveCallCount
    #expect(resolveCallCount == 1)
  }

  @Test
  func queryChangeInvalidatesResolutionEvenWhenRepositoryIgnoresCancellation() async throws {
    let repository = CatalogSearchTestRepository()
    let candidate = Self.result(name: "Phoenix", source: .musicBrainz, catalogID: nil)
    try await repository.setResolved(Self.artistEntity(name: "Phoenix"), for: #require(candidate.musicBrainzID))
    await repository.setResolutionDelay(.milliseconds(80))
    let model = CatalogSearchModel(repository: repository, kind: .artist, debounceDuration: .zero)

    let resolution = Task { await model.resolve(candidate) }
    try await Task.sleep(for: .milliseconds(5))
    model.updateQuery("another artist")

    #expect(await resolution.value == nil)
    #expect(model.resolvingResultID == nil)
    #expect(model.selectionErrorMessage == nil)
  }

  @Test
  func dismissalCancellationInvalidatesResolution() async throws {
    let repository = CatalogSearchTestRepository()
    let candidate = Self.result(name: "Phoenix", source: .musicBrainz, catalogID: nil)
    try await repository.setResolved(Self.artistEntity(name: "Phoenix"), for: #require(candidate.musicBrainzID))
    await repository.setResolutionDelay(.milliseconds(80))
    let model = CatalogSearchModel(repository: repository, kind: .artist, debounceDuration: .zero)

    let resolution = Task { await model.resolve(candidate) }
    try await Task.sleep(for: .milliseconds(5))
    model.cancelResolution()

    #expect(await resolution.value == nil)
    #expect(model.resolvingResultID == nil)
  }

  private func waitUntil(
    timeout: Duration = .seconds(1),
    condition: @escaping @MainActor () -> Bool
  ) async throws {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)
    while !condition() {
      guard clock.now < deadline else {
        Issue.record("Timed out waiting for catalog model state")
        return
      }
      try await Task.sleep(for: .milliseconds(5))
    }
  }

  private static func result(
    name: String,
    id: Int = 1,
    kind: CatalogEntityKind = .artist,
    source: CatalogSource = .tunedIn,
    catalogID: UUID? = nil
  ) -> CatalogResult {
    CatalogResult(
      source: source,
      origin: .musicBrainz,
      kind: kind,
      catalogID: catalogID ?? (source == .tunedIn
        ? UUID(uuidString: String(format: "10000000-0000-0000-0000-%012d", id))
        : nil),
      musicBrainzID: UUID(uuidString: String(format: "20000000-0000-0000-0000-%012d", id)),
      displayName: name,
      sortName: name,
      disambiguation: nil,
      subtitle: nil,
      metadata: [:]
    )
  }

  private static func artistEntity(name: String) -> CatalogEntity {
    .artist(
      CatalogArtist(
        id: UUID(uuidString: "30000000-0000-0000-0000-000000000001")!,
        origin: .musicBrainz,
        musicBrainzID: UUID(uuidString: "20000000-0000-0000-0000-000000000001"),
        displayName: name,
        sortName: name,
        disambiguation: nil,
        subtitle: nil,
        artistType: "Group",
        areaID: nil,
        areaName: nil
      )
    )
  }
}

struct CatalogCustomEntryDefaultsTests {
  @Test
  func songSearchKeepsFullLineupWhileCustomFallbackDefaultsToHeadliner() throws {
    let headliner = try artist(
      id: #require(UUID(uuidString: "40000000-0000-0000-0000-000000000001")),
      name: "Headliner"
    )
    let support = try artist(
      id: #require(UUID(uuidString: "40000000-0000-0000-0000-000000000002")),
      name: "Support"
    )
    let lineup = [headliner, support]
    let configuration = CatalogPickerConfiguration(kind: .song, artistContext: lineup)

    #expect(configuration.artistContext.map(\.id) == [headliner.id, support.id])
    #expect(
      CatalogCustomEntryDefaults.selectedArtists(for: .song, artistContext: configuration.artistContext).map(\.id)
        == [headliner.id]
    )
    #expect(CatalogCustomEntryDefaults.selectedArtists(for: .tour, artistContext: lineup).map(\.id) == lineup.map(\.id))
  }

  private func artist(id: UUID, name: String) -> CatalogArtist {
    CatalogArtist(
      id: id,
      origin: .tunedInCustom,
      musicBrainzID: nil,
      displayName: name,
      sortName: name,
      disambiguation: nil,
      subtitle: nil,
      artistType: nil,
      areaID: nil,
      areaName: nil
    )
  }
}
