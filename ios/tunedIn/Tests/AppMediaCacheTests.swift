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
    let signedURL = URL(string: "https://storage.example.test/object.jpg?token=private-value")!
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
    let signedURL = URL(string: "https://storage.example.test/object.jpg?token=one")!

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
    responseCache.storeCachedResponse(
      CachedURLResponse(
        response: URLResponse(
          url: try #require(resource.cacheRequest.url),
          mimeType: "image/jpeg",
          expectedContentLength: 1,
          textEncodingName: nil
        ),
        data: Data([0xFF])
      ),
      for: resource.cacheRequest
    )

    let value = try await cache.data(
      from: URL(string: "https://storage.example.test/object.jpg?token=two")!,
      for: resource
    )

    #expect(UIImage(data: value) != nil)
    #expect(await loader.count == 1)
    #expect(await diagnostics.snapshot()[.decodeFailure] == 1)
  }

  @Test
  func accountTransitionPurgesMediaResponsesAndSignedURLs() async throws {
    let loader = MediaDataLoaderSpy(responses: [Self.imageData()])
    let cache = AppMediaCache(
      environment: .development,
      urlCache: URLCache(memoryCapacity: 1_024_000, diskCapacity: 0),
      dataLoader: loader
    )
    let signedURL = URL(string: "https://storage.example.test/object.jpg?token=three")!
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
}

private actor MediaDataLoaderSpy: AppMediaDataLoading {
  private let responses: [Data]
  private let delay: Duration?
  private(set) var count = 0

  init(responses: [Data], delay: Duration? = nil) {
    self.responses = responses
    self.delay = delay
  }

  func data(for request: URLRequest) async throws -> (Data, URLResponse) {
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
