import Foundation
import Testing
@testable import tunedIn

struct SignedURLCacheTests {
  @Test
  func identicalRequestsCoalesceAndVersionsStayIndependent() async throws {
    let diagnostics = AppCacheDiagnostics()
    let cache = SignedURLCache(diagnostics: diagnostics)
    let loader = SignedURLLoaderSpy()
    let profileID = UUID()
    let firstKey = SignedURLCacheKey.avatar(profileID: profileID, version: 1)
    let secondKey = SignedURLCacheKey.avatar(profileID: profileID, version: 2)

    async let first = cache.value(for: firstKey) { try await loader.load(version: 1) }
    async let coalesced = cache.value(for: firstKey) { try await loader.load(version: 1) }
    let firstValue = try await first
    let coalescedValue = try await coalesced
    #expect(firstValue == coalescedValue)
    #expect(await loader.count == 1)

    _ = try await cache.value(for: firstKey) { try await loader.load(version: 1) }
    _ = try await cache.value(for: secondKey) { try await loader.load(version: 2) }
    #expect(await loader.count == 2)

    let snapshot = await diagnostics.snapshot()
    #expect(snapshot[.hit] == 1)
    #expect(snapshot[.coalesced] == 1)
    #expect(snapshot[.network] == 2)
  }

  @Test
  func expirationAndExplicitRemovalNeverReuseAnOldURL() async throws {
    let cache = SignedURLCache(lifetime: 60)
    let loader = SignedURLLoaderSpy()
    let profileID = UUID()
    let key = SignedURLCacheKey.avatar(profileID: profileID, version: 1)
    let start = Date(timeIntervalSince1970: 1_000)

    _ = try await cache.value(for: key, now: start) { try await loader.load(version: 1) }
    _ = try await cache.value(for: key, now: start.addingTimeInterval(61)) {
      try await loader.load(version: 1)
    }
    await cache.remove(kind: .avatar, id: profileID)
    _ = try await cache.value(for: key, now: start.addingTimeInterval(62)) {
      try await loader.load(version: 1)
    }

    #expect(await loader.count == 3)
  }

  @Test
  func aNewCacheInstanceNeverRestoresASignedURL() async throws {
    let loader = SignedURLLoaderSpy()
    let key = SignedURLCacheKey.avatar(profileID: UUID(), version: 1)

    _ = try await SignedURLCache().value(for: key) {
      try await loader.load(version: 1)
    }
    _ = try await SignedURLCache().value(for: key) {
      try await loader.load(version: 1)
    }

    #expect(await loader.count == 2)
  }

  @Test
  func removeAllRejectsAnOlderLoadThatIgnoresCancellation() async throws {
    let cache = SignedURLCache()
    let loader = SuspendedSignedURLLoader()
    let key = SignedURLCacheKey.avatar(profileID: UUID(), version: 1)
    let request = Task {
      try await cache.value(for: key) {
        await loader.load()
      }
    }
    await loader.waitUntilStarted()
    await cache.removeAll()
    await loader.finish()

    await #expect(throws: CancellationError.self) {
      try await request.value
    }
    #expect(await cache.entryCount() == 0)
  }

  @Test
  func transitionRejectsSignedURLReadsUntilItFinishes() async throws {
    let cache = SignedURLCache()
    let key = SignedURLCacheKey.avatar(profileID: UUID(), version: 1)
    await cache.beginTransition()

    await #expect(throws: CancellationError.self) {
      try await cache.value(for: key) {
        URL(string: "https://example.test/private-image?during-transition=true")!
      }
    }

    await cache.endTransition()
    #expect(await cache.entryCount() == 0)
  }

  @Test
  func cancelledReadReleasedAfterTransitionCannotCacheAnOldURL() async throws {
    let cache = SignedURLCache()
    let gate = SuspendedStartGate()
    let key = SignedURLCacheKey.avatar(profileID: UUID(), version: 1)
    let request = Task {
      await gate.wait()
      return try await cache.value(for: key) {
        URL(string: "https://example.test/private-image?old-account=true")!
      }
    }
    await gate.waitUntilStarted()
    await cache.beginTransition()
    await cache.endTransition()
    request.cancel()
    await gate.open()

    await #expect(throws: CancellationError.self) {
      try await request.value
    }
    #expect(await cache.entryCount() == 0)
  }

  @Test
  func targetedRemovalDoesNotCancelAnUnrelatedSignedURLLoad() async throws {
    let diagnostics = AppCacheDiagnostics()
    let cache = SignedURLCache(diagnostics: diagnostics)
    let firstLoader = SuspendedSignedURLLoader()
    let secondLoader = SuspendedSignedURLLoader()
    let firstID = UUID()
    let secondID = UUID()
    let firstKey = SignedURLCacheKey.avatar(profileID: firstID, version: 1)
    let secondKey = SignedURLCacheKey.avatar(profileID: secondID, version: 1)
    let first = Task {
      try await cache.value(for: firstKey) { await firstLoader.load() }
    }
    let coalesced = Task {
      try await cache.value(for: firstKey) { await firstLoader.load() }
    }
    let second = Task {
      try await cache.value(for: secondKey) { await secondLoader.load() }
    }
    await firstLoader.waitUntilStarted()
    await secondLoader.waitUntilStarted()
    while await diagnostics.snapshot()[.coalesced] != 1 {
      await Task.yield()
    }

    await cache.remove(kind: .avatar, id: firstID)
    await firstLoader.finish(
      with: URL(string: "https://example.test/private-image?removed=true")!
    )
    let expectedSecondURL = URL(string: "https://example.test/private-image?kept=true")!
    await secondLoader.finish(with: expectedSecondURL)

    await #expect(throws: CancellationError.self) {
      try await first.value
    }
    await #expect(throws: CancellationError.self) {
      try await coalesced.value
    }
    #expect(try await second.value == expectedSecondURL)
    #expect(await cache.entryCount() == 1)
  }
}

private actor SignedURLLoaderSpy {
  private(set) var count = 0

  func load(version: Int) async throws -> URL {
    count += 1
    try await Task.sleep(for: .milliseconds(50))
    return URL(string: "https://example.test/private-image?v=\(version)&attempt=\(count)")!
  }
}

private actor SuspendedSignedURLLoader {
  private var continuation: CheckedContinuation<URL, Never>?

  func load() async -> URL {
    await withCheckedContinuation { continuation in
      self.continuation = continuation
    }
  }

  func waitUntilStarted() async {
    while continuation == nil {
      await Task.yield()
    }
  }

  func finish(
    with url: URL = URL(string: "https://example.test/private-image?stale=true")!
  ) {
    continuation?.resume(returning: url)
    continuation = nil
  }
}

private actor SuspendedStartGate {
  private var continuation: CheckedContinuation<Void, Never>?

  func wait() async {
    await withCheckedContinuation { continuation in
      self.continuation = continuation
    }
  }

  func waitUntilStarted() async {
    while continuation == nil {
      await Task.yield()
    }
  }

  func open() {
    continuation?.resume()
    continuation = nil
  }
}
