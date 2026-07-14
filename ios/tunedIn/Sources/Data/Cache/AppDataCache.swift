import Foundation
import SwiftData

struct AppCacheLookup<Value: Sendable>: Sendable {
  let value: Value
  let state: AppCacheEntryState
}

actor AppDataCache {
  let environment: AppEnvironment
  let store: SwiftDataSnapshotStore
  let clock: any AppCacheClock
  let budget: AppCacheBudget
  let diagnostics: AppCacheDiagnostics
  let mediaCache: AppMediaCache?
  var viewerID: UUID?
  var generation = 0
  var memory: [String: AppCacheMemorySnapshot] = [:]
  var resourceNamesByStorageKey: [String: String] = [:]
  var revisions: [String: Int] = [:]
  var inFlight: [String: AppCacheInFlightRequest] = [:]
  var validatedResources: Set<String> = []

  init(
    environment: AppEnvironment,
    store: SwiftDataSnapshotStore,
    clock: any AppCacheClock = SystemAppCacheClock(),
    budget: AppCacheBudget = .structured,
    diagnostics: AppCacheDiagnostics = AppCacheDiagnostics(),
    mediaCache: AppMediaCache? = nil
  ) {
    self.environment = environment
    self.store = store
    self.clock = clock
    self.budget = budget
    self.diagnostics = diagnostics
    self.mediaCache = mediaCache
  }
}

extension AppDataCache {
  func transition(to newViewerID: UUID?) async {
    await mediaCache?.transition(to: newViewerID)
    guard viewerID != newViewerID else { return }

    let previousViewerID = viewerID
    viewerID = nil
    generation += 1
    memory.removeAll()
    resourceNamesByStorageKey.removeAll()
    revisions.removeAll()
    validatedResources.removeAll()
    let tasks = inFlight.values.map(\.task)
    inFlight.removeAll()
    for task in tasks {
      task.cancel()
    }

    try? await store.remove(excluding: environment)
    if let previousViewerID {
      try? await store.remove(environment: environment, viewerID: previousViewerID)
    }
    if let newViewerID {
      try? await store.remove(environment: environment, excludingViewerID: newViewerID)
    }
    viewerID = newViewerID
  }

  func value<Value: Codable & Sendable>(
    for resource: AppCacheResource,
    freshness: AppCacheFreshness,
    policy: CacheReadPolicy = .automatic,
    load: @escaping @Sendable () async throws -> Value
  ) async throws -> Value {
    guard let viewerID else {
      await diagnostics.record(.network)
      return try await load()
    }
    if policy == .networkOnly {
      await diagnostics.record(.network)
      return try await load()
    }

    let storageKey = storageKey(resource: resource, viewerID: viewerID)
    resourceNamesByStorageKey[storageKey] = resource.name
    await validate(resource, storageKey: storageKey, viewerID: viewerID)
    if let cached: AppCacheLookup<Value> = await cachedValue(
      for: storageKey,
      freshness: freshness,
      policy: policy
    ) {
      await diagnostics.record(.hit)
      switch cached.state {
      case .stale:
        await diagnostics.record(.stale)
      case .invalidated:
        await diagnostics.record(.invalidated)
      default:
        break
      }
      return cached.value
    }
    if policy == .automatic {
      await diagnostics.record(.miss)
    }

    return try await networkValue(
      for: resource,
      storageKey: storageKey,
      viewerID: viewerID,
      load: load
    )
  }

  private func networkValue<Value: Codable & Sendable>(
    for resource: AppCacheResource,
    storageKey: String,
    viewerID: UUID,
    load: @escaping @Sendable () async throws -> Value
  ) async throws -> Value {
    let requestGeneration = generation
    let requestRevision = revisions[storageKey, default: 0]
    let (request, wasCoalesced) = inFlightRequest(
      for: storageKey,
      revision: requestRevision,
      load: load
    )
    await diagnostics.record(wasCoalesced ? .coalesced : .network)

    do {
      let payload = try await request.task.value
      clearInFlightRequest(request, for: storageKey)
      let value = try Self.decode(Value.self, from: payload)

      guard generation == requestGeneration,
            self.viewerID == viewerID,
            revisions[storageKey, default: 0] == requestRevision
      else {
        return (memory[storageKey]?.value as? Value) ?? value
      }

      let fetchedAt = clock.now
      let snapshot = CachedSnapshotValue(
        payload: payload,
        fetchedAt: fetchedAt,
        invalidatedAt: nil
      )
      memory[storageKey] = AppCacheMemorySnapshot(
        value: value,
        payload: payload,
        fetchedAt: fetchedAt,
        invalidatedAt: nil
      )
      resourceNamesByStorageKey[storageKey] = resource.name
      try? await saveSnapshot(
        CachedSnapshotWrite(
          value: snapshot,
          storageKey: storageKey,
          environment: environment,
          viewerID: viewerID,
          resource: resource,
          accessedAt: fetchedAt
        )
      )
      return value
    } catch {
      clearInFlightRequest(request, for: storageKey)
      throw error
    }
  }

  private func inFlightRequest<Value: Encodable & Sendable>(
    for storageKey: String,
    revision: Int,
    load: @escaping @Sendable () async throws -> Value
  ) -> (request: AppCacheInFlightRequest, wasCoalesced: Bool) {
    if let existing = inFlight[storageKey], existing.revision == revision {
      return (existing, true)
    }
    let task = Task {
      let value = try await load()
      return try Self.encode(value)
    }
    let request = AppCacheInFlightRequest(
      id: UUID(),
      revision: revision,
      task: task
    )
    inFlight[storageKey] = request
    return (request, false)
  }
}
