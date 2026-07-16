import Foundation
import Supabase

struct SupabaseMusicCatalogRepository: MusicCatalogRepository {
  private let client: SupabaseClient

  init(client: SupabaseClient) {
    self.client = client
  }

  func search(
    kind: CatalogEntityKind,
    query: String,
    offset: Int,
    artistContextIDs: [UUID],
    concertContextID: UUID?
  ) async throws -> CatalogSearchPage {
    let normalized = CatalogInput.normalizedText(query)
    guard normalized.count >= 2, offset >= 0 else {
      throw MusicCatalogError.rejected(message: "Enter at least two characters to search.", retryable: false)
    }

    let request = CatalogGatewaySearchRequest(
      entity: kind,
      query: normalized,
      offset: offset == 0 ? nil : offset,
      artistContextIDs: artistContextIDs.isEmpty ? nil : artistContextIDs,
      concertContextID: concertContextID
    )
    let response: CatalogGatewaySearchResponse = try await invoke(request)
    guard
      response.operation == "search",
      response.entity == kind,
      response.offset == offset,
      response.limit == CatalogSearchPage.limit,
      response.results.allSatisfy({ $0.kind == kind })
    else {
      throw MusicCatalogError.invalidResponse
    }
    return CatalogSearchPage(
      kind: kind,
      offset: response.offset,
      hasMore: response.hasMore,
      isPartial: response.isPartial,
      results: response.results
    )
  }

  func resolve(_ candidate: CatalogResult) async throws -> CatalogEntity {
    if !candidate.requiresResolution {
      return try CatalogEntity(resolved: candidate)
    }
    guard let musicBrainzID = candidate.musicBrainzID else {
      throw MusicCatalogError.unresolvedCandidate
    }

    do {
      let request = CatalogGatewayResolveRequest(entity: candidate.kind, musicBrainzID: musicBrainzID)
      let response: CatalogGatewayResolveResponse = try await invoke(request)
      guard
        response.operation == "resolve",
        response.entity.kind == candidate.kind,
        response.entity.source == .tunedIn,
        response.entity.catalogID != nil
      else {
        throw MusicCatalogError.invalidResponse
      }
      return try CatalogEntity(resolved: response.entity)
    } catch let error as MusicCatalogError
      where candidate.catalogID != nil
      && candidate.origin == .musicBrainz
      && error.isRetryable
    {
      // Lookup cache expiry drives the 30-day MusicBrainz refresh. A saved identity
      // remains usable during a transient refresh outage because its tunedIn UUID
      // and server-derived metadata have already crossed the trust boundary.
      return try CatalogEntity(resolved: candidate)
    }
  }

  func createCustomArtist(_ input: CustomCatalogArtistInput) async throws -> CatalogArtist {
    let entity = try await customRPC(
      name: "create_custom_catalog_artist",
      parameters: CustomArtistParameters(input: input),
      expectedKind: .artist
    )
    guard case let .artist(value) = entity else { throw MusicCatalogError.wrongEntityKind }
    return value
  }

  func createCustomArea(_ input: CustomCatalogAreaInput) async throws -> CatalogArea {
    let entity = try await customRPC(
      name: "create_custom_catalog_area",
      parameters: CustomAreaParameters(input: input),
      expectedKind: .area
    )
    guard case let .area(value) = entity else { throw MusicCatalogError.wrongEntityKind }
    return value
  }

  func createCustomPlace(_ input: CustomCatalogPlaceInput) async throws -> CatalogPlace {
    let entity = try await customRPC(
      name: "create_custom_catalog_place",
      parameters: CustomPlaceParameters(input: input),
      expectedKind: .place
    )
    guard case let .place(value) = entity else { throw MusicCatalogError.wrongEntityKind }
    return value
  }

  func createCustomSong(_ input: CustomCatalogSongInput) async throws -> CatalogSong {
    let entity = try await customRPC(
      name: "create_custom_catalog_song",
      parameters: CustomSongParameters(input: input),
      expectedKind: .song
    )
    guard case let .song(value) = entity else { throw MusicCatalogError.wrongEntityKind }
    return value
  }

  func createCustomTour(_ input: CustomCatalogTourInput) async throws -> CatalogTour {
    let entity = try await customRPC(
      name: "create_custom_catalog_tour",
      parameters: CustomTourParameters(input: input),
      expectedKind: .tour
    )
    guard case let .tour(value) = entity else { throw MusicCatalogError.wrongEntityKind }
    return value
  }

  private func invoke<Response: Decodable & Sendable>(
    _ request: some Encodable & Sendable
  ) async throws -> Response {
    do {
      return try await client.functions.invoke(
        "music-catalog",
        options: FunctionInvokeOptions(body: request)
      )
    } catch {
      throw Self.catalogError(from: error)
    }
  }

  private func customRPC(
    name: String,
    parameters: some Encodable & Sendable,
    expectedKind: CatalogEntityKind
  ) async throws -> CatalogEntity {
    do {
      let response: PostgrestResponse<CatalogCustomRPCRecord> = try await client
        .rpc(name, params: parameters)
        .single()
        .execute()
      return try CatalogEntity(resolved: response.value.catalogResult(kind: expectedKind))
    } catch {
      throw Self.catalogError(from: error)
    }
  }

  private static func catalogError(from error: Error) -> MusicCatalogError {
    if let catalogError = error as? MusicCatalogError {
      return catalogError
    }
    if let urlError = error as? URLError {
      switch urlError.code {
      case .notConnectedToInternet, .networkConnectionLost, .cannotConnectToHost,
           .cannotFindHost, .dnsLookupFailed, .dataNotAllowed:
        return .offline
      default:
        return .rejected(message: "The catalog could not be reached. Please try again.", retryable: true)
      }
    }
    if case let FunctionsError.httpError(status, data) = error {
      if let envelope = try? JSONDecoder().decode(CatalogGatewayErrorEnvelope.self, from: data) {
        if status == 429 || envelope.error.code.contains("rate") {
          return .rateLimited(retryAfterSeconds: envelope.error.retryAfterSeconds)
        }
        return .rejected(
          message: CatalogGatewayErrorCopy.message(
            code: envelope.error.code,
            fallback: envelope.error.message
          ),
          retryable: envelope.error.retryable
        )
      }
      if status == 429 {
        return .rateLimited(retryAfterSeconds: nil)
      }
      return .rejected(message: "The catalog request failed. Please try again.", retryable: status >= 500)
    }
    return AppFailure(error).allowsRetry
      ? .rejected(message: "The catalog request failed. Please try again.", retryable: true)
      : .rejected(message: error.localizedDescription, retryable: false)
  }
}

struct CatalogGatewaySearchRequest: Encodable, Equatable, Sendable {
  let operation = "search"
  let entity: CatalogEntityKind
  let query: String
  let offset: Int?
  let artistContextIDs: [UUID]?
  let concertContextID: UUID?

  init(
    entity: CatalogEntityKind,
    query: String,
    offset: Int?,
    artistContextIDs: [UUID]?,
    concertContextID: UUID? = nil
  ) {
    self.entity = entity
    self.query = query
    self.offset = offset
    self.artistContextIDs = artistContextIDs
    self.concertContextID = concertContextID
  }

  enum CodingKeys: String, CodingKey {
    case operation, entity, query, offset
    case artistContextIDs = "artistContextIds"
    case concertContextID = "concertContextId"
  }
}

struct CatalogGatewayResolveRequest: Encodable, Equatable, Sendable {
  let operation = "resolve"
  let entity: CatalogEntityKind
  let musicBrainzID: UUID

  enum CodingKeys: String, CodingKey {
    case operation, entity
    case musicBrainzID = "musicBrainzId"
  }
}

private struct CatalogGatewaySearchResponse: Decodable, Sendable {
  let operation: String
  let entity: CatalogEntityKind
  let offset: Int
  let limit: Int
  let hasMore: Bool
  let isPartial: Bool
  let results: [CatalogResult]
}

private struct CatalogGatewayResolveResponse: Decodable, Sendable {
  let operation: String
  let entity: CatalogResult
}

private struct CatalogGatewayErrorEnvelope: Decodable, Sendable {
  struct Detail: Decodable, Sendable {
    let code: String
    let message: String
    let retryable: Bool
    let retryAfterSeconds: Double?
  }

  let error: Detail
}

enum CatalogGatewayErrorCopy {
  static func message(code: String, fallback: String) -> String {
    switch code {
    case "upstream_timeout":
      "Search took too long. Please try again."
    case "upstream_rate_limited", "queue_timeout":
      "Search is busy. Please try again shortly."
    case "upstream_unavailable":
      "Search is temporarily unavailable."
    case "upstream_invalid_response":
      "Search returned an unexpected response. Please try again."
    default:
      fallback.localizedCaseInsensitiveContains("musicbrainz")
        ? "Search could not be completed. Please try again."
        : fallback
    }
  }
}

private struct CatalogCustomRPCRecord: Decodable, Sendable {
  let catalogID: UUID
  let origin: CatalogOrigin
  let musicBrainzID: UUID?
  let displayName: String
  let sortName: String?
  let disambiguation: String?
  let subtitle: String?
  let metadata: [String: CatalogJSONValue]

  enum CodingKeys: String, CodingKey {
    case origin, disambiguation, subtitle, metadata
    case catalogID = "catalog_id"
    case musicBrainzID = "musicbrainz_id"
    case displayName = "display_name"
    case sortName = "sort_name"
  }

  func catalogResult(kind: CatalogEntityKind) -> CatalogResult {
    CatalogResult(
      source: .tunedIn,
      origin: origin,
      kind: kind,
      catalogID: catalogID,
      musicBrainzID: musicBrainzID,
      displayName: displayName,
      sortName: sortName,
      disambiguation: disambiguation,
      subtitle: subtitle,
      metadata: metadata
    )
  }
}

struct CustomArtistParameters: Encodable, Sendable {
  let name: String
  let artistType: String?
  let disambiguation: String?
  let areaID: UUID?
  let concertContextID: UUID?

  init(input: CustomCatalogArtistInput) {
    name = CatalogInput.normalizedText(input.name)
    artistType = input.artistType
    disambiguation = input.disambiguation.flatMap(CatalogInput.optionalNormalizedText)
    areaID = input.areaID
    concertContextID = input.concertContextID
  }

  enum CodingKeys: String, CodingKey {
    case name = "p_name"
    case artistType = "p_artist_type"
    case disambiguation = "p_disambiguation"
    case areaID = "p_area_id"
    case concertContextID = "p_concert_id"
  }
}

struct CustomAreaParameters: Encodable, Sendable {
  let name: String
  let countryCode: String?
  let parentAreaID: UUID?
  let concertContextID: UUID?

  init(input: CustomCatalogAreaInput) {
    name = CatalogInput.normalizedText(input.name)
    countryCode = input.countryCode.flatMap(CatalogInput.optionalNormalizedText)
    parentAreaID = input.parentAreaID
    concertContextID = input.concertContextID
  }

  enum CodingKeys: String, CodingKey {
    case name = "p_name"
    case countryCode = "p_country_code"
    case parentAreaID = "p_parent_area_id"
    case concertContextID = "p_concert_id"
  }
}

struct CustomPlaceParameters: Encodable, Sendable {
  let name: String
  let placeType: String?
  let address: String?
  let areaID: UUID
  let concertContextID: UUID?

  init(input: CustomCatalogPlaceInput) {
    name = CatalogInput.normalizedText(input.name)
    placeType = input.placeType
    address = input.address.flatMap(CatalogInput.optionalNormalizedText)
    areaID = input.areaID
    concertContextID = input.concertContextID
  }

  enum CodingKeys: String, CodingKey {
    case name = "p_name"
    case placeType = "p_place_type"
    case address = "p_address"
    case areaID = "p_area_id"
    case concertContextID = "p_concert_id"
  }
}

struct CustomSongParameters: Encodable, Sendable {
  let title: String
  let artistIDs: [UUID]
  let concertContextID: UUID?

  init(input: CustomCatalogSongInput) {
    title = CatalogInput.normalizedText(input.title)
    artistIDs = input.artistIDs
    concertContextID = input.concertContextID
  }

  enum CodingKeys: String, CodingKey {
    case title = "p_title"
    case artistIDs = "p_artist_ids"
    case concertContextID = "p_concert_id"
  }
}

struct CustomTourParameters: Encodable, Sendable {
  let name: String
  let artistIDs: [UUID]
  let concertContextID: UUID?

  init(input: CustomCatalogTourInput) {
    name = CatalogInput.normalizedText(input.name)
    artistIDs = input.artistIDs
    concertContextID = input.concertContextID
  }

  enum CodingKeys: String, CodingKey {
    case name = "p_name"
    case artistIDs = "p_artist_ids"
    case concertContextID = "p_concert_id"
  }
}
