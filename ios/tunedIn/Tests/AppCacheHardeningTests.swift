import Foundation
import Testing
@testable import tunedIn

struct AppCacheHardeningTests {
  private let viewerID = UUID(uuidString: "73000000-0000-0000-0000-000000000001")!
  private let freshness = AppCacheFreshness(freshFor: 60, maximumStale: 300)

  @Test
  func entryBudgetEvictsTheLeastRecentlyUsedSnapshotFromMemoryAndSwiftData() async throws {
    let clock = HardeningCacheClock(now: Date(timeIntervalSince1970: 1_000))
    let diagnostics = AppCacheDiagnostics()
    let cache = try AppDataCache.inMemory(
      clock: clock,
      budget: AppCacheBudget(maximumEntryCount: 2, maximumPayloadBytes: 1_024),
      diagnostics: diagnostics
    )
    let first = AppCacheResource(name: "budget", variant: "first")
    let second = AppCacheResource(name: "budget", variant: "second")
    let third = AppCacheResource(name: "budget", variant: "third")
    await cache.transition(to: viewerID)

    try await cache.store(1, for: first)
    clock.advance(by: 1)
    try await cache.store(2, for: second)
    clock.advance(by: 1)
    let touched: Int = try await cache.value(for: first, freshness: freshness) {
      Issue.record("The first value should be served from the cache")
      return 10
    }
    #expect(touched == 1)
    clock.advance(by: 1)
    try await cache.store(3, for: third)

    #expect(await cache.state(for: first, freshness: freshness) == .fresh)
    #expect(await cache.state(for: second, freshness: freshness) == .missing)
    #expect(await cache.state(for: third, freshness: freshness) == .fresh)
    await cache.clearMemory()
    #expect(await cache.state(for: second, freshness: freshness) == .missing)
    #expect(await diagnostics.snapshot()[.eviction] == 1)
  }

  @Test
  func payloadByteBudgetPrunesEvenWhenTheEntryLimitHasRoom() async throws {
    let clock = HardeningCacheClock(now: Date(timeIntervalSince1970: 2_000))
    let cache = try AppDataCache.inMemory(
      clock: clock,
      budget: AppCacheBudget(maximumEntryCount: 10, maximumPayloadBytes: 7)
    )
    let first = AppCacheResource(name: "bytes", variant: "first")
    let second = AppCacheResource(name: "bytes", variant: "second")
    await cache.transition(to: viewerID)

    try await cache.store("aa", for: first)
    clock.advance(by: 1)
    try await cache.store("bb", for: second)

    #expect(await cache.state(for: first, freshness: freshness) == .missing)
    #expect(await cache.state(for: second, freshness: freshness) == .fresh)
  }

  @Test
  func diagnosticsCountOnlyFixedCacheOutcomes() async throws {
    let clock = HardeningCacheClock(now: Date(timeIntervalSince1970: 3_000))
    let diagnostics = AppCacheDiagnostics()
    let cache = try AppDataCache.inMemory(clock: clock, diagnostics: diagnostics)
    let resource = AppCacheResource(name: "diagnostics")
    let loader = HardeningIntegerLoader(values: [1, 2])
    await cache.transition(to: viewerID)

    #expect(try await value(cache, resource, loader) == 1)
    #expect(try await value(cache, resource, loader) == 1)
    clock.advance(by: 120)
    #expect(try await value(cache, resource, loader) == 1)
    await cache.invalidate(resource)
    #expect(try await value(cache, resource, loader) == 1)
    try await cache.replacePayloadForTesting(Data([0xFF]), for: resource)
    #expect(try await value(cache, resource, loader) == 2)

    let snapshot = await diagnostics.snapshot()
    #expect(snapshot[.hit] == 3)
    #expect(snapshot[.miss] == 2)
    #expect(snapshot[.stale] == 1)
    #expect(snapshot[.invalidated] == 1)
    #expect(snapshot[.network] == 2)
    #expect(snapshot[.decodeFailure] == 1)
  }

  private func value(
    _ cache: AppDataCache,
    _ resource: AppCacheResource,
    _ loader: HardeningIntegerLoader
  ) async throws -> Int {
    try await cache.value(for: resource, freshness: freshness) {
      try await loader.load()
    }
  }
}

private actor HardeningIntegerLoader {
  private let values: [Int]
  private var index = 0

  init(values: [Int]) {
    self.values = values
  }

  func load() throws -> Int {
    defer { index += 1 }
    return values[min(index, values.count - 1)]
  }
}

private final class HardeningCacheClock: AppCacheClock, @unchecked Sendable {
  private let lock = NSLock()
  private var date: Date

  init(now: Date) {
    date = now
  }

  var now: Date {
    lock.lock()
    defer { lock.unlock() }
    return date
  }

  func advance(by interval: TimeInterval) {
    lock.lock()
    date = date.addingTimeInterval(interval)
    lock.unlock()
  }
}
