import CryptoKit
import Foundation
import UIKit

struct AppMediaResource: Hashable, Sendable {
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

  var cacheRequest: URLRequest {
    let components = [kind.rawValue, id.uuidString.lowercased(), String(version)]
    let digest = SHA256.hash(data: Data(components.joined(separator: "\u{1F}").utf8))
      .map { String(format: "%02x", $0) }
      .joined()
    let url = URL(string: "https://media-cache.tunedin.invalid/v1/\(digest)")!
    return URLRequest(url: url)
  }
}

protocol AppMediaDataLoading: Sendable {
  func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

struct URLSessionMediaDataLoader: AppMediaDataLoading {
  let session: URLSession

  func data(for request: URLRequest) async throws -> (Data, URLResponse) {
    try await session.data(for: request)
  }
}

actor AppMediaCache {
  static let memoryCapacity = 32 * 1_024 * 1_024
  static let diskCapacity = 128 * 1_024 * 1_024

  nonisolated let signedURLs: SignedURLCache

  private struct DownloadedMedia: Sendable {
    let data: Data
    let mimeType: String
  }

  private struct InFlightRequest {
    let id: UUID
    let task: Task<DownloadedMedia, any Error>
  }

  private let environment: AppEnvironment
  private let urlCache: URLCache
  private let dataLoader: any AppMediaDataLoading
  private let diagnostics: AppCacheDiagnostics
  private let scopeMarkerURL: URL?
  private var viewerID: UUID?
  private var hasTransitioned = false
  private var inFlight: [AppMediaResource: InFlightRequest] = [:]

  init(
    environment: AppEnvironment,
    urlCache: URLCache,
    dataLoader: any AppMediaDataLoading,
    diagnostics: AppCacheDiagnostics = AppCacheDiagnostics(),
    scopeMarkerURL: URL? = nil
  ) {
    self.environment = environment
    self.urlCache = urlCache
    self.dataLoader = dataLoader
    self.diagnostics = diagnostics
    self.scopeMarkerURL = scopeMarkerURL
    signedURLs = SignedURLCache(diagnostics: diagnostics)
  }

  static func live(
    environment: AppEnvironment,
    diagnostics: AppCacheDiagnostics,
    fileManager: FileManager = .default
  ) throws -> AppMediaCache {
    let baseDirectory = try AppCacheStorage.liveBaseDirectory(fileManager: fileManager)
    let directory = try AppCacheStorage.prepareMediaDirectory(
      environment: environment,
      baseDirectory: baseDirectory,
      fileManager: fileManager
    )
    let responsesDirectory = directory.appending(path: "Responses", directoryHint: .isDirectory)
    try AppCacheStorage.prepareDirectory(responsesDirectory, fileManager: fileManager)
    let responseCache = URLCache(
      memoryCapacity: memoryCapacity,
      diskCapacity: diskCapacity,
      directory: responsesDirectory
    )
    let session = URLSession(configuration: AppNetworkSession.makeMediaConfiguration())
    return AppMediaCache(
      environment: environment,
      urlCache: responseCache,
      dataLoader: URLSessionMediaDataLoader(session: session),
      diagnostics: diagnostics,
      scopeMarkerURL: directory.appending(path: "scope", directoryHint: .notDirectory)
    )
  }

  static func ephemeral(
    environment: AppEnvironment = .development,
    diagnostics: AppCacheDiagnostics = AppCacheDiagnostics()
  ) -> AppMediaCache {
    let responseCache = URLCache(memoryCapacity: memoryCapacity, diskCapacity: 0)
    let session = URLSession(configuration: AppNetworkSession.makeMediaConfiguration())
    return AppMediaCache(
      environment: environment,
      urlCache: responseCache,
      dataLoader: URLSessionMediaDataLoader(session: session),
      diagnostics: diagnostics
    )
  }

  func transition(to newViewerID: UUID?) async {
    guard !hasTransitioned || viewerID != newViewerID else { return }
    hasTransitioned = true
    viewerID = newViewerID
    await signedURLs.removeAll()
    cancelInFlightRequests()

    let nextScope = newViewerID.map { scopeHash(viewerID: $0) }
    let storedScope = readStoredScope()
    if storedScope != nextScope {
      urlCache.removeAllCachedResponses()
    }
    writeStoredScope(nextScope)
  }

  func data(from sourceURL: URL, for resource: AppMediaResource) async throws -> Data {
    let cacheRequest = resource.cacheRequest
    var foundCorruptResponse = false
    if let cached = urlCache.cachedResponse(for: cacheRequest) {
      if Self.isValidImage(cached.data) {
        await diagnostics.record(.hit)
        return cached.data
      }
      urlCache.removeCachedResponse(for: cacheRequest)
      foundCorruptResponse = true
    }

    if let request = inFlight[resource] {
      if foundCorruptResponse {
        await diagnostics.record(.decodeFailure)
      }
      await diagnostics.record(.miss)
      await diagnostics.record(.coalesced)
      return try await request.task.value.data
    }

    let dataLoader = dataLoader
    let request = InFlightRequest(
      id: UUID(),
      task: Task {
        try await Self.download(from: sourceURL, using: dataLoader)
      }
    )
    inFlight[resource] = request
    if foundCorruptResponse {
      await diagnostics.record(.decodeFailure)
    }
    await diagnostics.record(.miss)
    await diagnostics.record(.network)
    do {
      let download = try await request.task.value
      clear(request, for: resource)
      guard Self.isValidImage(download.data) else {
        await diagnostics.record(.decodeFailure)
        throw AppMediaCacheError.invalidImage
      }
      store(download, for: cacheRequest)
      return download.data
    } catch {
      clear(request, for: resource)
      throw error
    }
  }

  func remove(_ resource: AppMediaResource) {
    urlCache.removeCachedResponse(for: resource.cacheRequest)
    inFlight[resource]?.task.cancel()
    inFlight[resource] = nil
  }

  func reset() async {
    urlCache.removeAllCachedResponses()
    cancelInFlightRequests()
    await signedURLs.removeAll()
  }

  #if DEBUG
    func contains(_ resource: AppMediaResource) -> Bool {
      urlCache.cachedResponse(for: resource.cacheRequest) != nil
    }

    func configuredCapacities() -> (memory: Int, disk: Int) {
      (urlCache.memoryCapacity, urlCache.diskCapacity)
    }
  #endif

  private static func download(
    from sourceURL: URL,
    using dataLoader: any AppMediaDataLoading
  ) async throws -> DownloadedMedia {
    if sourceURL.isFileURL {
      let data = try await Task.detached(priority: .utility) {
        try Data(contentsOf: sourceURL)
      }.value
      return DownloadedMedia(data: data, mimeType: "image/jpeg")
    }

    var request = URLRequest(url: sourceURL)
    request.cachePolicy = .reloadIgnoringLocalCacheData
    let (data, response) = try await dataLoader.data(for: request)
    if let httpResponse = response as? HTTPURLResponse,
       !(200 ..< 300).contains(httpResponse.statusCode) {
      throw AppMediaCacheError.httpStatus(httpResponse.statusCode)
    }
    return DownloadedMedia(
      data: data,
      mimeType: response.mimeType ?? "application/octet-stream"
    )
  }

  private static func isValidImage(_ data: Data) -> Bool {
    !data.isEmpty && UIImage(data: data) != nil
  }

  private func store(_ download: DownloadedMedia, for request: URLRequest) {
    guard let url = request.url else { return }
    let response = URLResponse(
      url: url,
      mimeType: download.mimeType,
      expectedContentLength: download.data.count,
      textEncodingName: nil
    )
    urlCache.storeCachedResponse(
      CachedURLResponse(
        response: response,
        data: download.data,
        storagePolicy: .allowed
      ),
      for: request
    )
  }

  private func clear(_ request: InFlightRequest, for resource: AppMediaResource) {
    guard inFlight[resource]?.id == request.id else { return }
    inFlight[resource] = nil
  }

  private func cancelInFlightRequests() {
    for request in inFlight.values {
      request.task.cancel()
    }
    inFlight.removeAll()
  }

  private func scopeHash(viewerID: UUID) -> String {
    let scope = "\(environment.rawValue)\u{1F}\(viewerID.uuidString.lowercased())"
    return SHA256.hash(data: Data(scope.utf8))
      .map { String(format: "%02x", $0) }
      .joined()
  }

  private func readStoredScope() -> String? {
    guard let scopeMarkerURL,
          let data = try? Data(contentsOf: scopeMarkerURL),
          let value = String(data: data, encoding: .utf8),
          !value.isEmpty
    else { return nil }
    return value
  }

  private func writeStoredScope(_ scope: String?) {
    guard let scopeMarkerURL else { return }
    if let scope {
      try? AppCacheStorage.writeProtected(Data(scope.utf8), to: scopeMarkerURL)
    } else if FileManager.default.fileExists(atPath: scopeMarkerURL.path) {
      try? FileManager.default.removeItem(at: scopeMarkerURL)
    }
  }
}

enum AppMediaCacheError: LocalizedError {
  case httpStatus(Int)
  case invalidImage

  var errorDescription: String? {
    switch self {
    case .httpStatus:
      "The image could not be downloaded."
    case .invalidImage:
      "The downloaded file is not a valid image."
    }
  }
}
