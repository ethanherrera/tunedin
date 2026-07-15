import Foundation

enum CatalogEntityKind: String, CaseIterable, Codable, Equatable, Sendable {
  case artist
  case area
  case place
  case song
  case tour

  var singularTitle: String {
    switch self {
    case .artist: "Artist"
    case .area: "City or area"
    case .place: "Venue"
    case .song: "Song"
    case .tour: "Tour"
    }
  }

  var searchPrompt: String {
    switch self {
    case .artist: "Search artists"
    case .area: "Search cities and areas"
    case .place: "Search venues"
    case .song: "Search songs"
    case .tour: "Search tours"
    }
  }
}

enum CatalogSource: String, Codable, Equatable, Sendable {
  case tunedIn = "tunedin"
  case musicBrainz = "musicbrainz"
}

enum CatalogOrigin: String, Codable, Equatable, Sendable {
  case musicBrainz = "musicbrainz"
  case tunedInCustom = "tunedin_custom"
  case legacyImport = "legacy_import"
  case legacyClient = "legacy_client"
}

/// The gateway intentionally returns entity-specific metadata as a JSON object.
/// Keeping that transport detail in an app-owned value prevents feature views
/// from depending on MusicBrainz or Supabase response types.
enum CatalogJSONValue: Codable, Equatable, Sendable {
  case string(String)
  case number(Double)
  case boolean(Bool)
  case object([String: CatalogJSONValue])
  case array([CatalogJSONValue])
  case null

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    if container.decodeNil() {
      self = .null
    } else if let value = try? container.decode(Bool.self) {
      self = .boolean(value)
    } else if let value = try? container.decode(Double.self) {
      self = .number(value)
    } else if let value = try? container.decode(String.self) {
      self = .string(value)
    } else if let value = try? container.decode([String: CatalogJSONValue].self) {
      self = .object(value)
    } else if let value = try? container.decode([CatalogJSONValue].self) {
      self = .array(value)
    } else {
      throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported catalog metadata value")
    }
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    switch self {
    case let .string(value): try container.encode(value)
    case let .number(value): try container.encode(value)
    case let .boolean(value): try container.encode(value)
    case let .object(value): try container.encode(value)
    case let .array(value): try container.encode(value)
    case .null: try container.encodeNil()
    }
  }
}

extension [String: CatalogJSONValue] {
  func string(for keys: String...) -> String? {
    for key in keys {
      if case let .string(value)? = self[key], !value.isEmpty {
        return value
      }
    }
    return nil
  }

  func uuid(for keys: String...) -> UUID? {
    for key in keys {
      if case let .string(value)? = self[key], let id = UUID(uuidString: value) {
        return id
      }
    }
    return nil
  }

  func artistCreditLabel() -> String? {
    guard case let .array(credits)? = self["artistCredit"] ?? self["artist_credit"] else {
      return string(for: "artistCreditLabel", "artist_credit_label")
    }
    let label = credits.compactMap { credit -> String? in
      guard case let .object(value) = credit,
            let name = value.string(for: "name")
      else { return nil }
      return name + (value.string(for: "joinPhrase", "join_phrase") ?? "")
    }.joined()
    return label.isEmpty ? nil : label
  }

  func artistCatalogIDs() -> [UUID] {
    guard case let .array(credits)? = self["artistCredit"] ?? self["artist_credit"] else { return [] }
    return credits.compactMap { credit in
      guard case let .object(value) = credit else { return nil }
      return value.uuid(for: "artistCatalogId", "artist_catalog_id")
    }
  }
}

struct CatalogResult: Codable, Equatable, Identifiable, Sendable {
  let source: CatalogSource
  let origin: CatalogOrigin
  let kind: CatalogEntityKind
  let catalogID: UUID?
  let musicBrainzID: UUID?
  let displayName: String
  let sortName: String?
  let disambiguation: String?
  let subtitle: String?
  let metadata: [String: CatalogJSONValue]

  var id: String {
    let identity = catalogID ?? musicBrainzID
    return "\(source.rawValue):\(kind.rawValue):\(identity?.uuidString.lowercased() ?? displayName)"
  }

  var requiresResolution: Bool {
    origin == .musicBrainz || catalogID == nil
  }

  enum CodingKeys: String, CodingKey {
    case source, origin, kind, displayName, sortName, disambiguation, subtitle, metadata
    case catalogID = "catalogId"
    case musicBrainzID = "musicBrainzId"
  }
}

struct CatalogSearchPage: Equatable, Sendable {
  static let limit = 15

  let kind: CatalogEntityKind
  let offset: Int
  let hasMore: Bool
  let isPartial: Bool
  let results: [CatalogResult]

  init(
    kind: CatalogEntityKind,
    offset: Int,
    hasMore: Bool,
    isPartial: Bool = false,
    results: [CatalogResult]
  ) {
    self.kind = kind
    self.offset = offset
    self.hasMore = hasMore
    self.isPartial = isPartial
    self.results = results
  }
}

struct CatalogArtist: Codable, Equatable, Identifiable, Sendable {
  let id: UUID
  let origin: CatalogOrigin
  let musicBrainzID: UUID?
  let displayName: String
  let sortName: String?
  let disambiguation: String?
  let subtitle: String?
  let artistType: String?
  let areaID: UUID?
  let areaName: String?
}

struct CatalogArea: Codable, Equatable, Identifiable, Sendable {
  let id: UUID
  let origin: CatalogOrigin
  let musicBrainzID: UUID?
  let displayName: String
  let sortName: String?
  let disambiguation: String?
  let subtitle: String?
  let areaType: String?
  let countryCode: String?
  let parentAreaID: UUID?
}

struct CatalogPlace: Codable, Equatable, Identifiable, Sendable {
  let id: UUID
  let origin: CatalogOrigin
  let musicBrainzID: UUID?
  let displayName: String
  let sortName: String?
  let disambiguation: String?
  let subtitle: String?
  let placeType: String?
  let address: String?
  let areaID: UUID?
  let areaName: String?
}

struct CatalogSong: Codable, Equatable, Identifiable, Sendable {
  let id: UUID
  let origin: CatalogOrigin
  let musicBrainzID: UUID?
  let displayName: String
  let sortName: String?
  let disambiguation: String?
  let subtitle: String?
  let artistCredit: String?
  let artistIDs: [UUID]
  let firstReleaseDate: String?
  let workMusicBrainzID: UUID?
}

struct CatalogTour: Codable, Equatable, Identifiable, Sendable {
  let id: UUID
  let origin: CatalogOrigin
  let musicBrainzID: UUID?
  let displayName: String
  let sortName: String?
  let disambiguation: String?
  let subtitle: String?
  let artistCredit: String?
  let artistIDs: [UUID]
}

enum CatalogEntity: Equatable, Identifiable, Sendable {
  case artist(CatalogArtist)
  case area(CatalogArea)
  case place(CatalogPlace)
  case song(CatalogSong)
  case tour(CatalogTour)

  var id: UUID {
    switch self {
    case let .artist(value): value.id
    case let .area(value): value.id
    case let .place(value): value.id
    case let .song(value): value.id
    case let .tour(value): value.id
    }
  }

  var kind: CatalogEntityKind {
    switch self {
    case .artist: .artist
    case .area: .area
    case .place: .place
    case .song: .song
    case .tour: .tour
    }
  }

  var displayName: String {
    switch self {
    case let .artist(value): value.displayName
    case let .area(value): value.displayName
    case let .place(value): value.displayName
    case let .song(value): value.displayName
    case let .tour(value): value.displayName
    }
  }

  var musicBrainzID: UUID? {
    switch self {
    case let .artist(value): value.musicBrainzID
    case let .area(value): value.musicBrainzID
    case let .place(value): value.musicBrainzID
    case let .song(value): value.musicBrainzID
    case let .tour(value): value.musicBrainzID
    }
  }
}

extension CatalogEntity {
  init(resolved result: CatalogResult) throws {
    guard let id = result.catalogID else {
      throw MusicCatalogError.invalidResponse
    }
    let origin = result.origin

    switch result.kind {
    case .artist:
      self = .artist(
        CatalogArtist(
          id: id,
          origin: origin,
          musicBrainzID: result.musicBrainzID,
          displayName: result.displayName,
          sortName: result.sortName,
          disambiguation: result.disambiguation,
          subtitle: result.subtitle,
          artistType: result.metadata.string(for: "artistType", "artist_type", "type"),
          areaID: result.metadata.uuid(for: "areaCatalogId", "area_catalog_id"),
          areaName: result.metadata.string(for: "areaName", "area_name", "area")
        )
      )
    case .area:
      self = .area(
        CatalogArea(
          id: id,
          origin: origin,
          musicBrainzID: result.musicBrainzID,
          displayName: result.displayName,
          sortName: result.sortName,
          disambiguation: result.disambiguation,
          subtitle: result.subtitle,
          areaType: result.metadata.string(for: "areaType", "area_type", "type"),
          countryCode: result.metadata.string(for: "countryCode", "country_code"),
          parentAreaID: result.metadata.uuid(for: "parentAreaCatalogId", "parent_area_catalog_id")
        )
      )
    case .place:
      self = .place(
        CatalogPlace(
          id: id,
          origin: origin,
          musicBrainzID: result.musicBrainzID,
          displayName: result.displayName,
          sortName: result.sortName,
          disambiguation: result.disambiguation,
          subtitle: result.subtitle,
          placeType: result.metadata.string(for: "placeType", "place_type", "type"),
          address: result.metadata.string(for: "address"),
          areaID: result.metadata.uuid(for: "areaCatalogId", "area_catalog_id", "areaId", "area_id"),
          areaName: result.metadata.string(for: "areaName", "area_name", "area")
        )
      )
    case .song:
      self = .song(
        CatalogSong(
          id: id,
          origin: origin,
          musicBrainzID: result.musicBrainzID,
          displayName: result.displayName,
          sortName: result.sortName,
          disambiguation: result.disambiguation,
          subtitle: result.subtitle,
          artistCredit: result.metadata.artistCreditLabel(),
          artistIDs: result.metadata.artistCatalogIDs(),
          firstReleaseDate: result.metadata.string(for: "firstReleaseDate", "first_release_date"),
          workMusicBrainzID: result.metadata.uuid(for: "workMusicBrainzId", "work_musicbrainz_id")
        )
      )
    case .tour:
      self = .tour(
        CatalogTour(
          id: id,
          origin: origin,
          musicBrainzID: result.musicBrainzID,
          displayName: result.displayName,
          sortName: result.sortName,
          disambiguation: result.disambiguation,
          subtitle: result.subtitle,
          artistCredit: result.metadata.artistCreditLabel(),
          artistIDs: result.metadata.artistCatalogIDs()
        )
      )
    }
  }
}

struct CustomCatalogArtistInput: Equatable, Sendable {
  let name: String
  let artistType: String?
  let disambiguation: String?
  let areaID: UUID?
  let areaName: String?
  let concertContextID: UUID?

  init(
    name: String,
    artistType: String?,
    disambiguation: String?,
    areaID: UUID?,
    areaName: String?,
    concertContextID: UUID? = nil
  ) {
    self.name = name
    self.artistType = artistType
    self.disambiguation = disambiguation
    self.areaID = areaID
    self.areaName = areaName
    self.concertContextID = concertContextID
  }
}

struct CustomCatalogAreaInput: Equatable, Sendable {
  let name: String
  let countryCode: String?
  let parentAreaID: UUID?
  let concertContextID: UUID?

  init(name: String, countryCode: String?, parentAreaID: UUID?, concertContextID: UUID? = nil) {
    self.name = name
    self.countryCode = countryCode
    self.parentAreaID = parentAreaID
    self.concertContextID = concertContextID
  }
}

struct CustomCatalogPlaceInput: Equatable, Sendable {
  let name: String
  let placeType: String?
  let address: String?
  let areaID: UUID
  let areaName: String
  let concertContextID: UUID?

  init(
    name: String,
    placeType: String?,
    address: String?,
    areaID: UUID,
    areaName: String,
    concertContextID: UUID? = nil
  ) {
    self.name = name
    self.placeType = placeType
    self.address = address
    self.areaID = areaID
    self.areaName = areaName
    self.concertContextID = concertContextID
  }
}

struct CustomCatalogSongInput: Equatable, Sendable {
  let title: String
  let artistIDs: [UUID]
  let artistNames: [String]
  let concertContextID: UUID?

  init(
    title: String,
    artistIDs: [UUID],
    artistNames: [String],
    concertContextID: UUID? = nil
  ) {
    self.title = title
    self.artistIDs = artistIDs
    self.artistNames = artistNames
    self.concertContextID = concertContextID
  }
}

struct CustomCatalogTourInput: Equatable, Sendable {
  let name: String
  let artistIDs: [UUID]
  let artistNames: [String]
  let concertContextID: UUID?

  init(
    name: String,
    artistIDs: [UUID],
    artistNames: [String],
    concertContextID: UUID? = nil
  ) {
    self.name = name
    self.artistIDs = artistIDs
    self.artistNames = artistNames
    self.concertContextID = concertContextID
  }
}

enum MusicCatalogError: Error, Equatable, LocalizedError, Sendable {
  case offline
  case rateLimited(retryAfterSeconds: Double?)
  case rejected(message: String, retryable: Bool)
  case invalidResponse
  case unresolvedCandidate
  case wrongEntityKind

  var errorDescription: String? {
    switch self {
    case .offline:
      "You appear to be offline. Your current selection is still here."
    case let .rateLimited(retryAfterSeconds):
      if let retryAfterSeconds {
        "Music search is busy. Try again in \(max(1, Int(retryAfterSeconds.rounded(.up)))) seconds."
      } else {
        "Music search is busy. Please try again shortly."
      }
    case let .rejected(message, _):
      message
    case .invalidResponse:
      "The catalog returned an unexpected response. Please try again."
    case .unresolvedCandidate:
      "Select a resolved catalog result before saving."
    case .wrongEntityKind:
      "That catalog result is not valid for this field."
    }
  }

  var isRetryable: Bool {
    switch self {
    case .offline, .rateLimited: true
    case let .rejected(_, retryable): retryable
    case .invalidResponse, .unresolvedCandidate, .wrongEntityKind: false
    }
  }
}
