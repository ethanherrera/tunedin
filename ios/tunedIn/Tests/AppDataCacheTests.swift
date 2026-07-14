import Foundation
import SwiftData
import Testing
@testable import tunedIn

struct AppDataCacheTests {
  private let viewerID = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
  private let resource = AppCacheResource(name: "test", variant: "first-page")
  private let freshness = AppCacheFreshness(freshFor: 60, maximumStale: 300)

  @Test
  func automaticReadsReuseMemoryAndSwiftDataSnapshots() async throws {
    let cache = try AppDataCache.inMemory()
    let loader = IntegerLoader(values: [1, 2])
    await cache.transition(to: viewerID)

    let first = try await load(cache: cache, loader: loader)
    let memoryHit = try await load(cache: cache, loader: loader)
    await cache.clearMemory()
    let swiftDataHit = try await load(cache: cache, loader: loader)

    #expect(first == 1)
    #expect(memoryHit == 1)
    #expect(swiftDataHit == 1)
    #expect(await loader.count == 1)
  }

  @Test
  func concurrentReadsShareOneUnderlyingRequest() async throws {
    let cache = try AppDataCache.inMemory()
    let loader = IntegerLoader(values: [7, 8], delay: .milliseconds(100))
    await cache.transition(to: viewerID)

    async let first = load(cache: cache, loader: loader)
    async let second = load(cache: cache, loader: loader)
    async let third = load(cache: cache, loader: loader)
    let values = try await [first, second, third]

    #expect(values == [7, 7, 7])
    #expect(await loader.count == 1)
  }

  @Test
  func refreshBypassesAndReplacesTheSnapshot() async throws {
    let cache = try AppDataCache.inMemory()
    let loader = IntegerLoader(values: [1, 2, 3])
    await cache.transition(to: viewerID)

    #expect(try await load(cache: cache, loader: loader) == 1)
    #expect(try await load(cache: cache, loader: loader, policy: .refresh) == 2)
    #expect(try await load(cache: cache, loader: loader) == 2)
    #expect(await loader.count == 2)
  }

  @Test
  func failedRefreshPreservesTheLastUsableSnapshot() async throws {
    let cache = try AppDataCache.inMemory()
    let loader = IntegerLoader(results: [.success(1), .failure(TestFailure.unavailable)])
    await cache.transition(to: viewerID)

    #expect(try await load(cache: cache, loader: loader) == 1)
    await #expect(throws: TestFailure.self) {
      try await load(cache: cache, loader: loader, policy: .refresh)
    }
    #expect(try await load(cache: cache, loader: loader) == 1)
    #expect(await loader.count == 2)
  }

  @Test
  func aPatchedValueWinsOverAnOlderInFlightResponse() async throws {
    let cache = try AppDataCache.inMemory()
    let loader = SuspendedIntegerLoader()
    await cache.transition(to: viewerID)

    let request = Task {
      try await cache.value(for: resource, freshness: freshness) {
        await loader.load()
      }
    }
    await loader.waitUntilStarted()
    try await cache.store(2, for: resource)
    await loader.finish(with: 1)

    #expect(try await request.value == 2)
    let cached: Int = try await cache.value(for: resource, freshness: freshness) {
      Issue.record("The patched memory value should satisfy this read")
      return 3
    }
    #expect(cached == 2)
  }

  @Test
  func invalidationMarksStaleWithoutAutomaticallyRefetching() async throws {
    let cache = try AppDataCache.inMemory()
    let loader = IntegerLoader(values: [1, 2])
    await cache.transition(to: viewerID)

    #expect(try await load(cache: cache, loader: loader) == 1)
    await cache.invalidate(resource)
    #expect(await cache.state(for: resource, freshness: freshness) == .invalidated)
    #expect(try await load(cache: cache, loader: loader) == 1)
    #expect(await loader.count == 1)
  }

  @Test
  func staleSnapshotsRemainUsableUntilTheirHardLimit() async throws {
    let clock = TestAppCacheClock(now: Date(timeIntervalSince1970: 1000))
    let cache = try AppDataCache.inMemory(clock: clock)
    let loader = IntegerLoader(values: [1, 2])
    await cache.transition(to: viewerID)

    #expect(try await load(cache: cache, loader: loader) == 1)
    clock.advance(by: 120)
    #expect(await cache.state(for: resource, freshness: freshness) == .stale)
    #expect(try await load(cache: cache, loader: loader) == 1)

    clock.advance(by: 301)
    #expect(await cache.state(for: resource, freshness: freshness) == .expired)
    #expect(try await load(cache: cache, loader: loader) == 2)
    #expect(await loader.count == 2)
  }

  @Test
  func signOutPurgesThePreviousViewerNamespace() async throws {
    let cache = try AppDataCache.inMemory()
    let loader = IntegerLoader(values: [1, 2])
    await cache.transition(to: viewerID)

    #expect(try await load(cache: cache, loader: loader) == 1)
    await cache.transition(to: nil)
    await cache.transition(to: viewerID)
    #expect(try await load(cache: cache, loader: loader) == 2)
    #expect(await loader.count == 2)
  }

  @Test
  func changingEnvironmentPurgesThePreviousEnvironmentSnapshots() async throws {
    let schema = Schema([CachedServerSnapshot.self])
    let configuration = ModelConfiguration(
      "EnvironmentPurgingTests",
      schema: schema,
      isStoredInMemoryOnly: true,
      cloudKitDatabase: .none
    )
    let container = try ModelContainer(for: schema, configurations: [configuration])
    let store = SwiftDataSnapshotStore(modelContainer: container)
    let developmentCache = AppDataCache(environment: .development, store: store)
    let stagingCache = AppDataCache(environment: .staging, store: store)
    let loader = IntegerLoader(values: [1, 2])

    await developmentCache.transition(to: viewerID)
    #expect(try await load(cache: developmentCache, loader: loader) == 1)
    await stagingCache.transition(to: viewerID)
    await developmentCache.clearMemory()

    #expect(try await load(cache: developmentCache, loader: loader) == 2)
    #expect(await loader.count == 2)
  }

  @Test
  func corruptPayloadSelfHealsAsANetworkMiss() async throws {
    let cache = try AppDataCache.inMemory()
    let loader = IntegerLoader(values: [1, 2])
    await cache.transition(to: viewerID)

    #expect(try await load(cache: cache, loader: loader) == 1)
    try await cache.replacePayloadForTesting(Data([0xFF]), for: resource)
    #expect(try await load(cache: cache, loader: loader) == 2)
    #expect(try await load(cache: cache, loader: loader) == 2)
    #expect(await loader.count == 2)
  }

  @Test
  func aNewPayloadVersionDoesNotDecodeTheOldSnapshot() async throws {
    let cache = try AppDataCache.inMemory()
    let loader = IntegerLoader(values: [1, 2])
    await cache.transition(to: viewerID)

    #expect(try await load(cache: cache, loader: loader) == 1)
    let nextVersion = AppCacheResource(
      name: resource.name,
      variant: resource.variant,
      payloadVersion: 2
    )
    let value: Int = try await cache.value(for: nextVersion, freshness: freshness) {
      try await loader.load()
    }

    #expect(value == 2)
    #expect(await loader.count == 2)
  }

  private func load(
    cache: AppDataCache,
    loader: IntegerLoader,
    policy: CacheReadPolicy = .automatic
  ) async throws -> Int {
    try await cache.value(for: resource, freshness: freshness, policy: policy) {
      try await loader.load()
    }
  }
}

private actor IntegerLoader {
  private let results: [Result<Int, TestFailure>]
  private let delay: Duration?
  private var index = 0

  init(values: [Int], delay: Duration? = nil) {
    results = values.map(Result.success)
    self.delay = delay
  }

  init(results: [Result<Int, TestFailure>], delay: Duration? = nil) {
    self.results = results
    self.delay = delay
  }

  var count: Int {
    index
  }

  func load() async throws -> Int {
    let result = results[min(index, results.count - 1)]
    index += 1
    if let delay {
      try await Task.sleep(for: delay)
    }
    return try result.get()
  }
}

private actor SuspendedIntegerLoader {
  private var continuation: CheckedContinuation<Int, Never>?

  func load() async -> Int {
    await withCheckedContinuation { continuation in
      self.continuation = continuation
    }
  }

  func waitUntilStarted() async {
    while continuation == nil {
      await Task.yield()
    }
  }

  func finish(with value: Int) {
    continuation?.resume(returning: value)
    continuation = nil
  }
}

private enum TestFailure: Error {
  case unavailable
}

private final class TestAppCacheClock: AppCacheClock, @unchecked Sendable {
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
