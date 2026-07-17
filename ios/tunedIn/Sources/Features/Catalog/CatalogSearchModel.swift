import Foundation
import Observation

enum CatalogSearchPhase: Equatable, Sendable {
  case idle
  case loading
  case results
  case empty
  case offline
  case rateLimited(retryAfterSeconds: Double?)
  case failed(message: String, retryable: Bool)
}

@MainActor
@Observable
final class CatalogSearchModel {
  var query = ""
  private(set) var phase: CatalogSearchPhase = .idle
  private(set) var results: [CatalogResult] = []
  private(set) var hasMore = false
  private(set) var isPartial = false
  private(set) var isLoadingMore = false
  private(set) var paginationErrorMessage: String?
  private(set) var resolvingResultID: String?
  private(set) var selectionErrorMessage: String?

  private let repository: any MusicCatalogRepository
  private let kind: CatalogEntityKind
  private let availableArtistContextIDs: [UUID]
  private var artistContextIDs: [UUID]
  private let debounceDuration: Duration
  private var searchTask: Task<Void, Never>?
  private var generation = 0
  private var resolutionGeneration = 0
  private var nextOffset = 0

  init(
    repository: any MusicCatalogRepository,
    kind: CatalogEntityKind,
    artistContextIDs: [UUID] = [],
    debounceDuration: Duration = .milliseconds(400)
  ) {
    self.repository = repository
    self.kind = kind
    availableArtistContextIDs = artistContextIDs
    self.artistContextIDs = artistContextIDs
    self.debounceDuration = debounceDuration
  }

  func updateQuery(_ value: String) {
    cancelResolution()
    query = value
    searchTask?.cancel()
    generation += 1
    let requestedGeneration = generation
    let normalized = CatalogInput.normalizedText(value)
    selectionErrorMessage = nil
    paginationErrorMessage = nil

    guard normalized.count >= 2 else {
      results = []
      hasMore = false
      isPartial = false
      nextOffset = 0
      phase = .idle
      return
    }

    phase = .loading
    hasMore = false
    isPartial = false
    searchTask = Task { [weak self] in
      do {
        try await Task.sleep(for: self?.debounceDuration ?? .milliseconds(400))
        guard !Task.isCancelled else { return }
        await self?.performFirstPage(query: normalized, generation: requestedGeneration)
      } catch is CancellationError {
        return
      } catch {
        return
      }
    }
  }

  func retry() {
    searchTask?.cancel()
    generation += 1
    let requestedGeneration = generation
    let normalized = CatalogInput.normalizedText(query)
    guard normalized.count >= 2 else {
      phase = .idle
      return
    }
    phase = .loading
    searchTask = Task { [weak self] in
      await self?.performFirstPage(query: normalized, generation: requestedGeneration)
    }
  }

  func setArtistContextEnabled(_ isEnabled: Bool) {
    let updated = isEnabled ? availableArtistContextIDs : []
    guard updated != artistContextIDs else { return }
    artistContextIDs = updated
    updateQuery(query)
  }

  func loadMore() async {
    guard hasMore, !isLoadingMore, case .results = phase else { return }
    let normalized = CatalogInput.normalizedText(query)
    let requestedGeneration = generation
    let requestedOffset = nextOffset
    isLoadingMore = true
    defer {
      if requestedGeneration == generation {
        isLoadingMore = false
      }
    }

    do {
      let page = try await repository.search(
        kind: kind,
        query: normalized,
        offset: requestedOffset,
        artistContextIDs: artistContextIDs
      )
      guard requestedGeneration == generation,
            CatalogInput.normalizedText(query) == normalized,
            page.offset == requestedOffset
      else { return }
      let existingIDs = Set(results.map(\.id))
      results.append(contentsOf: page.results.filter { !existingIDs.contains($0.id) })
      nextOffset = page.offset + CatalogSearchPage.limit
      hasMore = page.hasMore
      isPartial = isPartial || page.isPartial
      paginationErrorMessage = nil
      phase = results.isEmpty ? .empty : .results
    } catch is CancellationError {
      return
    } catch {
      guard requestedGeneration == generation else { return }
      paginationErrorMessage = errorMessage(for: error)
      phase = .results
    }
  }

  func resolve(_ result: CatalogResult) async -> CatalogEntity? {
    resolutionGeneration += 1
    let requestedGeneration = resolutionGeneration
    resolvingResultID = result.id
    selectionErrorMessage = nil
    defer {
      if requestedGeneration == resolutionGeneration, resolvingResultID == result.id {
        resolvingResultID = nil
      }
    }
    do {
      let entity = try await repository.resolve(result)
      guard requestedGeneration == resolutionGeneration, !Task.isCancelled else { return nil }
      guard entity.kind == kind else {
        throw MusicCatalogError.wrongEntityKind
      }
      return entity
    } catch is CancellationError {
      return nil
    } catch {
      guard requestedGeneration == resolutionGeneration, !Task.isCancelled else { return nil }
      selectionErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
      return nil
    }
  }

  /// Invalidates an in-flight resolution even when its repository operation does not cooperate with task cancellation.
  func cancelResolution() {
    resolutionGeneration += 1
    resolvingResultID = nil
  }

  func clearSelectionError() {
    selectionErrorMessage = nil
  }

  private func performFirstPage(query: String, generation requestedGeneration: Int) async {
    do {
      let page = try await repository.search(
        kind: kind,
        query: query,
        offset: 0,
        artistContextIDs: artistContextIDs
      )
      guard requestedGeneration == generation,
            CatalogInput.normalizedText(self.query) == query,
            !Task.isCancelled
      else { return }
      results = page.results
      nextOffset = page.offset + CatalogSearchPage.limit
      hasMore = page.hasMore
      isPartial = page.isPartial
      paginationErrorMessage = nil
      phase = page.results.isEmpty ? .empty : .results
    } catch is CancellationError {
      return
    } catch {
      guard requestedGeneration == generation, CatalogInput.normalizedText(self.query) == query else { return }
      apply(error: error, preservingResults: false)
    }
  }

  private func apply(error: Error, preservingResults: Bool) {
    if !preservingResults {
      results = []
      hasMore = false
      isPartial = false
      nextOffset = 0
    }
    let catalogError = error as? MusicCatalogError
      ?? (AppFailure(error) == .offline ? .offline : .rejected(message: error.localizedDescription, retryable: true))
    switch catalogError {
    case .offline:
      phase = .offline
    case let .rateLimited(retryAfterSeconds):
      phase = .rateLimited(retryAfterSeconds: retryAfterSeconds)
    case let .rejected(message, retryable):
      phase = .failed(message: message, retryable: retryable)
    case .invalidResponse, .unresolvedCandidate, .wrongEntityKind:
      phase = .failed(message: catalogError.localizedDescription, retryable: catalogError.isRetryable)
    }
  }

  private func errorMessage(for error: Error) -> String {
    let catalogError = error as? MusicCatalogError
      ?? (AppFailure(error) == .offline
        ? .offline
        : .rejected(message: error.localizedDescription, retryable: true))
    return catalogError.localizedDescription
  }
}
