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
  func signOut() async throws {}
  func handleAuthCallback(_: URL) {}
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
