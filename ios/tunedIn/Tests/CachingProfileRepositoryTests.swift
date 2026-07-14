import Foundation
import Testing
@testable import tunedIn

struct CachingProfileRepositoryTests {
  private let userID = UUID(uuidString: "20000000-0000-0000-0000-000000000002")!

  @Test
  func automaticReadsUseTheSnapshotAndRefreshReplacesIt() async throws {
    let first = profile(displayName: "First", version: 1)
    let refreshed = profile(displayName: "Refreshed", version: 2)
    let remote = ProfileRepositorySpy(fetchResponses: [first, refreshed])
    let cache = try AppDataCache.inMemory()
    let repository = CachingProfileRepository(remote: remote, cache: cache)
    await cache.transition(to: userID)

    #expect(try await repository.fetchProfile(for: userID) == first)
    #expect(try await repository.fetchProfile(for: userID) == first)
    #expect(await remote.fetchCount == 1)

    #expect(try await repository.fetchProfile(for: userID, policy: .refresh) == refreshed)
    #expect(try await repository.fetchProfile(for: userID) == refreshed)
    #expect(await remote.fetchCount == 2)
  }

  @Test
  func successfulAvatarMutationPatchesTheProfileSnapshot() async throws {
    let first = profile(displayName: "First", version: 1)
    let updated = profile(displayName: "First", version: 2)
    let remote = ProfileRepositorySpy(fetchResponses: [first], avatarResponse: updated)
    let cache = try AppDataCache.inMemory()
    let repository = CachingProfileRepository(remote: remote, cache: cache)
    await cache.transition(to: userID)

    #expect(try await repository.fetchProfile(for: userID) == first)
    #expect(try await repository.setAvatar(jpegData: Data([1]), for: userID) == updated)
    #expect(try await repository.fetchProfile(for: userID) == updated)
    #expect(await remote.fetchCount == 1)
  }

  private func profile(displayName: String, version: Int64) -> Profile {
    Profile(
      id: userID,
      username: "listener",
      displayName: displayName,
      avatarObjectPath: version > 1 ? "avatars/listener/profile.jpg" : nil,
      avatarVersion: version,
      onboardingCompletedAt: Date(timeIntervalSince1970: 1),
      createdAt: Date(timeIntervalSince1970: 0),
      updatedAt: Date(timeIntervalSince1970: TimeInterval(version))
    )
  }
}

private actor ProfileRepositorySpy: ProfileRepository {
  private let fetchResponses: [Profile]
  private let avatarResponse: Profile?
  private var fetchIndex = 0

  init(fetchResponses: [Profile], avatarResponse: Profile? = nil) {
    self.fetchResponses = fetchResponses
    self.avatarResponse = avatarResponse
  }

  var fetchCount: Int {
    fetchIndex
  }

  func fetchProfile(for _: UUID) async throws -> Profile {
    let response = fetchResponses[min(fetchIndex, fetchResponses.count - 1)]
    fetchIndex += 1
    return response
  }

  func isUsernameAvailable(_: String) async throws -> Bool {
    true
  }

  func completeOnboarding(username _: String, displayName _: String) async throws -> Profile {
    fetchResponses[0]
  }

  func setAvatar(jpegData _: Data, for _: UUID) async throws -> Profile {
    avatarResponse ?? fetchResponses[0]
  }

  func removeAvatar(for _: UUID) async throws -> Profile {
    fetchResponses[0]
  }

  func avatarURL(profileID _: UUID, objectPath _: String, version _: Int64) async throws -> URL {
    URL(string: "https://example.test/avatar.jpg")!
  }
}
