import CryptoKit
import Foundation
import UIKit

struct AppMediaResource: Hashable, Sendable {
  enum Kind: String, Sendable {
    case avatar
    case postMedia = "post-media"
    case eventCover = "event-cover"
  }

  let kind: Kind
  let id: UUID
  let version: Int64

  static func avatar(profileID: UUID, version: Int64) -> Self {
    Self(kind: .avatar, id: profileID, version: version)
  }

  static func postMedia(mediaID: UUID, version: Int64) -> Self {
    Self(kind: .postMedia, id: mediaID, version: version)
  }

  static func eventCover(eventID: UUID, version: Int64) -> Self {
    Self(kind: .eventCover, id: eventID, version: version)
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
  static let memoryCapacity = 32 * 1024 * 1024
  static let diskCapacity = 128 * 1024 * 1024

  nonisolated let signedURLs: SignedURLCache

  private struct DownloadedMedia: Sendable {
    let data: Data
    let mimeType: String
  }

  private struct InFlightRequest {
    let id: UUID
    let cacheGeneration: Int
    let task: Task<DownloadedMedia, any Error>
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

  private let environment: AppEnvironment
  private let urlCache: URLCache
  private let dataLoader: any AppMediaDataLoading
  private let diagnostics: AppCacheDiagnostics
  private let scopeMarkerURL: URL?
  private let transitionCheckpoint: (@Sendable () async -> Void)?
  private var viewerID: UUID?
  private var hasTransitioned = false
  private var transitionLockIsHeld = false
  private var transitionWaiters: [CheckedContinuation<Void, Never>] = []
  private var cacheGeneration = 0
  private var activeCacheTransitions = 0
  private var activeOperations: [AppMediaResource: ActiveOperation] = [:]
  private var inFlight: [AppMediaResource: InFlightRequest] = [:]

  init(
    environment: AppEnvironment,
    urlCache: URLCache,
    dataLoader: any AppMediaDataLoading,
    diagnostics: AppCacheDiagnostics = AppCacheDiagnostics(),
    scopeMarkerURL: URL? = nil,
    transitionCheckpoint: (@Sendable () async -> Void)? = nil
  ) {
    self.environment = environment
    self.urlCache = urlCache
    self.dataLoader = dataLoader
    self.diagnostics = diagnostics
    self.scopeMarkerURL = scopeMarkerURL
    self.transitionCheckpoint = transitionCheckpoint
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
    await acquireTransitionLock()
    defer { releaseTransitionLock() }
    guard !hasTransitioned || viewerID != newViewerID else { return }
    let changedViewerInProcess = hasTransitioned && viewerID != newViewerID
    hasTransitioned = true
    viewerID = newViewerID
    activeCacheTransitions += 1
    defer { activeCacheTransitions -= 1 }
    cancelInFlightRequests()
    await signedURLs.beginTransition()
    if let transitionCheckpoint {
      await transitionCheckpoint()
    }

    let nextScope = newViewerID.map { scopeHash(viewerID: $0) }
    let storedScope = readStoredScope()
    if changedViewerInProcess || storedScope != nextScope {
      urlCache.removeAllCachedResponses()
    }
    writeStoredScope(nextScope)
    await signedURLs.endTransition()
  }

  func data(from sourceURL: URL, for resource: AppMediaResource) async throws -> Data {
    try Task.checkCancellation()
    guard activeCacheTransitions == 0 else {
      throw CancellationError()
    }
    let operation = acquireOperation(for: resource)
    defer { release(operation, for: resource) }
    let cacheRequest = resource.cacheRequest
    var foundCorruptResponse = false
    if let cached = urlCache.cachedResponse(for: cacheRequest) {
      if Self.isValidImage(cached.data) {
        await diagnostics.record(.hit)
        try ensureValid(operation, for: resource)
        return cached.data
      }
      urlCache.removeCachedResponse(for: cacheRequest)
      foundCorruptResponse = true
    }

    if let request = inFlight[resource] {
      if foundCorruptResponse {
        await diagnostics.record(.decodeFailure)
        try ensureValid(operation, for: resource)
      }
      await diagnostics.record(.miss)
      try ensureValid(operation, for: resource)
      await diagnostics.record(.coalesced)
      try ensureValid(operation, for: resource)
      let download = try await request.task.value
      try ensureValid(operation, for: resource, request: request)
      guard Self.isValidImage(download.data) else {
        await diagnostics.record(.decodeFailure)
        try ensureValid(operation, for: resource, request: request)
        throw AppMediaCacheError.invalidImage
      }
      return download.data
    }

    let dataLoader = dataLoader
    let request = InFlightRequest(
      id: UUID(),
      cacheGeneration: cacheGeneration,
      task: Task {
        try await Self.download(from: sourceURL, using: dataLoader)
      }
    )
    inFlight[resource] = request
    do {
      if foundCorruptResponse {
        await diagnostics.record(.decodeFailure)
        try ensureValid(operation, for: resource, request: request)
      }
      await diagnostics.record(.miss)
      try ensureValid(operation, for: resource, request: request)
      await diagnostics.record(.network)
      try ensureValid(operation, for: resource, request: request)
      let download = try await request.task.value
      try ensureValid(operation, for: resource, request: request)
      guard Self.isValidImage(download.data) else {
        clear(request, for: resource)
        await diagnostics.record(.decodeFailure)
        try ensureValid(operation, for: resource, request: request)
        throw AppMediaCacheError.invalidImage
      }
      store(download, for: cacheRequest)
      clear(request, for: resource)
      return download.data
    } catch {
      clear(request, for: resource)
      throw error
    }
  }

  func remove(_ resource: AppMediaResource) {
    activeOperations[resource] = nil
    if let request = inFlight[resource] {
      request.task.cancel()
      inFlight[resource] = nil
    }
    urlCache.removeCachedResponse(for: resource.cacheRequest)
  }

  func reset() async {
    await acquireTransitionLock()
    defer { releaseTransitionLock() }
    activeCacheTransitions += 1
    defer { activeCacheTransitions -= 1 }
    urlCache.removeAllCachedResponses()
    cancelInFlightRequests()
    await signedURLs.beginTransition()
    await signedURLs.endTransition()
  }

  #if DEBUG
    func contains(_ resource: AppMediaResource) -> Bool {
      urlCache.cachedResponse(for: resource.cacheRequest) != nil
    }

    func configuredCapacities() -> (memory: Int, disk: Int) {
      (urlCache.memoryCapacity, urlCache.diskCapacity)
    }

    func currentViewerIDForTesting() -> UUID? {
      viewerID
    }

    func transitionWaiterCountForTesting() -> Int {
      transitionWaiters.count
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
    if let httpResponse = response as? HTTPURLResponse {
      guard (200 ..< 300).contains(httpResponse.statusCode) else {
        throw AppMediaCacheError.httpStatus(httpResponse.statusCode)
      }
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

  private func acquireOperation(for resource: AppMediaResource) -> OperationHandle {
    if var operation = activeOperations[resource] {
      operation.callerCount += 1
      activeOperations[resource] = operation
      return OperationHandle(id: operation.id, cacheGeneration: operation.cacheGeneration)
    }
    let operation = ActiveOperation(
      id: UUID(),
      cacheGeneration: cacheGeneration,
      callerCount: 1
    )
    activeOperations[resource] = operation
    return OperationHandle(id: operation.id, cacheGeneration: operation.cacheGeneration)
  }

  private func release(_ handle: OperationHandle, for resource: AppMediaResource) {
    guard var operation = activeOperations[resource], operation.id == handle.id else { return }
    operation.callerCount -= 1
    if operation.callerCount == 0 {
      activeOperations[resource] = nil
    } else {
      activeOperations[resource] = operation
    }
  }

  private func ensureValid(
    _ handle: OperationHandle,
    for resource: AppMediaResource,
    request: InFlightRequest? = nil
  ) throws {
    try Task.checkCancellation()
    guard handle.cacheGeneration == cacheGeneration,
          activeOperations[resource]?.id == handle.id
    else {
      throw CancellationError()
    }
    if let request, request.cacheGeneration != cacheGeneration {
      throw CancellationError()
    }
  }

  private func cancelInFlightRequests() {
    cacheGeneration += 1
    activeOperations.removeAll()
    for request in inFlight.values {
      request.task.cancel()
    }
    inFlight.removeAll()
  }

  private func acquireTransitionLock() async {
    if !transitionLockIsHeld {
      transitionLockIsHeld = true
      return
    }
    await withCheckedContinuation { continuation in
      transitionWaiters.append(continuation)
    }
  }

  private func releaseTransitionLock() {
    guard !transitionWaiters.isEmpty else {
      transitionLockIsHeld = false
      return
    }
    transitionWaiters.removeFirst().resume()
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
