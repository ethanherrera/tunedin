import Foundation

enum CacheReadPolicy: Sendable {
  case automatic
  case refresh
  case networkOnly
}

struct AppCacheFreshness: Equatable, Sendable {
  let freshFor: TimeInterval
  let maximumStale: TimeInterval

  static let profile = Self(
    freshFor: 60 * 60,
    maximumStale: 7 * 24 * 60 * 60
  )
  static let friendsActivity = Self(
    freshFor: 15 * 60,
    maximumStale: 24 * 60 * 60
  )
}

enum AppCacheEntryState: Equatable, Sendable {
  case missing
  case fresh
  case stale
  case invalidated
  case expired
}

struct AppCacheResource: Hashable, Sendable {
  let name: String
  let variant: String
  let payloadVersion: Int

  init(name: String, variant: String = "default", payloadVersion: Int = 1) {
    self.name = name
    self.variant = variant
    self.payloadVersion = payloadVersion
  }
}

enum AppCacheResources {
  static func profile(userID: UUID) -> AppCacheResource {
    AppCacheResource(name: "profile", variant: userID.uuidString.lowercased())
  }

  static let friendsActivity = AppCacheResource(name: "friends-activity", variant: "first-page")
}

protocol AppCacheClock: Sendable {
  var now: Date { get }
}

struct SystemAppCacheClock: AppCacheClock {
  var now: Date {
    .now
  }
}

struct AppCacheMemorySnapshot {
  let value: any Sendable
  let payload: Data
  let fetchedAt: Date
  let invalidatedAt: Date?
}

struct AppCacheInFlightRequest {
  let id: UUID
  let revision: Int
  let task: Task<Data, any Error>
}
