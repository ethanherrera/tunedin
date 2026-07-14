import Foundation

actor SocialProfileSearchCache {
  private struct Entry: Sendable {
    let profiles: [SocialProfile]
    let storedAt: Date
  }

  private struct InFlightRequest {
    let id: UUID
    let task: Task<[SocialProfile], any Error>
  }

  private let capacity: Int
  private let maximumAge: TimeInterval
  private let clock: any AppCacheClock
  private var activeScope: AppCacheScope?
  private var entries: [String: Entry] = [:]
  private var recency: [String] = []
  private var inFlight: [String: InFlightRequest] = [:]

  init(
    capacity: Int = 20,
    maximumAge: TimeInterval = 5 * 60,
    clock: any AppCacheClock = SystemAppCacheClock()
  ) {
    self.capacity = max(1, capacity)
    self.maximumAge = maximumAge
    self.clock = clock
  }

  func value(
    scope: AppCacheScope?,
    normalizedPrefix: String,
    policy: CacheReadPolicy,
    load: @escaping @Sendable () async throws -> [SocialProfile]
  ) async throws -> [SocialProfile] {
    guard let scope else {
      reset()
      return try await load()
    }
    guard policy != .networkOnly else { return try await load() }
    transition(to: scope)

    if policy == .automatic, let entry = entries[normalizedPrefix] {
      let age = max(0, clock.now.timeIntervalSince(entry.storedAt))
      if age <= maximumAge {
        touch(normalizedPrefix)
        return entry.profiles
      }
      remove(prefix: normalizedPrefix)
    }

    let request: InFlightRequest
    if let existing = inFlight[normalizedPrefix] {
      request = existing
    } else {
      let task = Task { try await load() }
      request = InFlightRequest(id: UUID(), task: task)
      inFlight[normalizedPrefix] = request
    }

    do {
      let profiles = try await request.task.value
      clear(request, for: normalizedPrefix)
      guard activeScope == scope else { return profiles }
      entries[normalizedPrefix] = Entry(profiles: profiles, storedAt: clock.now)
      touch(normalizedPrefix)
      trimToCapacity()
      return profiles
    } catch {
      clear(request, for: normalizedPrefix)
      throw error
    }
  }

  func removeAll(scope: AppCacheScope?) {
    guard let scope else {
      reset()
      return
    }
    transition(to: scope)
    reset()
    activeScope = scope
  }

  private func transition(to scope: AppCacheScope) {
    guard activeScope != scope else { return }
    reset()
    activeScope = scope
  }

  private func reset() {
    entries.removeAll()
    recency.removeAll()
    for request in inFlight.values {
      request.task.cancel()
    }
    inFlight.removeAll()
    activeScope = nil
  }

  private func touch(_ prefix: String) {
    recency.removeAll { $0 == prefix }
    recency.append(prefix)
  }

  private func trimToCapacity() {
    while entries.count > capacity, let leastRecent = recency.first {
      remove(prefix: leastRecent)
    }
  }

  private func remove(prefix: String) {
    entries[prefix] = nil
    recency.removeAll { $0 == prefix }
  }

  private func clear(_ request: InFlightRequest, for prefix: String) {
    guard inFlight[prefix]?.id == request.id else { return }
    inFlight[prefix] = nil
  }
}
