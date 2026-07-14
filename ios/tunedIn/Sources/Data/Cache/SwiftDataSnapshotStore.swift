import Foundation
import SwiftData

@Model
final class CachedServerSnapshot {
  @Attribute(.unique) var storageKey: String
  var environment: String
  var viewerID: UUID
  var resource: String
  var payloadVersion: Int
  var payload: Data
  var fetchedAt: Date
  var lastAccessedAt: Date
  var invalidatedAt: Date?

  init(
    storageKey: String,
    environment: String,
    viewerID: UUID,
    resource: String,
    payloadVersion: Int,
    payload: Data,
    fetchedAt: Date,
    lastAccessedAt: Date,
    invalidatedAt: Date? = nil
  ) {
    self.storageKey = storageKey
    self.environment = environment
    self.viewerID = viewerID
    self.resource = resource
    self.payloadVersion = payloadVersion
    self.payload = payload
    self.fetchedAt = fetchedAt
    self.lastAccessedAt = lastAccessedAt
    self.invalidatedAt = invalidatedAt
  }
}

struct CachedSnapshotValue: Sendable {
  let payload: Data
  let fetchedAt: Date
  let invalidatedAt: Date?
}

struct CachedSnapshotWrite: Sendable {
  let value: CachedSnapshotValue
  let storageKey: String
  let environment: AppEnvironment
  let viewerID: UUID
  let resource: AppCacheResource
  let accessedAt: Date
}

@ModelActor
actor SwiftDataSnapshotStore {
  func snapshot(for storageKey: String, accessedAt: Date) throws -> CachedSnapshotValue? {
    guard let snapshot = try model(for: storageKey) else { return nil }
    snapshot.lastAccessedAt = accessedAt
    try modelContext.save()
    return CachedSnapshotValue(
      payload: snapshot.payload,
      fetchedAt: snapshot.fetchedAt,
      invalidatedAt: snapshot.invalidatedAt
    )
  }

  func save(_ write: CachedSnapshotWrite) throws {
    if let snapshot = try model(for: write.storageKey) {
      snapshot.payload = write.value.payload
      snapshot.payloadVersion = write.resource.payloadVersion
      snapshot.fetchedAt = write.value.fetchedAt
      snapshot.lastAccessedAt = write.accessedAt
      snapshot.invalidatedAt = write.value.invalidatedAt
    } else {
      modelContext.insert(CachedServerSnapshot(write: write))
    }
    try modelContext.save()
  }

  func invalidate(storageKey: String, at date: Date) throws {
    guard let snapshot = try model(for: storageKey) else { return }
    snapshot.invalidatedAt = date
    snapshot.lastAccessedAt = date
    try modelContext.save()
  }

  func remove(storageKey: String) throws {
    guard let snapshot = try model(for: storageKey) else { return }
    modelContext.delete(snapshot)
    try modelContext.save()
  }

  func remove(environment: AppEnvironment, viewerID: UUID) throws {
    let environmentValue = environment.rawValue
    let descriptor = FetchDescriptor<CachedServerSnapshot>(
      predicate: #Predicate { snapshot in
        snapshot.environment == environmentValue && snapshot.viewerID == viewerID
      }
    )
    for snapshot in try modelContext.fetch(descriptor) {
      modelContext.delete(snapshot)
    }
    try modelContext.save()
  }

  func remove(excluding environment: AppEnvironment) throws {
    let environmentValue = environment.rawValue
    let descriptor = FetchDescriptor<CachedServerSnapshot>(
      predicate: #Predicate { snapshot in
        snapshot.environment != environmentValue
      }
    )
    for snapshot in try modelContext.fetch(descriptor) {
      modelContext.delete(snapshot)
    }
    try modelContext.save()
  }

  private func model(for storageKey: String) throws -> CachedServerSnapshot? {
    var descriptor = FetchDescriptor<CachedServerSnapshot>(
      predicate: #Predicate { snapshot in
        snapshot.storageKey == storageKey
      }
    )
    descriptor.fetchLimit = 1
    return try modelContext.fetch(descriptor).first
  }
}

private extension CachedServerSnapshot {
  convenience init(write: CachedSnapshotWrite) {
    self.init(
      storageKey: write.storageKey,
      environment: write.environment.rawValue,
      viewerID: write.viewerID,
      resource: write.resource.name,
      payloadVersion: write.resource.payloadVersion,
      payload: write.value.payload,
      fetchedAt: write.value.fetchedAt,
      lastAccessedAt: write.accessedAt,
      invalidatedAt: write.value.invalidatedAt
    )
  }
}
