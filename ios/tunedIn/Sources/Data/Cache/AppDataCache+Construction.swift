import Foundation
import SwiftData

extension AppDataCache {
  static func live(
    environment: AppEnvironment,
    clock: any AppCacheClock = SystemAppCacheClock()
  ) throws -> AppDataCache {
    try make(environment: environment, isStoredInMemoryOnly: false, clock: clock)
  }

  static func inMemory(
    environment: AppEnvironment = .development,
    clock: any AppCacheClock = SystemAppCacheClock()
  ) throws -> AppDataCache {
    try make(environment: environment, isStoredInMemoryOnly: true, clock: clock)
  }

  private static func make(
    environment: AppEnvironment,
    isStoredInMemoryOnly: Bool,
    clock: any AppCacheClock
  ) throws -> AppDataCache {
    if !isStoredInMemoryOnly {
      _ = try FileManager.default.url(
        for: .applicationSupportDirectory,
        in: .userDomainMask,
        appropriateFor: nil,
        create: true
      )
    }
    let schema = Schema([CachedServerSnapshot.self])
    let configuration = ModelConfiguration(
      "ServerSnapshots",
      schema: schema,
      isStoredInMemoryOnly: isStoredInMemoryOnly,
      cloudKitDatabase: .none
    )
    let container = try ModelContainer(for: schema, configurations: [configuration])
    return AppDataCache(
      environment: environment,
      store: SwiftDataSnapshotStore(modelContainer: container),
      clock: clock
    )
  }
}
