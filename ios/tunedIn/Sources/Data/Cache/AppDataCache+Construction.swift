import Foundation
import SwiftData

private struct AppDataCacheConstruction {
  let environment: AppEnvironment
  let clock: any AppCacheClock
  let budget: AppCacheBudget
  let diagnostics: AppCacheDiagnostics
  let mediaCache: AppMediaCache?
}

extension AppDataCache {
  static func live(
    environment: AppEnvironment,
    clock: any AppCacheClock = SystemAppCacheClock(),
    budget: AppCacheBudget = .structured,
    diagnostics: AppCacheDiagnostics = AppCacheDiagnostics(),
    mediaCache: AppMediaCache? = nil
  ) throws -> AppDataCache {
    let baseDirectory = try AppCacheStorage.liveBaseDirectory()
    return try persistent(
      environment: environment,
      baseDirectory: baseDirectory,
      clock: clock,
      budget: budget,
      diagnostics: diagnostics,
      mediaCache: mediaCache
    )
  }

  static func inMemory(
    environment: AppEnvironment = .development,
    clock: any AppCacheClock = SystemAppCacheClock(),
    budget: AppCacheBudget = .structured,
    diagnostics: AppCacheDiagnostics = AppCacheDiagnostics(),
    mediaCache: AppMediaCache? = nil
  ) throws -> AppDataCache {
    let construction = AppDataCacheConstruction(
      environment: environment,
      clock: clock,
      budget: budget,
      diagnostics: diagnostics,
      mediaCache: mediaCache
    )
    let schema = Schema([CachedServerSnapshot.self])
    let configuration = ModelConfiguration(
      "ServerSnapshots",
      schema: schema,
      isStoredInMemoryOnly: true,
      cloudKitDatabase: .none
    )
    return try make(
      configuration: configuration,
      schema: schema,
      construction: construction
    )
  }

  static func persistent(
    environment: AppEnvironment,
    baseDirectory: URL,
    clock: any AppCacheClock = SystemAppCacheClock(),
    budget: AppCacheBudget = .structured,
    diagnostics: AppCacheDiagnostics = AppCacheDiagnostics(),
    mediaCache: AppMediaCache? = nil,
    fileManager: FileManager = .default
  ) throws -> AppDataCache {
    let construction = AppDataCacheConstruction(
      environment: environment,
      clock: clock,
      budget: budget,
      diagnostics: diagnostics,
      mediaCache: mediaCache
    )
    let directory = try AppCacheStorage.prepareStructuredDirectory(
      environment: environment,
      baseDirectory: baseDirectory,
      fileManager: fileManager
    )
    let schema = Schema([CachedServerSnapshot.self])
    do {
      return try makePersistent(
        directory: directory,
        schema: schema,
        construction: construction
      )
    } catch {
      try AppCacheStorage.resetDirectory(directory, fileManager: fileManager)
      return try makePersistent(
        directory: directory,
        schema: schema,
        construction: construction
      )
    }
  }

  private static func makePersistent(
    directory: URL,
    schema: Schema,
    construction: AppDataCacheConstruction
  ) throws -> AppDataCache {
    let configuration = ModelConfiguration(
      "ServerSnapshots",
      schema: schema,
      url: AppCacheStorage.structuredStoreURL(in: directory),
      cloudKitDatabase: .none
    )
    return try make(
      configuration: configuration,
      schema: schema,
      construction: construction
    )
  }

  private static func make(
    configuration: ModelConfiguration,
    schema: Schema,
    construction: AppDataCacheConstruction
  ) throws -> AppDataCache {
    let container = try ModelContainer(for: schema, configurations: [configuration])
    return AppDataCache(
      environment: construction.environment,
      store: SwiftDataSnapshotStore(modelContainer: container),
      clock: construction.clock,
      budget: construction.budget,
      diagnostics: construction.diagnostics,
      mediaCache: construction.mediaCache
    )
  }
}
