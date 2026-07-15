import Foundation

struct SignedURLCacheKey: Hashable, Sendable {
  enum Kind: String, Sendable {
    case avatar
    case concertPhoto = "concert-photo"
    case albumPhoto = "album-photo"
  }

  let kind: Kind
  let id: UUID
  let version: Int64

  static func avatar(profileID: UUID, version: Int64) -> Self {
    Self(kind: .avatar, id: profileID, version: version)
  }

  static func concertPhoto(concertID: UUID, version: Int64) -> Self {
    Self(kind: .concertPhoto, id: concertID, version: version)
  }

  static func albumPhoto(photoID: UUID, version: Int64) -> Self {
    Self(kind: .albumPhoto, id: photoID, version: version)
  }
}

actor SignedURLCache {
  private struct Entry {
    let url: URL
    let expiresAt: Date
    var lastAccessedAt: Date
  }

  private struct InFlightRequest {
    let id: UUID
    let cacheGeneration: Int
    let task: Task<URL, any Error>
  }

  private struct ActiveOperation {
    let id: UUID
    let cacheGeneration: Int
    var callerCount: Int
  }

  private struct OperationHandle: Sendable {
    let id: UUID
    let cacheGeneration: Int
  }

  private let capacity: Int
  private let lifetime: TimeInterval
  private let diagnostics: AppCacheDiagnostics
  private var cacheGeneration = 0
  private var activeTransitions = 0
  private var entries: [SignedURLCacheKey: Entry] = [:]
  private var activeOperations: [SignedURLCacheKey: ActiveOperation] = [:]
  private var inFlight: [SignedURLCacheKey: InFlightRequest] = [:]

  init(
    capacity: Int = 200,
    lifetime: TimeInterval = 55 * 60,
    diagnostics: AppCacheDiagnostics = AppCacheDiagnostics()
  ) {
    self.capacity = capacity
    self.lifetime = lifetime
    self.diagnostics = diagnostics
  }

  func value(
    for key: SignedURLCacheKey,
    now: Date = .now,
    load: @escaping @Sendable () async throws -> URL
  ) async throws -> URL {
    try Task.checkCancellation()
    guard activeTransitions == 0 else {
      throw CancellationError()
    }
    let operation = acquireOperation(for: key)
    defer { release(operation, for: key) }
    if var entry = entries[key], entry.expiresAt > now {
      entry.lastAccessedAt = now
      entries[key] = entry
      await diagnostics.record(.hit)
      try ensureValid(operation, for: key)
      return entry.url
    }
    entries[key] = nil

    if let request = inFlight[key] {
      await diagnostics.record(.miss)
      try ensureValid(operation, for: key, request: request)
      await diagnostics.record(.coalesced)
      try ensureValid(operation, for: key, request: request)
      let url = try await request.task.value
      try ensureValid(operation, for: key, request: request)
      return url
    }

    let request = InFlightRequest(
      id: UUID(),
      cacheGeneration: cacheGeneration,
      task: Task { try await load() }
    )
    inFlight[key] = request
    do {
      await diagnostics.record(.miss)
      try ensureValid(operation, for: key, request: request)
      await diagnostics.record(.network)
      try ensureValid(operation, for: key, request: request)
      let url = try await request.task.value
      try ensureValid(operation, for: key, request: request)
      entries[key] = Entry(
        url: url,
        expiresAt: now.addingTimeInterval(lifetime),
        lastAccessedAt: now
      )
      await prune(now: now)
      try ensureValid(operation, for: key, request: request)
      clear(request, for: key)
      return url
    } catch {
      clear(request, for: key)
      throw error
    }
  }

  func beginTransition() {
    activeTransitions += 1
    invalidateInFlightRequests()
    entries.removeAll()
  }

  func endTransition() {
    precondition(activeTransitions > 0)
    activeTransitions -= 1
  }

  func remove(kind: SignedURLCacheKey.Kind, id: UUID) {
    let keys = Set(entries.keys)
      .union(activeOperations.keys)
      .union(inFlight.keys)
      .filter { key in
        key.kind == kind && key.id == id
      }
    for key in keys {
      entries[key] = nil
      activeOperations[key] = nil
      if let request = inFlight[key] {
        request.task.cancel()
        inFlight[key] = nil
      }
    }
  }

  func removeAll() {
    invalidateInFlightRequests()
    entries.removeAll()
  }

  #if DEBUG
    func entryCount() -> Int {
      entries.count
    }
  #endif

  private func clear(_ request: InFlightRequest, for key: SignedURLCacheKey) {
    guard inFlight[key]?.id == request.id else { return }
    inFlight[key] = nil
  }

  private func acquireOperation(for key: SignedURLCacheKey) -> OperationHandle {
    if var operation = activeOperations[key] {
      operation.callerCount += 1
      activeOperations[key] = operation
      return OperationHandle(id: operation.id, cacheGeneration: operation.cacheGeneration)
    }
    let operation = ActiveOperation(
      id: UUID(),
      cacheGeneration: cacheGeneration,
      callerCount: 1
    )
    activeOperations[key] = operation
    return OperationHandle(id: operation.id, cacheGeneration: operation.cacheGeneration)
  }

  private func release(_ handle: OperationHandle, for key: SignedURLCacheKey) {
    guard var operation = activeOperations[key], operation.id == handle.id else { return }
    operation.callerCount -= 1
    if operation.callerCount == 0 {
      activeOperations[key] = nil
    } else {
      activeOperations[key] = operation
    }
  }

  private func ensureValid(
    _ handle: OperationHandle,
    for key: SignedURLCacheKey,
    request: InFlightRequest? = nil
  ) throws {
    try Task.checkCancellation()
    guard handle.cacheGeneration == cacheGeneration,
          activeOperations[key]?.id == handle.id
    else {
      throw CancellationError()
    }
    if let request, request.cacheGeneration != cacheGeneration {
      throw CancellationError()
    }
  }

  private func invalidateInFlightRequests() {
    cacheGeneration += 1
    activeOperations.removeAll()
    for request in inFlight.values {
      request.task.cancel()
    }
    inFlight.removeAll()
  }

  private func prune(now: Date) async {
    let expiredKeys = entries.compactMap { key, entry in
      entry.expiresAt <= now ? key : nil
    }
    for key in expiredKeys {
      entries[key] = nil
    }

    var evictionCount = expiredKeys.count
    while entries.count > capacity {
      guard let oldestKey = entries.min(by: {
        $0.value.lastAccessedAt < $1.value.lastAccessedAt
      })?.key else { break }
      entries[oldestKey] = nil
      evictionCount += 1
    }
    await diagnostics.record(.eviction, count: evictionCount)
  }
}
