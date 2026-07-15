import Foundation
@testable import tunedIn

actor CatalogSearchTestRepository: MusicCatalogRepository {
  private struct PageKey: Hashable {
    let query: String
    let offset: Int
  }

  private struct Page: Sendable {
    let results: [CatalogResult]
    let hasMore: Bool
  }

  private var pages: [PageKey: Page] = [:]
  private var errors: [String: MusicCatalogError] = [:]
  private var pageErrors: [PageKey: MusicCatalogError] = [:]
  private var delays: [String: Duration] = [:]
  private var resolutions: [UUID: CatalogEntity] = [:]
  private var resolutionDelay: Duration?
  private(set) var resolveCallCount = 0
  private(set) var searchOffsets: [Int] = []
  private(set) var searchArtistContexts: [[UUID]] = []

  func setResults(_ results: [CatalogResult], for query: String) {
    setPage(results, query: query, offset: 0, hasMore: false)
  }

  func setPage(_ results: [CatalogResult], query: String, offset: Int, hasMore: Bool) {
    pages[PageKey(query: query, offset: offset)] = Page(results: results, hasMore: hasMore)
  }

  func setError(_ error: MusicCatalogError, for query: String) {
    errors[query] = error
  }

  func setPageError(_ error: MusicCatalogError, query: String, offset: Int) {
    pageErrors[PageKey(query: query, offset: offset)] = error
  }

  func setDelay(_ delay: Duration, for query: String) {
    delays[query] = delay
  }

  func setResolved(_ entity: CatalogEntity, for musicBrainzID: UUID) {
    resolutions[musicBrainzID] = entity
  }

  func setResolutionDelay(_ delay: Duration) {
    resolutionDelay = delay
  }

  func search(
    kind: CatalogEntityKind,
    query: String,
    offset: Int,
    artistContextIDs: [UUID],
    concertContextID _: UUID?
  ) async throws -> CatalogSearchPage {
    searchOffsets.append(offset)
    searchArtistContexts.append(artistContextIDs)
    if let delay = delays[query] {
      try? await Task.sleep(for: delay)
    }
    if let error = errors[query] {
      throw error
    }
    if let error = pageErrors[PageKey(query: query, offset: offset)] {
      throw error
    }
    let page = pages[PageKey(query: query, offset: offset)] ?? Page(results: [], hasMore: false)
    return CatalogSearchPage(kind: kind, offset: offset, hasMore: page.hasMore, results: page.results)
  }

  func resolve(_ candidate: CatalogResult) async throws -> CatalogEntity {
    resolveCallCount += 1
    if let resolutionDelay {
      // Deliberately ignore cancellation to prove the model's generation guard prevents stale selection.
      try? await Task.sleep(for: resolutionDelay)
    }
    if candidate.catalogID != nil, candidate.source == .tunedIn {
      return try CatalogEntity(resolved: candidate)
    }
    guard let musicBrainzID = candidate.musicBrainzID, let entity = resolutions[musicBrainzID] else {
      throw MusicCatalogError.unresolvedCandidate
    }
    return entity
  }

  func createCustomArtist(_: CustomCatalogArtistInput) async throws -> CatalogArtist {
    throw MusicCatalogError.invalidResponse
  }

  func createCustomArea(_: CustomCatalogAreaInput) async throws -> CatalogArea {
    throw MusicCatalogError.invalidResponse
  }

  func createCustomPlace(_: CustomCatalogPlaceInput) async throws -> CatalogPlace {
    throw MusicCatalogError.invalidResponse
  }

  func createCustomSong(_: CustomCatalogSongInput) async throws -> CatalogSong {
    throw MusicCatalogError.invalidResponse
  }

  func createCustomTour(_: CustomCatalogTourInput) async throws -> CatalogTour {
    throw MusicCatalogError.invalidResponse
  }
}
