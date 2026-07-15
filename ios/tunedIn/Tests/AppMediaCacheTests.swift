import CryptoKit
import Foundation
import Testing
@testable import tunedIn
import UIKit

struct AppMediaCacheTests {
  private let viewerID = UUID(uuidString: "71000000-0000-0000-0000-000000000001")!
  private let otherViewerID = UUID(uuidString: "71000000-0000-0000-0000-000000000002")!
  private let resource = AppMediaResource.avatar(
    profileID: UUID(uuidString: "72000000-0000-0000-0000-000000000001")!,
    version: 1
  )
  private let otherResource = AppMediaResource.avatar(
    profileID: UUID(uuidString: "72000000-0000-0000-0000-000000000002")!,
    version: 1
  )

  @Test
  func repeatedDisplayUsesOpaqueResponseCacheWithoutPersistingTheSignedURL() async throws {
    let diagnostics = AppCacheDiagnostics()
    let responseCache = URLCache(memoryCapacity: 1_024_000, diskCapacity: 0)
    let loader = MediaDataLoaderSpy(responses: [Self.imageData()])
    let cache = AppMediaCache(
      environment: .development,
      urlCache: responseCache,
      dataLoader: loader,
      diagnostics: diagnostics
    )
    let signedURL = try #require(URL(string: "https://storage.example.test/object.jpg?token=private-value"))
    await cache.transition(to: viewerID)

    let first = try await cache.data(from: signedURL, for: resource)
    let second = try await cache.data(from: signedURL, for: resource)

    #expect(first == second)
    #expect(await loader.count == 1)
    let cachedURL = responseCache.cachedResponse(for: resource.cacheRequest)?.response.url
    #expect(cachedURL?.host == "media-cache.tunedin.invalid")
    #expect(cachedURL?.absoluteString.contains("private-value") == false)
    #expect(cachedURL?.absoluteString.contains("object.jpg") == false)
    let snapshot = await diagnostics.snapshot()
    #expect(snapshot[.hit] == 1)
    #expect(snapshot[.miss] == 1)
    #expect(snapshot[.network] == 1)
  }

  @Test
  func concurrentImageLoadsShareOneDownload() async throws {
    let diagnostics = AppCacheDiagnostics()
    let loader = MediaDataLoaderSpy(
      responses: [Self.imageData()],
      delay: .milliseconds(75)
    )
    let cache = AppMediaCache(
      environment: .development,
      urlCache: URLCache(memoryCapacity: 1_024_000, diskCapacity: 0),
      dataLoader: loader,
      diagnostics: diagnostics
    )
    let signedURL = try #require(URL(string: "https://storage.example.test/object.jpg?token=one"))

    async let first = cache.data(from: signedURL, for: resource)
    async let second = cache.data(from: signedURL, for: resource)
    let values = try await [first, second]

    #expect(values[0] == values[1])
    #expect(await loader.count == 1)
    #expect(await diagnostics.snapshot()[.coalesced] == 1)
  }

  @Test
  func corruptCachedMediaSelfHealsAsANetworkMiss() async throws {
    let diagnostics = AppCacheDiagnostics()
    let responseCache = URLCache(memoryCapacity: 1_024_000, diskCapacity: 0)
    let loader = MediaDataLoaderSpy(responses: [Self.imageData()])
    let cache = AppMediaCache(
      environment: .development,
      urlCache: responseCache,
      dataLoader: loader,
      diagnostics: diagnostics
    )
    try responseCache.storeCachedResponse(
      CachedURLResponse(
        response: URLResponse(
          url: #require(resource.cacheRequest.url),
          mimeType: "image/jpeg",
          expectedContentLength: 1,
          textEncodingName: nil
        ),
        data: Data([0xFF])
      ),
      for: resource.cacheRequest
    )

    let value = try await cache.data(
      from: #require(URL(string: "https://storage.example.test/object.jpg?token=two")),
      for: resource
    )

    #expect(UIImage(data: value) != nil)
    #expect(await loader.count == 1)
    #expect(await diagnostics.snapshot()[.decodeFailure] == 1)
  }

  @Test
  func concurrentCorruptDownloadsRejectEveryWaiter() async throws {
    let diagnostics = AppCacheDiagnostics()
    let loader = MediaDataLoaderSpy(responses: [Data([0xFF])], delay: .milliseconds(75))
    let cache = AppMediaCache(
      environment: .development,
      urlCache: URLCache(memoryCapacity: 1_024_000, diskCapacity: 0),
      dataLoader: loader,
      diagnostics: diagnostics
    )
    let sourceURL = try #require(URL(string: "https://storage.example.test/corrupt.jpg"))
    let first = Task { try await cache.data(from: sourceURL, for: resource) }
    let second = Task { try await cache.data(from: sourceURL, for: resource) }
    while await diagnostics.snapshot()[.coalesced] != 1 {
      await Task.yield()
    }

    await #expect(throws: AppMediaCacheError.self) { try await first.value }
    await #expect(throws: AppMediaCacheError.self) { try await second.value }
  }

  @Test
  func accountTransitionPurgesMediaResponsesAndSignedURLs() async throws {
    let loader = MediaDataLoaderSpy(responses: [Self.imageData()])
    let cache = AppMediaCache(
      environment: .development,
      urlCache: URLCache(memoryCapacity: 1_024_000, diskCapacity: 0),
      dataLoader: loader
    )
    let signedURL = try #require(URL(string: "https://storage.example.test/object.jpg?token=three"))
    await cache.transition(to: viewerID)
    _ = try await cache.data(from: signedURL, for: resource)
    _ = try await cache.signedURLs.value(
      for: .avatar(profileID: resource.id, version: resource.version)
    ) {
      signedURL
    }

    #expect(await cache.contains(resource))
    #expect(await cache.signedURLs.entryCount() == 1)
    await cache.transition(to: otherViewerID)
    #expect(await cache.contains(resource) == false)
    #expect(await cache.signedURLs.entryCount() == 0)
  }

  @Test
  func signOutTransitionPurgesMediaResponsesAndSignedURLs() async throws {
    let loader = MediaDataLoaderSpy(responses: [Self.imageData()])
    let cache = AppMediaCache(
      environment: .development,
      urlCache: URLCache(memoryCapacity: 1_024_000, diskCapacity: 0),
      dataLoader: loader
    )
    let signedURL = try #require(URL(string: "https://storage.example.test/object.jpg?token=four"))
    await cache.transition(to: viewerID)
    _ = try await cache.data(from: signedURL, for: resource)
    _ = try await cache.signedURLs.value(
      for: .avatar(profileID: resource.id, version: resource.version)
    ) {
      signedURL
    }

    #expect(await cache.contains(resource))
    #expect(await cache.signedURLs.entryCount() == 1)
    await cache.transition(to: nil)
    #expect(await cache.contains(resource) == false)
    #expect(await cache.signedURLs.entryCount() == 0)
  }

  @Test
  func signOutTransitionRejectsAnOlderDownloadThatIgnoresCancellation() async throws {
    let loader = SuspendedMediaDataLoader()
    let cache = AppMediaCache(
      environment: .development,
      urlCache: URLCache(memoryCapacity: 1_024_000, diskCapacity: 0),
      dataLoader: loader
    )
    let signedURL = try #require(URL(string: "https://storage.example.test/object.jpg?token=five"))
    await cache.transition(to: viewerID)

    let request = Task {
      try await cache.data(from: signedURL, for: resource)
    }
    await loader.waitUntilStarted()
    await cache.transition(to: nil)
    await loader.finish(with: Self.imageData())

    await #expect(throws: CancellationError.self) {
      try await request.value
    }
    #expect(await cache.contains(resource) == false)
  }

  @Test
  func cancelledDownloadReleasedAfterSignOutCannotCacheOldMedia() async throws {
    let loader = MediaDataLoaderSpy(responses: [Self.imageData()])
    let gate = SuspendedMediaStartGate()
    let cache = AppMediaCache(
      environment: .development,
      urlCache: URLCache(memoryCapacity: 1_024_000, diskCapacity: 0),
      dataLoader: loader
    )
    let signedURL = try #require(URL(string: "https://storage.example.test/old-account.jpg"))
    await cache.transition(to: viewerID)
    let request = Task {
      await gate.wait()
      return try await cache.data(from: signedURL, for: resource)
    }
    await gate.waitUntilStarted()
    await cache.transition(to: nil)
    request.cancel()
    await gate.open()

    await #expect(throws: CancellationError.self) {
      try await request.value
    }
    #expect(await loader.didLoad == false)
    #expect(await cache.contains(resource) == false)
  }

  @Test
  func targetedRemovalRejectsRemovedWaitersWithoutCancellingAnUnrelatedDownload() async throws {
    let diagnostics = AppCacheDiagnostics()
    let loader = MultiSuspendedMediaDataLoader()
    let cache = AppMediaCache(
      environment: .development,
      urlCache: URLCache(memoryCapacity: 1_024_000, diskCapacity: 0),
      dataLoader: loader,
      diagnostics: diagnostics
    )
    let firstURL = try #require(URL(string: "https://storage.example.test/first.jpg"))
    let secondURL = try #require(URL(string: "https://storage.example.test/second.jpg"))
    let first = Task { try await cache.data(from: firstURL, for: resource) }
    let coalesced = Task { try await cache.data(from: firstURL, for: resource) }
    let second = Task { try await cache.data(from: secondURL, for: otherResource) }
    await loader.waitUntilStarted([firstURL, secondURL])
    while await diagnostics.snapshot()[.coalesced] != 1 {
      await Task.yield()
    }

    await cache.remove(resource)
    await loader.finish(firstURL, with: Self.imageData())
    await loader.finish(secondURL, with: Self.imageData())

    await #expect(throws: CancellationError.self) {
      try await first.value
    }
    await #expect(throws: CancellationError.self) {
      try await coalesced.value
    }
    #expect(try await second.value == Self.imageData())
    #expect(await cache.contains(resource) == false)
    #expect(await cache.contains(otherResource))
  }

  @Test
  func concurrentSameTargetTransitionWaitsForTheActivePurge() async {
    let checkpoint = SerialTransitionCheckpoint()
    let cache = AppMediaCache(
      environment: .development,
      urlCache: URLCache(memoryCapacity: 1_024_000, diskCapacity: 0),
      dataLoader: MediaDataLoaderSpy(responses: [Self.imageData()]),
      transitionCheckpoint: { await checkpoint.pause() }
    )
    let first = Task { await cache.transition(to: viewerID) }
    await checkpoint.waitUntilPaused(total: 1)
    let second = Task { await cache.transition(to: viewerID) }
    while await cache.transitionWaiterCountForTesting() != 1 {
      await Task.yield()
    }

    await checkpoint.releaseNext()
    await first.value
    await second.value

    #expect(await checkpoint.pauseCount == 1)
    #expect(await cache.currentViewerIDForTesting() == viewerID)
    #expect(await cache.transitionWaiterCountForTesting() == 0)
  }

  @Test
  func concurrentDifferentTargetTransitionsPersistTheNewestScope() async throws {
    let checkpoint = SerialTransitionCheckpoint()
    let directory = FileManager.default.temporaryDirectory.appending(
      path: "media-transition-\(UUID().uuidString)",
      directoryHint: .isDirectory
    )
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let scopeMarkerURL = directory.appending(path: "scope", directoryHint: .notDirectory)
    let cache = AppMediaCache(
      environment: .development,
      urlCache: URLCache(memoryCapacity: 1_024_000, diskCapacity: 0),
      dataLoader: MediaDataLoaderSpy(responses: [Self.imageData()]),
      scopeMarkerURL: scopeMarkerURL,
      transitionCheckpoint: { await checkpoint.pause() }
    )
    let first = Task { await cache.transition(to: viewerID) }
    await checkpoint.waitUntilPaused(total: 1)
    let second = Task { await cache.transition(to: otherViewerID) }
    while await cache.transitionWaiterCountForTesting() != 1 {
      await Task.yield()
    }

    await checkpoint.releaseNext()
    await checkpoint.waitUntilPaused(total: 2)
    await first.value
    #expect(try String(contentsOf: scopeMarkerURL, encoding: .utf8) == scopeHash(for: viewerID))

    await checkpoint.releaseNext()
    await second.value

    #expect(await cache.currentViewerIDForTesting() == otherViewerID)
    #expect(try String(contentsOf: scopeMarkerURL, encoding: .utf8) == scopeHash(for: otherViewerID))
  }

  @Test
  func productionCacheUsesTheConfiguredMemoryAndDiskBudgets() async {
    let cache = AppMediaCache.ephemeral()
    let capacities = await cache.configuredCapacities()

    #expect(capacities.memory == AppMediaCache.memoryCapacity)
    #expect(capacities.disk == 0)
    #expect(AppMediaCache.diskCapacity == 128 * 1_024 * 1_024)
  }

  private static func imageData() -> Data {
    UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4)).image { context in
      UIColor.systemRed.setFill()
      context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
    }.pngData()!
  }

  private func scopeHash(for viewerID: UUID) -> String {
    let scope = "\(AppEnvironment.development.rawValue)\u{1F}\(viewerID.uuidString.lowercased())"
    return SHA256.hash(data: Data(scope.utf8))
      .map { String(format: "%02x", $0) }
      .joined()
  }
}

private actor MediaDataLoaderSpy: AppMediaDataLoading {
  private let responses: [Data]
  private let delay: Duration?
  private(set) var count = 0
  private(set) var didLoad = false

  init(responses: [Data], delay: Duration? = nil) {
    self.responses = responses
    self.delay = delay
  }

  func data(for request: URLRequest) async throws -> (Data, URLResponse) {
    didLoad = true
    let index = count
    count += 1
    if let delay {
      try await Task.sleep(for: delay)
    }
    let response = HTTPURLResponse(
      url: request.url!,
      statusCode: 200,
      httpVersion: nil,
      headerFields: ["Content-Type": "image/png"]
    )!
    return (responses[min(index, responses.count - 1)], response)
  }
}

private actor SuspendedMediaDataLoader: AppMediaDataLoading {
  private var continuation: CheckedContinuation<(Data, URLResponse), Never>?
  private var requestURL: URL?

  func data(for request: URLRequest) async throws -> (Data, URLResponse) {
    requestURL = request.url
    return await withCheckedContinuation { continuation in
      self.continuation = continuation
    }
  }

  func waitUntilStarted() async {
    while continuation == nil {
      await Task.yield()
    }
  }

  func finish(with data: Data) {
    let response = HTTPURLResponse(
      url: requestURL!,
      statusCode: 200,
      httpVersion: nil,
      headerFields: ["Content-Type": "image/png"]
    )!
    continuation?.resume(returning: (data, response))
    continuation = nil
  }
}

private actor MultiSuspendedMediaDataLoader: AppMediaDataLoading {
  private var continuations: [URL: CheckedContinuation<(Data, URLResponse), Never>] = [:]

  func data(for request: URLRequest) async throws -> (Data, URLResponse) {
    await withCheckedContinuation { continuation in
      continuations[request.url!] = continuation
    }
  }

  func waitUntilStarted(_ urls: [URL]) async {
    while !urls.allSatisfy({ continuations[$0] != nil }) {
      await Task.yield()
    }
  }

  func finish(_ url: URL, with data: Data) {
    let response = HTTPURLResponse(
      url: url,
      statusCode: 200,
      httpVersion: nil,
      headerFields: ["Content-Type": "image/png"]
    )!
    continuations[url]?.resume(returning: (data, response))
    continuations[url] = nil
  }
}

private actor SuspendedMediaStartGate {
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

private actor SerialTransitionCheckpoint {
  private var continuations: [CheckedContinuation<Void, Never>] = []
  private(set) var pauseCount = 0

  func pause() async {
    await withCheckedContinuation { continuation in
      pauseCount += 1
      continuations.append(continuation)
    }
  }

  func waitUntilPaused(total: Int) async {
    while pauseCount < total || continuations.isEmpty {
      await Task.yield()
    }
  }

  func releaseNext() {
    continuations.removeFirst().resume()
  }
}
