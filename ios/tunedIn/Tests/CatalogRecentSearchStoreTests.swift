import Foundation
import Testing
@testable import tunedIn

struct CatalogRecentSearchStoreTests {
  @Test
  func recentSearchesAreNewestFirstDeduplicatedAndScopedByKind() throws {
    let suiteName = "CatalogRecentSearchStoreTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }

    _ = CatalogRecentSearchStore.record("Waxahatchee", for: .artist, defaults: defaults)
    _ = CatalogRecentSearchStore.record("The National", for: .artist, defaults: defaults)
    _ = CatalogRecentSearchStore.record(" waxahatchee ", for: .artist, defaults: defaults)
    _ = CatalogRecentSearchStore.record("The Wiltern", for: .place, defaults: defaults)

    #expect(
      CatalogRecentSearchStore.values(for: .artist, defaults: defaults)
        == ["waxahatchee", "The National"]
    )
    #expect(
      CatalogRecentSearchStore.values(for: .place, defaults: defaults)
        == ["The Wiltern"]
    )
  }

  @Test
  func recentSearchesKeepOnlyFiveValues() throws {
    let suiteName = "CatalogRecentSearchStoreTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }

    for index in 1 ... 6 {
      _ = CatalogRecentSearchStore.record("Artist \(index)", for: .artist, defaults: defaults)
    }

    #expect(
      CatalogRecentSearchStore.values(for: .artist, defaults: defaults)
        == ["Artist 6", "Artist 5", "Artist 4", "Artist 3", "Artist 2"]
    )
  }
}
