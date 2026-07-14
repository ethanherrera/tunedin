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
  static let socialRelationship = Self(
    freshFor: 5 * 60,
    maximumStale: 24 * 60 * 60
  )
  static let concertArchive = Self(
    freshFor: 15 * 60,
    maximumStale: 24 * 60 * 60
  )
  static let concertDetail = Self(
    freshFor: 10 * 60,
    maximumStale: 24 * 60 * 60
  )
  static let concertComments = Self(
    freshFor: 2 * 60,
    maximumStale: 24 * 60 * 60
  )
  static let concertAlbum = Self(
    freshFor: 5 * 60,
    maximumStale: 24 * 60 * 60
  )
  static let concertAlbumPolicy = Self(
    freshFor: 55 * 60,
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

struct AppCacheScope: Hashable, Sendable {
  let environment: String
  let viewerID: UUID
  let generation: Int
}

enum AppCacheResources {
  static let profileName = "profile"
  static let friendsActivityName = "friends-activity"
  static let socialProfileName = "social-profile"
  static let socialFriendsName = "social-friends"
  static let incomingFriendRequestsName = "incoming-friend-requests"
  static let concertArchiveName = "concert-archive"
  static let concertDetailName = "concert-detail"
  static let concertCommentsName = "concert-comments"
  static let concertAlbumPhotosName = "concert-album-photos"
  static let concertAlbumPolicyName = "concert-album-policy"

  static func profile(userID: UUID) -> AppCacheResource {
    AppCacheResource(name: profileName, variant: userID.uuidString.lowercased())
  }

  static let friendsActivity = AppCacheResource(name: friendsActivityName, variant: "first-page")

  static func socialProfile(username: String) -> AppCacheResource {
    AppCacheResource(name: socialProfileName, variant: normalizedUsername(username))
  }

  static func socialFriends(username: String) -> AppCacheResource {
    AppCacheResource(name: socialFriendsName, variant: normalizedUsername(username))
  }

  static let incomingFriendRequests = AppCacheResource(
    name: incomingFriendRequestsName,
    variant: "first-page"
  )

  static func concertArchive(
    profileID: UUID,
    query: ConcertHistoryQuery
  ) -> AppCacheResource {
    let normalizedSearch = query.searchText
      .split(whereSeparator: \.isWhitespace)
      .joined(separator: " ")
      .lowercased()
    let components = [
      profileID.uuidString.lowercased(),
      normalizedSearch,
      query.year.map(String.init) ?? "all-years",
      query.visibility?.rawValue ?? "all-visibility",
      query.sort.rawValue
    ]
    return AppCacheResource(name: concertArchiveName, variant: components.joined(separator: "|"))
  }

  static func concertDetail(concertID: UUID, viewerID: UUID) -> AppCacheResource {
    AppCacheResource(
      name: concertDetailName,
      variant: "\(concertID.uuidString.lowercased())|\(viewerID.uuidString.lowercased())"
    )
  }

  static func concertComments(concertID: UUID) -> AppCacheResource {
    AppCacheResource(name: concertCommentsName, variant: concertID.uuidString.lowercased())
  }

  static func concertAlbumPhotos(concertID: UUID) -> AppCacheResource {
    AppCacheResource(name: concertAlbumPhotosName, variant: concertID.uuidString.lowercased())
  }

  static let concertAlbumPolicy = AppCacheResource(name: concertAlbumPolicyName)

  static let socialRelationshipNames: Set<String> = [
    socialProfileName,
    socialFriendsName,
    incomingFriendRequestsName
  ]

  static let concertArchiveNames: Set<String> = [concertArchiveName]

  static let permissionSensitiveConcertNames: Set<String> = [
    concertArchiveName,
    concertDetailName,
    concertCommentsName,
    concertAlbumPhotosName
  ]

  private static func normalizedUsername(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
  }
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
