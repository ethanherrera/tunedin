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
}

private actor SignedURLLoaderSpy {
  private(set) var count = 0

  func load(version: Int) async throws -> URL {
    count += 1
    try await Task.sleep(for: .milliseconds(50))
    return URL(string: "https://example.test/private-image?v=\(version)&attempt=\(count)")!
  }
}
