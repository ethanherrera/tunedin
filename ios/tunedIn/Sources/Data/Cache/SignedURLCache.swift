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
    let task: Task<URL, any Error>
  }

  private let capacity: Int
  private let lifetime: TimeInterval
  private let diagnostics: AppCacheDiagnostics
  private var entries: [SignedURLCacheKey: Entry] = [:]
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
    if var entry = entries[key], entry.expiresAt > now {
      entry.lastAccessedAt = now
      entries[key] = entry
      await diagnostics.record(.hit)
      return entry.url
    }
    entries[key] = nil

    if let request = inFlight[key] {
      await diagnostics.record(.miss)
      await diagnostics.record(.coalesced)
      return try await request.task.value
    }

    let request = InFlightRequest(id: UUID(), task: Task { try await load() })
    inFlight[key] = request
    await diagnostics.record(.miss)
    await diagnostics.record(.network)
    do {
      let url = try await request.task.value
      clear(request, for: key)
      entries[key] = Entry(
        url: url,
        expiresAt: now.addingTimeInterval(lifetime),
        lastAccessedAt: now
      )
      await prune(now: now)
      return url
    } catch {
      clear(request, for: key)
      throw error
    }
  }

  func remove(kind: SignedURLCacheKey.Kind, id: UUID) {
    let keys = Set(entries.keys).union(inFlight.keys).filter { key in
      key.kind == kind && key.id == id
    }
    for key in keys {
      entries[key] = nil
      inFlight[key]?.task.cancel()
      inFlight[key] = nil
    }
  }

  func removeAll() {
    entries.removeAll()
    for request in inFlight.values {
      request.task.cancel()
    }
    inFlight.removeAll()
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

  private func prune(now: Date) async {
    let expiredKeys = entries.compactMap { key, entry in
      entry.expiresAt <= now ? key : nil
    }
    for key in expiredKeys {
      entries[key] = nil
    }

    var evictionCount = expiredKeys.count
    while entries.count > capacity,
          let oldestKey = entries.min(by: {
            $0.value.lastAccessedAt < $1.value.lastAccessedAt
          })?.key {
      entries[oldestKey] = nil
      evictionCount += 1
    }
    await diagnostics.record(.eviction, count: evictionCount)
  }
}
