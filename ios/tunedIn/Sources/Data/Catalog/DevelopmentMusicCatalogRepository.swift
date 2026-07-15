import Foundation

#if DEBUG
  enum DevelopmentMusicCatalogFixture {
    static let mitskiID = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
    static let vampireWeekendID = UUID(uuidString: "10000000-0000-0000-0000-000000000002")!
    static let bigThiefID = UUID(uuidString: "10000000-0000-0000-0000-000000000003")!
    static let greekTheatreBerkeleyID = UUID(uuidString: "20000000-0000-0000-0000-000000000001")!
    static let masonicID = UUID(uuidString: "20000000-0000-0000-0000-000000000002")!
    static let berkeleyAreaID = UUID(uuidString: "30000000-0000-0000-0000-000000000001")!
    static let sanFranciscoAreaID = UUID(uuidString: "30000000-0000-0000-0000-000000000002")!
    static let firstLoveID = UUID(uuidString: "40000000-0000-0000-0000-000000000001")!
    static let myLoveID = UUID(uuidString: "40000000-0000-0000-0000-000000000002")!
    static let heavenID = UUID(uuidString: "40000000-0000-0000-0000-000000000003")!
    static let landTourID = UUID(uuidString: "50000000-0000-0000-0000-000000000001")!
  }

  actor DevelopmentMusicCatalogRepository: MusicCatalogRepository {
    private var entries: [CatalogEntity]
    private var candidateResolutions: [UUID: CatalogEntity]
    private var nextCustomID = 1

    init() {
      let fixtures = Self.makeFixtures()
      entries = fixtures.entries
      candidateResolutions = fixtures.candidateResolutions
    }

    func entity(id: UUID) -> CatalogEntity? {
      entries.first(where: { $0.id == id })
    }

    func search(
      kind: CatalogEntityKind,
      query: String,
      offset: Int,
      artistContextIDs: [UUID],
      concertContextID _: UUID?
    ) async throws -> CatalogSearchPage {
      let normalized = CatalogInput.normalizedText(query).lowercased()
      guard normalized.count >= 2 else {
        throw MusicCatalogError.rejected(message: "Enter at least two characters to search.", retryable: false)
      }
      if normalized == "offline" {
        throw MusicCatalogError.offline
      }
      if normalized == "rate limit" {
        throw MusicCatalogError.rateLimited(retryAfterSeconds: 3)
      }
      if normalized == "failure" {
        throw MusicCatalogError.rejected(message: "The development catalog is unavailable.", retryable: true)
      }

      var matches = entries
        .filter { $0.kind == kind && $0.displayName.lowercased().contains(normalized) }
        .map(Self.result(for:))

      matches += Self.musicBrainzCandidates(kind: kind).filter {
        $0.displayName.lowercased().contains(normalized)
          || ($0.subtitle?.lowercased().contains(normalized) ?? false)
      }

      if !artistContextIDs.isEmpty, kind == .song || kind == .tour {
        let context = Set(artistContextIDs)
        matches.sort { lhs, rhs in
          let lhsMatches = lhs.metadata.artistCatalogIDs().contains(where: context.contains)
          let rhsMatches = rhs.metadata.artistCatalogIDs().contains(where: context.contains)
          return lhsMatches && !rhsMatches
        }
      }

      let safeOffset = max(0, offset)
      let end = min(matches.count, safeOffset + CatalogSearchPage.limit)
      let pageResults = safeOffset < end ? Array(matches[safeOffset ..< end]) : []
      return CatalogSearchPage(
        kind: kind,
        offset: safeOffset,
        hasMore: end < matches.count,
        results: pageResults
      )
    }

    func resolve(_ candidate: CatalogResult) async throws -> CatalogEntity {
      if candidate.catalogID != nil {
        return try CatalogEntity(resolved: candidate)
      }
      guard
        let musicBrainzID = candidate.musicBrainzID,
        let resolved = candidateResolutions[musicBrainzID],
        resolved.kind == candidate.kind
      else {
        throw MusicCatalogError.unresolvedCandidate
      }
      if !entries.contains(where: { $0.id == resolved.id }) {
        entries.append(resolved)
      }
      return resolved
    }

    func createCustomArtist(_ input: CustomCatalogArtistInput) async throws -> CatalogArtist {
      try validateName(input.name)
      if let existing = entries.compactMap(\.artist).first(where: {
        $0.origin == .tunedInCustom && namesMatch($0.displayName, input.name)
          && $0.artistType == input.artistType && $0.areaID == input.areaID
          && $0.disambiguation == input.disambiguation.flatMap(CatalogInput.optionalNormalizedText)
      }) {
        return existing
      }
      let artist = CatalogArtist(
        id: makeCustomID(kind: .artist),
        origin: .tunedInCustom,
        musicBrainzID: nil,
        displayName: CatalogInput.normalizedText(input.name),
        sortName: nil,
        disambiguation: input.disambiguation.flatMap(CatalogInput.optionalNormalizedText),
        subtitle: input.artistType,
        artistType: input.artistType,
        areaID: input.areaID,
        areaName: input.areaName ?? areaName(for: input.areaID)
      )
      entries.append(.artist(artist))
      return artist
    }

    func createCustomArea(_ input: CustomCatalogAreaInput) async throws -> CatalogArea {
      try validateName(input.name)
      if let existing = entries.compactMap(\.area).first(where: {
        $0.origin == .tunedInCustom && namesMatch($0.displayName, input.name)
          && $0.countryCode == input.countryCode && $0.parentAreaID == input.parentAreaID
      }) {
        return existing
      }
      let area = CatalogArea(
        id: makeCustomID(kind: .area),
        origin: .tunedInCustom,
        musicBrainzID: nil,
        displayName: CatalogInput.normalizedText(input.name),
        sortName: nil,
        disambiguation: nil,
        subtitle: input.countryCode,
        areaType: nil,
        countryCode: input.countryCode,
        parentAreaID: input.parentAreaID
      )
      entries.append(.area(area))
      return area
    }

    func createCustomPlace(_ input: CustomCatalogPlaceInput) async throws -> CatalogPlace {
      try validateName(input.name)
      guard let area = entries.compactMap(\.area).first(where: { $0.id == input.areaID }) else {
        throw MusicCatalogError.rejected(message: "Choose a city or area first.", retryable: false)
      }
      if let existing = entries.compactMap(\.place).first(where: {
        $0.origin == .tunedInCustom && namesMatch($0.displayName, input.name) && $0.areaID == input.areaID
      }) {
        return existing
      }
      let place = CatalogPlace(
        id: makeCustomID(kind: .place),
        origin: .tunedInCustom,
        musicBrainzID: nil,
        displayName: CatalogInput.normalizedText(input.name),
        sortName: nil,
        disambiguation: nil,
        subtitle: [area.displayName, input.address.flatMap(CatalogInput.optionalNormalizedText)]
          .compactMap(\.self).joined(separator: " · "),
        placeType: input.placeType,
        address: input.address.flatMap(CatalogInput.optionalNormalizedText),
        areaID: area.id,
        areaName: area.displayName
      )
      entries.append(.place(place))
      return place
    }

    func createCustomSong(_ input: CustomCatalogSongInput) async throws -> CatalogSong {
      try validateName(input.title)
      var artists: [CatalogArtist] = []
      for id in input.artistIDs {
        guard let artist = entries.compactMap(\.artist).first(where: { $0.id == id }) else {
          throw MusicCatalogError.rejected(message: "Choose at least one artist for this song.", retryable: false)
        }
        artists.append(artist)
      }
      guard !artists.isEmpty else {
        throw MusicCatalogError.rejected(message: "Choose at least one artist for this song.", retryable: false)
      }
      if let existing = entries.compactMap(\.song).first(where: {
        $0.origin == .tunedInCustom && namesMatch($0.displayName, input.title)
          && $0.artistIDs == input.artistIDs
      }) {
        return existing
      }
      let artistNames = input.artistNames.isEmpty ? artists.map(\.displayName) : input.artistNames
      let artistCredit = artistNames.joined(separator: ", ")
      let song = CatalogSong(
        id: makeCustomID(kind: .song),
        origin: .tunedInCustom,
        musicBrainzID: nil,
        displayName: CatalogInput.normalizedText(input.title),
        sortName: nil,
        disambiguation: nil,
        subtitle: artistCredit,
        artistCredit: artistCredit,
        artistIDs: input.artistIDs,
        firstReleaseDate: nil,
        workMusicBrainzID: nil
      )
      entries.append(.song(song))
      return song
    }

    func createCustomTour(_ input: CustomCatalogTourInput) async throws -> CatalogTour {
      try validateName(input.name)
      var artists: [CatalogArtist] = []
      for id in input.artistIDs {
        guard let artist = entries.compactMap(\.artist).first(where: { $0.id == id }) else {
          throw MusicCatalogError.rejected(message: "Choose at least one artist for this tour.", retryable: false)
        }
        artists.append(artist)
      }
      guard !artists.isEmpty else {
        throw MusicCatalogError.rejected(message: "Choose at least one artist for this tour.", retryable: false)
      }
      if let existing = entries.compactMap(\.tour).first(where: {
        $0.origin == .tunedInCustom && namesMatch($0.displayName, input.name)
          && $0.artistIDs == input.artistIDs
      }) {
        return existing
      }
      let artistNames = input.artistNames.isEmpty ? artists.map(\.displayName) : input.artistNames
      let artistCredit = artistNames.joined(separator: ", ")
      let tour = CatalogTour(
        id: makeCustomID(kind: .tour),
        origin: .tunedInCustom,
        musicBrainzID: nil,
        displayName: CatalogInput.normalizedText(input.name),
        sortName: nil,
        disambiguation: nil,
        subtitle: artistCredit,
        artistCredit: artistCredit,
        artistIDs: input.artistIDs
      )
      entries.append(.tour(tour))
      return tour
    }

    private func validateName(_ name: String) throws {
      guard CatalogInput.isValidName(name) else {
        throw MusicCatalogError.rejected(message: "Enter a valid name.", retryable: false)
      }
    }

    private func namesMatch(_ lhs: String, _ rhs: String) -> Bool {
      lhs.localizedCaseInsensitiveCompare(CatalogInput.normalizedText(rhs)) == .orderedSame
    }

    private func areaName(for id: UUID?) -> String? {
      entries.compactMap(\.area).first(where: { $0.id == id })?.displayName
    }

    private func makeCustomID(kind: CatalogEntityKind) -> UUID {
      let prefix = switch kind {
      case .artist: 61
      case .area: 62
      case .place: 63
      case .song: 64
      case .tour: 65
      }
      defer { nextCustomID += 1 }
      return UUID(uuidString: String(format: "%08d-0000-0000-0000-%012d", prefix, nextCustomID))!
    }
  }

  private extension DevelopmentMusicCatalogRepository {
    static func result(for entity: CatalogEntity) -> CatalogResult {
      switch entity {
      case let .artist(value):
        CatalogResult(
          source: .tunedIn, origin: value.origin, kind: .artist, catalogID: value.id,
          musicBrainzID: value.musicBrainzID, displayName: value.displayName,
          sortName: value.sortName, disambiguation: value.disambiguation,
          subtitle: value.subtitle,
          metadata: metadata(values: [
            "artistType": value.artistType.map(CatalogJSONValue.string),
            "countryCode": nil,
            "areaCatalogId": value.areaID.map { .string($0.uuidString) },
            "areaMusicBrainzId": nil,
            "areaName": value.areaName.map(CatalogJSONValue.string),
            "lifeSpanBegin": nil,
            "lifeSpanEnd": nil,
            "ended": nil
          ])
        )
      case let .area(value):
        CatalogResult(
          source: .tunedIn, origin: value.origin, kind: .area, catalogID: value.id,
          musicBrainzID: value.musicBrainzID, displayName: value.displayName,
          sortName: value.sortName, disambiguation: value.disambiguation,
          subtitle: value.subtitle,
          metadata: metadata(values: [
            "areaType": value.areaType.map(CatalogJSONValue.string),
            "countryCode": value.countryCode.map(CatalogJSONValue.string),
            "subdivisionCode": nil,
            "parentAreaCatalogId": value.parentAreaID.map { .string($0.uuidString) },
            "parentMusicBrainzId": nil,
            "parentName": nil
          ])
        )
      case let .place(value):
        CatalogResult(
          source: .tunedIn, origin: value.origin, kind: .place, catalogID: value.id,
          musicBrainzID: value.musicBrainzID, displayName: value.displayName,
          sortName: value.sortName, disambiguation: value.disambiguation,
          subtitle: value.subtitle,
          metadata: metadata(values: [
            "placeType": value.placeType.map(CatalogJSONValue.string),
            "address": value.address.map(CatalogJSONValue.string),
            "latitude": nil,
            "longitude": nil,
            "ended": nil,
            "areaCatalogId": value.areaID.map { .string($0.uuidString) },
            "areaMusicBrainzId": nil,
            "areaName": value.areaName.map(CatalogJSONValue.string)
          ])
        )
      case let .song(value):
        CatalogResult(
          source: .tunedIn, origin: value.origin, kind: .song, catalogID: value.id,
          musicBrainzID: value.musicBrainzID, displayName: value.displayName,
          sortName: value.sortName, disambiguation: value.disambiguation,
          subtitle: value.subtitle,
          metadata: metadata(values: [
            "workMusicBrainzId": value.workMusicBrainzID.map { .string($0.uuidString) },
            "durationMs": nil,
            "firstReleaseDate": value.firstReleaseDate.map(CatalogJSONValue.string),
            "artistCredit": creditMetadata(ids: value.artistIDs, label: value.artistCredit)
          ])
        )
      case let .tour(value):
        CatalogResult(
          source: .tunedIn, origin: value.origin, kind: .tour, catalogID: value.id,
          musicBrainzID: value.musicBrainzID, displayName: value.displayName,
          sortName: value.sortName, disambiguation: value.disambiguation,
          subtitle: value.subtitle,
          metadata: metadata(values: [
            "seriesType": .string("Tour"),
            "disambiguation": value.disambiguation.map(CatalogJSONValue.string),
            "artistCredit": creditMetadata(ids: value.artistIDs, label: value.artistCredit)
          ])
        )
      }
    }

    static func metadata(values: [String: CatalogJSONValue?]) -> [String: CatalogJSONValue] {
      values.mapValues { $0 ?? .null }
    }

    static func creditMetadata(ids: [UUID], label: String?) -> CatalogJSONValue? {
      guard !ids.isEmpty else { return nil }
      let names = label?.components(separatedBy: ", ") ?? []
      return .array(ids.enumerated().map { index, id in
        .object([
          "artistCatalogId": .string(id.uuidString),
          "artistMusicBrainzId": .null,
          "name": .string(index < names.count ? names[index] : (label ?? "Artist")),
          "canonicalName": .string(index < names.count ? names[index] : (label ?? "Artist")),
          "joinPhrase": .string(index == ids.count - 1 ? "" : ", ")
        ])
      })
    }

    static func makeFixtures() -> (entries: [CatalogEntity], candidateResolutions: [UUID: CatalogEntity]) {
      let berkeley = CatalogArea(
        id: DevelopmentMusicCatalogFixture.berkeleyAreaID, origin: .musicBrainz,
        musicBrainzID: UUID(uuidString: "e635b944-3e6f-4ad6-b91e-4500ba9c6a1f"),
        displayName: "Berkeley", sortName: "Berkeley", disambiguation: "California, United States",
        subtitle: "California, United States", areaType: "City", countryCode: "US", parentAreaID: nil
      )
      let sanFrancisco = CatalogArea(
        id: DevelopmentMusicCatalogFixture.sanFranciscoAreaID, origin: .musicBrainz,
        musicBrainzID: UUID(uuidString: "23b2c290-aaed-4a3f-a9cb-5f2c7de8f2e0"),
        displayName: "San Francisco", sortName: "San Francisco", disambiguation: "California, United States",
        subtitle: "California, United States", areaType: "City", countryCode: "US", parentAreaID: nil
      )
      let mitski = CatalogArtist(
        id: DevelopmentMusicCatalogFixture.mitskiID, origin: .musicBrainz,
        musicBrainzID: UUID(uuidString: "87b69f18-ea9f-4cc7-a22d-7b7545d9c19d"),
        displayName: "Mitski", sortName: "Mitski", disambiguation: "Japanese-American singer-songwriter",
        subtitle: "Person · United States", artistType: "Person", areaID: nil, areaName: "United States"
      )
      let vampireWeekend = CatalogArtist(
        id: DevelopmentMusicCatalogFixture.vampireWeekendID, origin: .musicBrainz,
        musicBrainzID: UUID(uuidString: "af37c51c-0790-4a29-b995-456f98a6b8c9"),
        displayName: "Vampire Weekend", sortName: "Vampire Weekend", disambiguation: nil,
        subtitle: "Group · New York", artistType: "Group", areaID: nil, areaName: "New York"
      )
      let bigThief = CatalogArtist(
        id: DevelopmentMusicCatalogFixture.bigThiefID, origin: .musicBrainz,
        musicBrainzID: UUID(uuidString: "b8a7c51f-362c-4dcb-a259-bc6e0e1ad2f9"),
        displayName: "Big Thief", sortName: "Big Thief", disambiguation: nil,
        subtitle: "Group · Brooklyn", artistType: "Group", areaID: nil, areaName: "Brooklyn"
      )
      let greek = CatalogPlace(
        id: DevelopmentMusicCatalogFixture.greekTheatreBerkeleyID, origin: .musicBrainz,
        musicBrainzID: UUID(uuidString: "3f1a2ae6-1f55-447d-8d3e-2d22ca9bb071"),
        displayName: "The Greek Theatre", sortName: "Greek Theatre, The", disambiguation: "UC Berkeley",
        subtitle: "Berkeley · Amphitheatre", placeType: "Amphitheatre", address: "2001 Gayley Road",
        areaID: berkeley.id, areaName: berkeley.displayName
      )
      let masonic = CatalogPlace(
        id: DevelopmentMusicCatalogFixture.masonicID, origin: .musicBrainz,
        musicBrainzID: UUID(uuidString: "2d1520b9-cced-43e7-8abf-aed6e445c106"),
        displayName: "The Masonic", sortName: "Masonic, The", disambiguation: nil,
        subtitle: "San Francisco · Hall", placeType: "Hall", address: "1111 California Street",
        areaID: sanFrancisco.id, areaName: sanFrancisco.displayName
      )
      let firstLove = CatalogSong(
        id: DevelopmentMusicCatalogFixture.firstLoveID, origin: .musicBrainz,
        musicBrainzID: UUID(uuidString: "67746196-1c25-43ab-bc36-f73b23dcb2d9"),
        displayName: "First Love / Late Spring", sortName: nil, disambiguation: nil,
        subtitle: "Mitski · 2014", artistCredit: "Mitski", artistIDs: [mitski.id],
        firstReleaseDate: "2014", workMusicBrainzID: nil
      )
      let myLove = CatalogSong(
        id: DevelopmentMusicCatalogFixture.myLoveID, origin: .musicBrainz,
        musicBrainzID: UUID(uuidString: "7ce012ea-64e4-4e5f-9275-c0313e84c21b"),
        displayName: "My Love Mine All Mine", sortName: nil, disambiguation: nil,
        subtitle: "Mitski · 2023", artistCredit: "Mitski", artistIDs: [mitski.id],
        firstReleaseDate: "2023", workMusicBrainzID: nil
      )
      let heaven = CatalogSong(
        id: DevelopmentMusicCatalogFixture.heavenID, origin: .musicBrainz,
        musicBrainzID: UUID(uuidString: "e5a8fd87-5a9e-4336-96e8-762b5c785ea8"),
        displayName: "Heaven", sortName: nil, disambiguation: nil,
        subtitle: "Mitski · 2023", artistCredit: "Mitski", artistIDs: [mitski.id],
        firstReleaseDate: "2023", workMusicBrainzID: nil
      )
      let tour = CatalogTour(
        id: DevelopmentMusicCatalogFixture.landTourID, origin: .musicBrainz,
        musicBrainzID: UUID(uuidString: "56d4c55d-4e64-45d8-8720-4d0c2a3d5599"),
        displayName: "The Land Is Inhospitable Tour", sortName: nil, disambiguation: nil,
        subtitle: "Mitski", artistCredit: "Mitski", artistIDs: [mitski.id]
      )
      let entries: [CatalogEntity] = [
        .area(berkeley), .area(sanFrancisco), .artist(mitski), .artist(vampireWeekend), .artist(bigThief),
        .place(greek), .place(masonic), .song(firstLove), .song(myLove), .song(heaven), .tour(tour)
      ]

      let phoenixBandMBID = UUID(uuidString: "d25d050c-c59f-11d9-9669-0800200c9a66")!
      let phoenixSingerMBID = UUID(uuidString: "8c42c308-0a3e-4a7f-847b-14fb27d22e75")!
      let phoenixBand = CatalogEntity.artist(
        CatalogArtist(
          id: UUID(uuidString: "10000000-0000-0000-0000-000000000010")!, origin: .musicBrainz,
          musicBrainzID: phoenixBandMBID, displayName: "Phoenix", sortName: "Phoenix",
          disambiguation: "French indie pop band", subtitle: "Group · Versailles, France",
          artistType: "Group", areaID: nil, areaName: "Versailles"
        )
      )
      let phoenixSinger = CatalogEntity.artist(
        CatalogArtist(
          id: UUID(uuidString: "10000000-0000-0000-0000-000000000011")!, origin: .musicBrainz,
          musicBrainzID: phoenixSingerMBID, displayName: "Phoenix", sortName: "Phoenix",
          disambiguation: "Romanian singer", subtitle: "Person · Romania",
          artistType: "Person", areaID: nil, areaName: "Romania"
        )
      )
      return (entries, [phoenixBandMBID: phoenixBand, phoenixSingerMBID: phoenixSinger])
    }

    static func musicBrainzCandidates(kind: CatalogEntityKind) -> [CatalogResult] {
      guard kind == .artist else { return [] }
      return makeFixtures().candidateResolutions.values.map { entity in
        var result = result(for: entity)
        return CatalogResult(
          source: .musicBrainz, origin: .musicBrainz, kind: result.kind, catalogID: nil,
          musicBrainzID: result.musicBrainzID, displayName: result.displayName,
          sortName: result.sortName, disambiguation: result.disambiguation,
          subtitle: result.subtitle, metadata: result.metadata
        )
      }
    }
  }

  private extension CatalogEntity {
    var artist: CatalogArtist? {
      guard case let .artist(value) = self else { return nil }
      return value
    }

    var area: CatalogArea? {
      guard case let .area(value) = self else { return nil }
      return value
    }

    var place: CatalogPlace? {
      guard case let .place(value) = self else { return nil }
      return value
    }

    var song: CatalogSong? {
      guard case let .song(value) = self else { return nil }
      return value
    }

    var tour: CatalogTour? {
      guard case let .tour(value) = self else { return nil }
      return value
    }
  }
#endif
