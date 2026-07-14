import Foundation

extension AppDataCache {
  func invalidate(resourcesNamed resourceNames: Set<String>) async {
    guard let viewerID, !resourceNames.isEmpty else { return }
    let date = clock.now
    let memoryKeys = resourceNamesByStorageKey.compactMap { key, name in
      resourceNames.contains(name) ? key : nil
    }
    for key in memoryKeys {
      advanceRevision(for: key)
      if let snapshot = memory[key] {
        memory[key] = AppCacheMemorySnapshot(
          value: snapshot.value,
          payload: snapshot.payload,
          fetchedAt: snapshot.fetchedAt,
          invalidatedAt: date
        )
      }
    }

    let storedKeys = (try? await store.invalidate(
      environment: environment,
      viewerID: viewerID,
      resourcesNamed: resourceNames,
      at: date
    )) ?? []
    for key in storedKeys where !memoryKeys.contains(key) {
      advanceRevision(for: key)
    }
  }

  func patch<Value: Codable & Sendable>(
    _ type: Value.Type,
    for resource: AppCacheResource,
    markInvalidated: Bool = false,
    transform: @Sendable (Value) -> Value
  ) async {
    guard let viewerID else { return }
    let key = storageKey(resource: resource, viewerID: viewerID)
    guard let snapshot = await patchableSnapshot(type, storageKey: key) else { return }
    guard let payload = try? Self.encode(transform(snapshot.value)) else { return }
    guard let patched = try? Self.decode(type, from: payload) else { return }
    let date = clock.now
    let invalidatedAt = markInvalidated ? date : snapshot.metadata.invalidatedAt
    advanceRevision(for: key)
    memory[key] = AppCacheMemorySnapshot(
      value: patched,
      payload: payload,
      fetchedAt: snapshot.metadata.fetchedAt,
      invalidatedAt: invalidatedAt
    )
    resourceNamesByStorageKey[key] = resource.name
    try? await store.save(
      CachedSnapshotWrite(
        value: CachedSnapshotValue(
          payload: payload,
          fetchedAt: snapshot.metadata.fetchedAt,
          invalidatedAt: invalidatedAt
        ),
        storageKey: key,
        environment: environment,
        viewerID: viewerID,
        resource: resource,
        accessedAt: date
      )
    )
  }

  private func patchableSnapshot<Value: Codable & Sendable>(
    _ type: Value.Type,
    storageKey: String
  ) async -> (value: Value, metadata: CachedSnapshotValue)? {
    if let memorySnapshot = memory[storageKey] {
      guard let value = memorySnapshot.value as? Value else {
        await dropSnapshot(for: storageKey)
        return nil
      }
      return (
        value,
        CachedSnapshotValue(
          payload: memorySnapshot.payload,
          fetchedAt: memorySnapshot.fetchedAt,
          invalidatedAt: memorySnapshot.invalidatedAt
        )
      )
    }

    guard let metadata = try? await store.snapshot(for: storageKey, accessedAt: clock.now),
          let value = try? Self.decode(type, from: metadata.payload)
    else { return nil }
    return (value, metadata)
  }
}
