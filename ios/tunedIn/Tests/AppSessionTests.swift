import Foundation
import Testing
@testable import tunedIn

struct AppSessionTests {
  @MainActor
  @Test
  func restoredSessionRequiresIncompleteProfileOnboarding() async throws {
    let user = try AuthenticatedUser(
      id: #require(UUID(uuidString: "11111111-1111-1111-1111-111111111111")),
      email: "listener@example.test"
    )
    let profile = makeProfile(id: user.id, completed: false)
    let session = AppSession(
      authenticationRepository: StaticAuthenticationRepository(user: user),
      profileRepository: StaticProfileRepository(profile: profile)
    )

    await settle(session)

    guard case let .needsOnboarding(restoredUser) = session.phase else {
      Issue.record("Expected an incomplete restored profile to require onboarding")
      return
    }
    #expect(restoredUser == user)
  }

  @MainActor
  @Test
  func restoredSessionOpensAppForCompletedProfile() async throws {
    let user = try AuthenticatedUser(
      id: #require(UUID(uuidString: "22222222-2222-2222-2222-222222222222")),
      email: "journal@example.test"
    )
    let profile = makeProfile(id: user.id, completed: true)
    let session = AppSession(
      authenticationRepository: StaticAuthenticationRepository(user: user),
      profileRepository: StaticProfileRepository(profile: profile)
    )

    await settle(session)

    guard case let .signedIn(restoredUser, restoredProfile) = session.phase else {
      Issue.record("Expected a completed restored profile to open the app")
      return
    }
    #expect(restoredUser == user)
    #expect(restoredProfile == profile)
  }

  @MainActor
  @Test
  func successfulSignOutImmediatelyReturnsToSignIn() async throws {
    let user = try AuthenticatedUser(
      id: #require(UUID(uuidString: "33333333-3333-3333-3333-333333333333")),
      email: "signout@example.test"
    )
    let session = AppSession(
      authenticationRepository: StaticAuthenticationRepository(user: user),
      profileRepository: StaticProfileRepository(profile: makeProfile(id: user.id, completed: true))
    )

    await settle(session)
    await session.signOut()

    guard case .signedOut = session.phase else {
      Issue.record("Expected a successful sign out to return to sign-in immediately")
      return
    }
  }

  @MainActor
  @Test
  func callbackFailureIsVisibleInsteadOfSilentlyDoingNothing() async throws {
    let userID = try #require(UUID(uuidString: "44444444-4444-4444-4444-444444444444"))
    let session = AppSession(
      authenticationRepository: FailingCallbackAuthenticationRepository(),
      profileRepository: StaticProfileRepository(profile: makeProfile(id: userID, completed: false))
    )

    await settle(session)
    try session.handleAuthCallback(#require(URL(string: "com.ethanherrera.tunedin://auth-callback")))

    for _ in 0 ..< 100 where session.authCallbackError == nil {
      try? await Task.sleep(for: .milliseconds(10))
    }

    #expect(session.authCallbackError == "The login link could not be verified.")
  }

  @MainActor
  @Test
  func manualProfileRefreshUpdatesTheSignedInProfile() async throws {
    let user = try AuthenticatedUser(
      id: #require(UUID(uuidString: "55555555-5555-5555-5555-555555555555")),
      email: "refresh@example.test"
    )
    let initialProfile = makeProfile(id: user.id, completed: true)
    let refreshedProfile = Profile(
      id: user.id,
      username: "listener",
      displayName: "Refreshed Listener",
      avatarObjectPath: "avatars/refreshed.jpg",
      avatarVersion: 2,
      onboardingCompletedAt: Date(timeIntervalSince1970: 1),
      createdAt: Date(timeIntervalSince1970: 0),
      updatedAt: Date(timeIntervalSince1970: 2)
    )
    let session = AppSession(
      authenticationRepository: StaticAuthenticationRepository(user: user),
      profileRepository: RefreshProfileRepository(initial: initialProfile, refreshed: refreshedProfile)
    )

    await settle(session)
    try await session.refreshProfile()

    guard case let .signedIn(_, profile) = session.phase else {
      Issue.record("Expected refresh to keep the session signed in")
      return
    }
    #expect(profile == refreshedProfile)
  }

  @MainActor
  @Test
  func failedManualProfileRefreshPreservesVisibleProfile() async throws {
    let user = try AuthenticatedUser(
      id: #require(UUID(uuidString: "66666666-6666-6666-6666-666666666666")),
      email: "refresh-failure@example.test"
    )
    let profile = makeProfile(id: user.id, completed: true)
    let session = AppSession(
      authenticationRepository: StaticAuthenticationRepository(user: user),
      profileRepository: RefreshProfileRepository(initial: profile, refreshed: nil)
    )

    await settle(session)
    await #expect(throws: RefreshProfileRepository.Failure.self) {
      try await session.refreshProfile()
    }

    guard case let .signedIn(_, visibleProfile) = session.phase else {
      Issue.record("Expected a failed refresh to preserve the signed-in screen")
      return
    }
    #expect(visibleProfile == profile)
  }

  @MainActor
  @Test
  func repeatedAuthenticationEventForTheSameUserDoesNotReloadProfile() async throws {
    let user = try AuthenticatedUser(
      id: #require(UUID(uuidString: "77777777-7777-7777-7777-777777777777")),
      email: "before-refresh@example.test"
    )
    let refreshedUser = AuthenticatedUser(
      id: user.id,
      email: "after-refresh@example.test"
    )
    let repository = CountingProfileRepository(
      profile: makeProfile(id: user.id, completed: true)
    )
    let session = AppSession(
      authenticationRepository: RepeatedAuthenticationRepository(users: [user, refreshedUser]),
      profileRepository: repository
    )

    await settle(session)

    guard case let .signedIn(visibleUser, _) = session.phase else {
      Issue.record("Expected the repeated auth event to retain the signed-in session")
      return
    }
    #expect(visibleUser == refreshedUser)
    #expect(await repository.fetchCount == 1)
  }

  private func makeProfile(id: UUID, completed: Bool) -> Profile {
    Profile(
      id: id,
      username: completed ? "listener" : nil,
      displayName: completed ? "Listener" : nil,
      avatarObjectPath: nil,
      avatarVersion: 0,
      onboardingCompletedAt: completed ? Date(timeIntervalSince1970: 1) : nil,
      createdAt: Date(timeIntervalSince1970: 0),
      updatedAt: Date(timeIntervalSince1970: 1)
    )
  }

  @MainActor
  private func settle(_ session: AppSession) async {
    for _ in 0 ..< 100 {
      switch session.phase {
      case .restoring, .loadingProfile:
        try? await Task.sleep(for: .milliseconds(10))
      default:
        return
      }
    }
  }
}

private struct FailingCallbackAuthenticationRepository: AuthenticationRepository {
  var authenticationStateChanges: AsyncStream<AuthenticatedUser?> {
    AsyncStream { continuation in
      continuation.yield(nil)
      continuation.finish()
    }
  }

  func sendEmailOTP(to _: String) async throws {}
  func signInWithPassword(email _: String, password _: String) async throws {}
  func verifyEmailOTP(email _: String, code _: String) async throws {}
  func signIn(with _: NativeAuthCredentials) async throws -> AuthenticatedUser {
    throw AppFailure.unavailable
  }

  func signOut() async throws {}

  func handleAuthCallback(_: URL) async throws {
    throw Failure.invalidLink
  }

  enum Failure: LocalizedError {
    case invalidLink

    var errorDescription: String? {
      "The login link could not be verified."
    }
  }
}

private struct StaticAuthenticationRepository: AuthenticationRepository {
  let user: AuthenticatedUser?

  var authenticationStateChanges: AsyncStream<AuthenticatedUser?> {
    AsyncStream { continuation in
      continuation.yield(user)
      continuation.finish()
    }
  }

  func sendEmailOTP(to _: String) async throws {}
  func signInWithPassword(email _: String, password _: String) async throws {}
  func verifyEmailOTP(email _: String, code _: String) async throws {}
  func signIn(with _: NativeAuthCredentials) async throws -> AuthenticatedUser {
    guard let user else { throw AppFailure.unavailable }
    return user
  }

  func signOut() async throws {}
  func handleAuthCallback(_: URL) async throws {}
}

private struct RepeatedAuthenticationRepository: AuthenticationRepository {
  let users: [AuthenticatedUser]

  var authenticationStateChanges: AsyncStream<AuthenticatedUser?> {
    AsyncStream { continuation in
      for user in users {
        continuation.yield(user)
      }
      continuation.finish()
    }
  }

  func sendEmailOTP(to _: String) async throws {}
  func signInWithPassword(email _: String, password _: String) async throws {}
  func verifyEmailOTP(email _: String, code _: String) async throws {}
  func signIn(with _: NativeAuthCredentials) async throws -> AuthenticatedUser {
    guard let user = users.last else { throw AppFailure.unavailable }
    return user
  }

  func signOut() async throws {}
  func handleAuthCallback(_: URL) async throws {}
}

private struct StaticProfileRepository: ProfileRepository {
  let profile: Profile

  func fetchProfile(for _: UUID) async throws -> Profile {
    profile
  }

  func isUsernameAvailable(_: String) async throws -> Bool {
    true
  }

  func completeOnboarding(username _: String, displayName _: String) async throws -> Profile {
    profile
  }

  func setAvatar(jpegData _: Data, for _: UUID) async throws -> Profile {
    profile
  }

  func removeAvatar(for _: UUID) async throws -> Profile {
    profile
  }

  func avatarURL(profileID _: UUID, objectPath _: String, version _: Int64) async throws -> URL {
    URL(string: "https://example.test/avatar.jpg")!
  }
}

private actor RefreshProfileRepository: ProfileRepository {
  enum Failure: Error {
    case unavailable
  }

  let initial: Profile
  let refreshed: Profile?
  private var fetchCount = 0

  init(initial: Profile, refreshed: Profile?) {
    self.initial = initial
    self.refreshed = refreshed
  }

  func fetchProfile(for _: UUID) async throws -> Profile {
    defer { fetchCount += 1 }
    guard fetchCount > 0 else { return initial }
    guard let refreshed else { throw Failure.unavailable }
    return refreshed
  }

  func isUsernameAvailable(_: String) async throws -> Bool {
    true
  }

  func completeOnboarding(username _: String, displayName _: String) async throws -> Profile {
    initial
  }

  func setAvatar(jpegData _: Data, for _: UUID) async throws -> Profile {
    initial
  }

  func removeAvatar(for _: UUID) async throws -> Profile {
    initial
  }

  func avatarURL(profileID _: UUID, objectPath _: String, version _: Int64) async throws -> URL {
    URL(string: "https://example.test/avatar.jpg")!
  }
}

private actor CountingProfileRepository: ProfileRepository {
  let profile: Profile
  private(set) var fetchCount = 0

  init(profile: Profile) {
    self.profile = profile
  }

  func fetchProfile(for _: UUID) async throws -> Profile {
    fetchCount += 1
    return profile
  }

  func isUsernameAvailable(_: String) async throws -> Bool {
    true
  }

  func completeOnboarding(username _: String, displayName _: String) async throws -> Profile {
    profile
  }

  func setAvatar(jpegData _: Data, for _: UUID) async throws -> Profile {
    profile
  }

  func removeAvatar(for _: UUID) async throws -> Profile {
    profile
  }

  func avatarURL(profileID _: UUID, objectPath _: String, version _: Int64) async throws -> URL {
    URL(string: "https://example.test/avatar.jpg")!
  }
}
