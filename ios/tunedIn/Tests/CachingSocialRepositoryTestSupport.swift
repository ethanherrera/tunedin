import Foundation
@testable import tunedIn

struct SocialReadCounts: Equatable, Sendable {
  let profile: Int
  let friends: Int
  let incoming: Int
  let search: Int
}

enum SocialMutation: CaseIterable, Equatable, Sendable {
  case send
  case accept
  case decline
  case withdraw
  case removeFriend
  case block
  case unblock

  var expectedFeedState: AppCacheEntryState {
    switch self {
    case .accept:
      .invalidated
    case .removeFriend, .block:
      .missing
    case .send, .decline, .withdraw, .unblock:
      .fresh
    }
  }

  func perform(on repository: any SocialRepository, profileID: UUID) async throws {
    switch self {
    case .send:
      try await repository.sendFriendRequest(to: profileID)
    case .accept:
      try await repository.acceptFriendRequest(from: profileID)
    case .decline:
      try await repository.declineFriendRequest(from: profileID)
    case .withdraw:
      try await repository.withdrawFriendRequest(to: profileID)
    case .removeFriend:
      try await repository.removeFriend(profileID)
    case .block:
      try await repository.block(profileID)
    case .unblock:
      try await repository.unblock(profileID)
    }
  }
}

actor SocialRepositorySpy: SocialRepository {
  private let profileResults: [Result<SocialProfile?, SocialRepositoryTestFailure>]
  private let friendResults: [Result<[SocialProfile], SocialRepositoryTestFailure>]
  private let incomingResults: [Result<[SocialProfile], SocialRepositoryTestFailure>]
  private let searchResults: [SocialProfile]
  private let mutationFailure: SocialRepositoryTestFailure?
  private let deniesFriendRefresh: Bool
  private var profileIndex = 0
  private var friendsIndex = 0
  private var incomingIndex = 0
  private var searchCount = 0
  private(set) var searchedPrefixes: [String] = []
  private(set) var mutations: [SocialMutation] = []

  init(
    profiles: [Result<SocialProfile?, SocialRepositoryTestFailure>] = [.success(nil)],
    friends: [Result<[SocialProfile], SocialRepositoryTestFailure>] = [.success([])],
    incoming: [Result<[SocialProfile], SocialRepositoryTestFailure>] = [.success([])],
    searchResults: [SocialProfile] = [],
    mutationFailure: SocialRepositoryTestFailure? = nil,
    deniesFriendRefresh: Bool = false
  ) {
    profileResults = profiles
    friendResults = friends
    incomingResults = incoming
    self.searchResults = searchResults
    self.mutationFailure = mutationFailure
    self.deniesFriendRefresh = deniesFriendRefresh
  }

  var readCounts: SocialReadCounts {
    SocialReadCounts(
      profile: profileIndex,
      friends: friendsIndex,
      incoming: incomingIndex,
      search: searchCount
    )
  }

  func searchProfiles(usernamePrefix: String) async throws -> [SocialProfile] {
    searchCount += 1
    searchedPrefixes.append(usernamePrefix)
    return searchResults
  }

  func profile(username _: String) async throws -> SocialProfile? {
    let result = profileResults[min(profileIndex, profileResults.count - 1)]
    profileIndex += 1
    return try result.get()
  }

  func friends(username _: String) async throws -> [SocialProfile] {
    if deniesFriendRefresh, friendsIndex > 0 {
      friendsIndex += 1
      throw AppFailure.permissionDenied
    }
    let result = friendResults[min(friendsIndex, friendResults.count - 1)]
    friendsIndex += 1
    return try result.get()
  }

  func incomingFriendRequests() async throws -> [SocialProfile] {
    let result = incomingResults[min(incomingIndex, incomingResults.count - 1)]
    incomingIndex += 1
    return try result.get()
  }

  func sendFriendRequest(to _: UUID) async throws {
    try record(.send)
  }

  func acceptFriendRequest(from _: UUID) async throws {
    try record(.accept)
  }

  func declineFriendRequest(from _: UUID) async throws {
    try record(.decline)
  }

  func withdrawFriendRequest(to _: UUID) async throws {
    try record(.withdraw)
  }

  func removeFriend(_: UUID) async throws {
    try record(.removeFriend)
  }

  func block(_: UUID) async throws {
    try record(.block)
  }

  func unblock(_: UUID) async throws {
    try record(.unblock)
  }

  private func record(_ mutation: SocialMutation) throws {
    mutations.append(mutation)
    if let mutationFailure {
      throw mutationFailure
    }
  }
}

enum SocialRepositoryTestFailure: Error {
  case unavailable
}
