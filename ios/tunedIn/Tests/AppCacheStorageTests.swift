import Foundation
import Testing
@testable import tunedIn

struct AppCacheStorageTests {
  @Test
  func preparedCacheStorageIsBackupExcludedProtectedAndEnvironmentScoped() throws {
    let fileManager = FileManager.default
    let baseDirectory = try temporaryDirectory(named: "cache-storage")
    defer { try? fileManager.removeItem(at: baseDirectory) }

    let stagingDirectory = try AppCacheStorage.prepareStructuredDirectory(
      environment: .staging,
      baseDirectory: baseDirectory,
      fileManager: fileManager
    )
    let developmentDirectory = try AppCacheStorage.prepareStructuredDirectory(
      environment: .development,
      baseDirectory: baseDirectory,
      fileManager: fileManager
    )
    let markerURL = developmentDirectory.appending(path: "marker", directoryHint: .notDirectory)
    try AppCacheStorage.writeProtected(
      Data("cache-marker".utf8),
      to: markerURL,
      fileManager: fileManager
    )

    #expect(fileManager.fileExists(atPath: stagingDirectory.path) == false)
    #expect(
      try developmentDirectory.resourceValues(forKeys: [.isExcludedFromBackupKey])
        .isExcludedFromBackup == true
    )
    #expect(
      try markerURL.resourceValues(forKeys: [.isExcludedFromBackupKey])
        .isExcludedFromBackup == true
    )
    #expect(AppCacheStorage.fileProtection == .complete)
    #expect(AppCacheStorage.protectedWriteOptions.contains(.completeFileProtection))
    for reportedProtection in try [developmentDirectory, markerURL].compactMap({ url in
      try protection(at: url, fileManager: fileManager)
    }) {
      #expect(reportedProtection == .complete)
    }
  }

  @Test
  func corruptPersistentStoreIsReplacedAndRemainsUsable() async throws {
    let fileManager = FileManager.default
    let baseDirectory = try temporaryDirectory(named: "cache-recovery")
    defer { try? fileManager.removeItem(at: baseDirectory) }
    let directory = try AppCacheStorage.prepareStructuredDirectory(
      environment: .development,
      baseDirectory: baseDirectory,
      fileManager: fileManager
    )
    let storeURL = AppCacheStorage.structuredStoreURL(in: directory)
    try AppCacheStorage.writeProtected(
      Data("not-a-swiftdata-store".utf8),
      to: storeURL,
      fileManager: fileManager
    )

    let cache = try AppDataCache.persistent(
      environment: .development,
      baseDirectory: baseDirectory,
      fileManager: fileManager
    )
    let viewerID = UUID(uuidString: "74000000-0000-0000-0000-000000000001")!
    let resource = AppCacheResource(name: "recovered")
    let freshness = AppCacheFreshness(freshFor: 60, maximumStale: 300)
    await cache.transition(to: viewerID)
    try await cache.store(42, for: resource)
    await cache.clearMemory()

    let value: Int = try await cache.value(for: resource, freshness: freshness) {
      Issue.record("The recovered SwiftData store should satisfy this read")
      return 0
    }
    #expect(value == 42)
  }

  private func temporaryDirectory(named name: String) throws -> URL {
    let url = FileManager.default.temporaryDirectory.appending(
      path: "\(name)-\(UUID().uuidString)",
      directoryHint: .isDirectory
    )
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }

  private func protection(
    at url: URL,
    fileManager: FileManager
  ) throws -> FileProtectionType? {
    try fileManager.attributesOfItem(atPath: url.path)[.protectionKey] as? FileProtectionType
  }
}
