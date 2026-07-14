import CryptoKit
import Foundation

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
    try await saveSnapshot(
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
    return entryState(
      fetchedAt: snapshot.fetchedAt,
      invalidatedAt: snapshot.invalidatedAt,
      freshness: freshness
    )
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
      try await saveSnapshot(
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

    func diagnosticsSnapshot() async -> AppCacheDiagnosticsSnapshot {
      await diagnostics.snapshot()
    }
  #endif

  func cachedValue<Value: Decodable & Sendable>(
    for storageKey: String,
    freshness: AppCacheFreshness,
    policy: CacheReadPolicy
  ) async -> AppCacheLookup<Value>? {
    guard policy == .automatic else { return nil }
    if let snapshot = memory[storageKey] {
      return await memoryValue(
        snapshot,
        storageKey: storageKey,
        freshness: freshness
      )
    }
    return await storedValue(storageKey: storageKey, freshness: freshness)
  }

  private func memoryValue<Value: Decodable & Sendable>(
    _ snapshot: AppCacheMemorySnapshot,
    storageKey: String,
    freshness: AppCacheFreshness
  ) async -> AppCacheLookup<Value>? {
    guard isUsable(snapshot.fetchedAt, freshness: freshness) else {
      await dropSnapshot(for: storageKey)
      await diagnostics.record(.eviction)
      return nil
    }
    guard let value = snapshot.value as? Value else {
      await dropSnapshot(for: storageKey)
      await diagnostics.record(.decodeFailure)
      return nil
    }
    try? await store.touch(storageKey: storageKey, at: clock.now)
    return AppCacheLookup(
      value: value,
      state: entryState(
        fetchedAt: snapshot.fetchedAt,
        invalidatedAt: snapshot.invalidatedAt,
        freshness: freshness
      )
    )
  }

  private func storedValue<Value: Decodable & Sendable>(
    storageKey: String,
    freshness: AppCacheFreshness
  ) async -> AppCacheLookup<Value>? {
    guard let snapshot = try? await store.snapshot(for: storageKey, accessedAt: clock.now) else {
      return nil
    }
    guard isUsable(snapshot.fetchedAt, freshness: freshness) else {
      await dropSnapshot(for: storageKey)
      await diagnostics.record(.eviction)
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
      return AppCacheLookup(
        value: value,
        state: entryState(
          fetchedAt: snapshot.fetchedAt,
          invalidatedAt: snapshot.invalidatedAt,
          freshness: freshness
        )
      )
    } catch {
      await dropSnapshot(for: storageKey)
      await diagnostics.record(.decodeFailure)
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

  private func entryState(
    fetchedAt: Date,
    invalidatedAt: Date?,
    freshness: AppCacheFreshness
  ) -> AppCacheEntryState {
    let age = max(0, clock.now.timeIntervalSince(fetchedAt))
    if age > freshness.maximumStale {
      return .expired
    }
    if invalidatedAt != nil {
      return .invalidated
    }
    return age <= freshness.freshFor ? .fresh : .stale
  }

  func saveSnapshot(_ write: CachedSnapshotWrite) async throws {
    let evictedKeys = try await store.save(write, budget: budget)
    await applyEvictions(evictedKeys)
  }

  func validate(
    _ resource: AppCacheResource,
    storageKey: String,
    viewerID: UUID
  ) async {
    guard !validatedResources.contains(storageKey) else { return }
    do {
      let removedKeys = try await store.removeIncompatible(
        environment: environment,
        viewerID: viewerID,
        resource: resource
      )
      validatedResources.insert(storageKey)
      await applyEvictions(removedKeys)
    } catch {
      return
    }
  }

  private func applyEvictions(_ storageKeys: [String]) async {
    let uniqueKeys = Set(storageKeys)
    guard !uniqueKeys.isEmpty else { return }
    for key in uniqueKeys {
      advanceRevision(for: key)
      memory[key] = nil
      resourceNamesByStorageKey[key] = nil
      validatedResources.remove(key)
    }
    await diagnostics.record(.eviction, count: uniqueKeys.count)
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

  func clearInFlightRequest(
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
