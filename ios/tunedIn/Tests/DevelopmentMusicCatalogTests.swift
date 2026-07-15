import Foundation
import Testing
@testable import tunedIn

#if DEBUG
  struct DevelopmentMusicCatalogRepositoryTests {
    @Test
    func searchMetadataUsesProductionShapesWithoutTransportFields() async throws {
      let repository = DevelopmentMusicCatalogRepository()
      let cases: [(CatalogEntityKind, String, Set<String>)] = [
        (
          .artist, "Mitski",
          [
            "artistType", "countryCode", "areaCatalogId", "areaMusicBrainzId", "areaName",
            "lifeSpanBegin", "lifeSpanEnd", "ended"
          ]
        ),
        (
          .area, "Berkeley",
          [
            "areaType", "countryCode", "subdivisionCode", "parentAreaCatalogId",
            "parentMusicBrainzId", "parentName"
          ]
        ),
        (
          .place, "Greek",
          [
            "placeType", "address", "latitude", "longitude", "ended", "areaCatalogId",
            "areaMusicBrainzId", "areaName"
          ]
        ),
        (
          .song, "First Love",
          ["workMusicBrainzId", "durationMs", "firstReleaseDate", "artistCredit"]
        ),
        (.tour, "Land", ["seriesType", "disambiguation", "artistCredit"])
      ]

      for (kind, query, expectedKeys) in cases {
        let page = try await repository.search(
          kind: kind, query: query, offset: 0, artistContextIDs: [], concertContextID: nil
        )
        let result = try #require(page.results.first)
        #expect(Set(result.metadata.keys) == expectedKeys)
        #expect(result.metadata["origin"] == nil)
      }
    }

    @Test
    func customEntriesDeduplicateUsingStructuredContextAndPreserveArtistOrder() async throws {
      let repository = DevelopmentMusicCatalogRepository()
      let first = try await repository.createCustomArtist(
        CustomCatalogArtistInput(
          name: "Same Name", artistType: "Person", disambiguation: "solo artist",
          areaID: DevelopmentMusicCatalogFixture.berkeleyAreaID, areaName: "Berkeley"
        )
      )
      let duplicate = try await repository.createCustomArtist(
        CustomCatalogArtistInput(
          name: " Same   Name ", artistType: "Person", disambiguation: " solo   artist ",
          areaID: DevelopmentMusicCatalogFixture.berkeleyAreaID, areaName: "Berkeley"
        )
      )
      let distinctType = try await repository.createCustomArtist(
        CustomCatalogArtistInput(
          name: "Same Name", artistType: "Group", disambiguation: nil,
          areaID: DevelopmentMusicCatalogFixture.berkeleyAreaID, areaName: "Berkeley"
        )
      )
      #expect(first.id == duplicate.id)
      #expect(first.id != distinctType.id)

      let distinctDisambiguation = try await repository.createCustomArtist(
        CustomCatalogArtistInput(
          name: "Same Name", artistType: "Person", disambiguation: "tribute act",
          areaID: DevelopmentMusicCatalogFixture.berkeleyAreaID, areaName: "Berkeley"
        )
      )
      #expect(first.id != distinctDisambiguation.id)

      let tour = try await repository.createCustomTour(
        CustomCatalogTourInput(
          name: "Shared Tour",
          artistIDs: [distinctType.id, first.id],
          artistNames: [distinctType.displayName, first.displayName]
        )
      )
      #expect(tour.artistIDs == [distinctType.id, first.id])
    }
  }
#endif
