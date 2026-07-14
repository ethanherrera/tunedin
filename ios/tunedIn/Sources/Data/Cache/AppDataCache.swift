import CryptoKit
import Foundation
import SwiftData

actor AppDataCache {
  let environment: AppEnvironment
  let store: SwiftDataSnapshotStore
  let clock: any AppCacheClock
  var viewerID: UUID?
  private var generation = 0
  var memory: [String: AppCacheMemorySnapshot] = [:]
  var resourceNamesByStorageKey: [String: String] = [:]
  private var revisions: [String: Int] = [:]
  private var inFlight: [String: AppCacheInFlightRequest] = [:]

  init(
    environment: AppEnvironment,
    store: SwiftDataSnapshotStore,
    clock: any AppCacheClock = SystemAppCacheClock()
  ) {
    self.environment = environment
    self.store = store
    self.clock = clock
  }
}

extension AppDataCache {
  func transition(to newViewerID: UUID?) async {
    guard viewerID != newViewerID else { return }

    let previousViewerID = viewerID
    viewerID = nil
    generation += 1
    memory.removeAll()
    resourceNamesByStorageKey.removeAll()
    revisions.removeAll()
    let tasks = inFlight.values.map(\.task)
    inFlight.removeAll()
    for task in tasks {
      task.cancel()
    }

    try? await store.remove(excluding: environment)
    if let previousViewerID {
      try? await store.remove(environment: environment, viewerID: previousViewerID)
    }
    viewerID = newViewerID
  }

  func value<Value: Codable & Sendable>(
    for resource: AppCacheResource,
    freshness: AppCacheFreshness,
    policy: CacheReadPolicy = .automatic,
    load: @escaping @Sendable () async throws -> Value
  ) async throws -> Value {
    guard let viewerID, policy != .networkOnly else {
      return try await load()
    }

    let storageKey = storageKey(resource: resource, viewerID: viewerID)
    resourceNamesByStorageKey[storageKey] = resource.name
    if let cached: Value = await cachedValue(
      for: storageKey,
      freshness: freshness,
      policy: policy
    ) {
      return cached
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
    let request = inFlightRequest(
      for: storageKey,
      revision: requestRevision,
      load: load
    )

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
      try? await store.save(
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
  ) -> AppCacheInFlightRequest {
    if let existing = inFlight[storageKey], existing.revision == revision {
      return existing
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
    return request
  }
}

extension AppDataCache {
  func currentScope() -> AppCacheScope? {
    guard let viewerID else { return nil }
    return AppCacheScope(
      environment: environment.rawValue,
      viewerID: viewerID,
      generation: generation
    )
  }

  func store(
    _ value: some Codable & Sendable,
    for resource: AppCacheResource
  ) async throws {
    guard let viewerID else { return }
    let storageKey = storageKey(resource: resource, viewerID: viewerID)
    let date = clock.now
    let payload = try Self.encode(value)
    advanceRevision(for: storageKey)
    let snapshot = CachedSnapshotValue(
      payload: payload,
      fetchedAt: date,
      invalidatedAt: nil
    )
    memory[storageKey] = AppCacheMemorySnapshot(
      value: value,
      payload: payload,
      fetchedAt: date,
      invalidatedAt: nil
    )
    resourceNamesByStorageKey[storageKey] = resource.name
    try await store.save(
      CachedSnapshotWrite(
        value: snapshot,
        storageKey: storageKey,
        environment: environment,
        viewerID: viewerID,
        resource: resource,
        accessedAt: date
      )
    )
  }

  func invalidate(_ resource: AppCacheResource) async {
    guard let viewerID else { return }
    let key = storageKey(resource: resource, viewerID: viewerID)
    let date = clock.now
    advanceRevision(for: key)
    if let snapshot = memory[key] {
      memory[key] = AppCacheMemorySnapshot(
        value: snapshot.value,
        payload: snapshot.payload,
        fetchedAt: snapshot.fetchedAt,
        invalidatedAt: date
      )
    }
    try? await store.invalidate(storageKey: key, at: date)
  }

  func remove(_ resource: AppCacheResource) async {
    guard let viewerID else { return }
    let key = storageKey(resource: resource, viewerID: viewerID)
    advanceRevision(for: key)
    memory[key] = nil
    resourceNamesByStorageKey[key] = nil
    try? await store.remove(storageKey: key)
  }

  func remove(resourcesNamed resourceNames: Set<String>) async {
    guard let viewerID, !resourceNames.isEmpty else { return }

    let memoryKeys = resourceNamesByStorageKey.compactMap { key, name in
      resourceNames.contains(name) ? key : nil
    }
    for key in memoryKeys {
      advanceRevision(for: key)
      memory[key] = nil
      resourceNamesByStorageKey[key] = nil
    }

    let storedKeys = (try? await store.remove(
      environment: environment,
      viewerID: viewerID,
      resourcesNamed: resourceNames
    )) ?? []

    for key in storedKeys where !memoryKeys.contains(key) {
      advanceRevision(for: key)
      memory[key] = nil
      resourceNamesByStorageKey[key] = nil
    }
  }

  func state(
    for resource: AppCacheResource,
    freshness: AppCacheFreshness
  ) async -> AppCacheEntryState {
    guard let viewerID else { return .missing }
    let key = storageKey(resource: resource, viewerID: viewerID)
    guard let snapshot = await snapshotMetadata(for: key) else { return .missing }
    let age = max(0, clock.now.timeIntervalSince(snapshot.fetchedAt))
    if age > freshness.maximumStale {
      return .expired
    }
    if snapshot.invalidatedAt != nil {
      return .invalidated
    }
    return age <= freshness.freshFor ? .fresh : .stale
  }

  func clearMemory() {
    memory.removeAll()
    resourceNamesByStorageKey.removeAll()
  }

  #if DEBUG
    func replacePayloadForTesting(
      _ payload: Data,
      for resource: AppCacheResource
    ) async throws {
      guard let viewerID else { return }
      let key = storageKey(resource: resource, viewerID: viewerID)
      let date = clock.now
      advanceRevision(for: key)
      let snapshot = CachedSnapshotValue(
        payload: payload,
        fetchedAt: date,
        invalidatedAt: nil
      )
      memory[key] = nil
      try await store.save(
        CachedSnapshotWrite(
          value: snapshot,
          storageKey: key,
          environment: environment,
          viewerID: viewerID,
          resource: resource,
          accessedAt: date
        )
      )
    }
  #endif

  private func cachedValue<Value: Decodable & Sendable>(
    for storageKey: String,
    freshness: AppCacheFreshness,
    policy: CacheReadPolicy
  ) async -> Value? {
    guard policy == .automatic else { return nil }

    if let snapshot = memory[storageKey] {
      guard isUsable(snapshot.fetchedAt, freshness: freshness) else {
        await dropSnapshot(for: storageKey)
        return nil
      }
      guard let value = snapshot.value as? Value else {
        await dropSnapshot(for: storageKey)
        return nil
      }
      return value
    }

    guard let snapshot = try? await store.snapshot(for: storageKey, accessedAt: clock.now) else {
      return nil
    }
    guard isUsable(snapshot.fetchedAt, freshness: freshness) else {
      await dropSnapshot(for: storageKey)
      return nil
    }

    do {
      let value = try Self.decode(Value.self, from: snapshot.payload)
      memory[storageKey] = AppCacheMemorySnapshot(
        value: value,
        payload: snapshot.payload,
        fetchedAt: snapshot.fetchedAt,
        invalidatedAt: snapshot.invalidatedAt
      )
      return value
    } catch {
      await dropSnapshot(for: storageKey)
      return nil
    }
  }

  private func snapshotMetadata(for storageKey: String) async -> CachedSnapshotValue? {
    if let snapshot = memory[storageKey] {
      return CachedSnapshotValue(
        payload: snapshot.payload,
        fetchedAt: snapshot.fetchedAt,
        invalidatedAt: snapshot.invalidatedAt
      )
    }
    return try? await store.snapshot(for: storageKey, accessedAt: clock.now)
  }

  private func isUsable(_ fetchedAt: Date, freshness: AppCacheFreshness) -> Bool {
    max(0, clock.now.timeIntervalSince(fetchedAt)) <= freshness.maximumStale
  }

  func dropSnapshot(for storageKey: String) async {
    advanceRevision(for: storageKey)
    memory[storageKey] = nil
    resourceNamesByStorageKey[storageKey] = nil
    try? await store.remove(storageKey: storageKey)
  }

  func advanceRevision(for storageKey: String) {
    revisions[storageKey, default: 0] += 1
    inFlight[storageKey]?.task.cancel()
    inFlight[storageKey] = nil
  }

  private func clearInFlightRequest(
    _ request: AppCacheInFlightRequest,
    for storageKey: String
  ) {
    guard inFlight[storageKey]?.id == request.id else { return }
    inFlight[storageKey] = nil
  }

  func storageKey(resource: AppCacheResource, viewerID: UUID) -> String {
    let components = [
      environment.rawValue,
      viewerID.uuidString.lowercased(),
      resource.name,
      resource.variant,
      String(resource.payloadVersion)
    ]
    let digest = SHA256.hash(data: Data(components.joined(separator: "\u{1F}").utf8))
    return digest.map { String(format: "%02x", $0) }.joined()
  }

  nonisolated static func encode(_ value: some Encodable) throws -> Data {
    try JSONEncoder().encode(value)
  }

  nonisolated static func decode<Value: Decodable>(
    _ type: Value.Type,
    from payload: Data
  ) throws -> Value {
    try JSONDecoder().decode(type, from: payload)
  }
}
