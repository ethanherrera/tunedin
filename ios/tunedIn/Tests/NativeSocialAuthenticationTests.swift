import Foundation
import Testing
@testable import tunedIn

struct NativeSocialAuthenticationTests {
  @Test
  func secureNonceHasExpectedLengthAndAlphabet() throws {
    let nonce = try NativeAuthNonce.random(length: 48)

    #expect(nonce.count == 48)
    #expect(nonce.allSatisfy { $0.isASCII && !$0.isWhitespace })
  }

  @Test
  func nonceHashMatchesSHA256Reference() {
    #expect(
      NativeAuthNonce.hashed("tunedIn")
        == "0dbb1da7257f372b952958536d9ad318408012ae7b576b740be05343433a9969"
    )
  }

  @MainActor
  @Test
  func sessionRecordsTheNativeProviderAfterSuccessfulExchange() async throws {
    let configuration = NativeSocialAuthConfiguration(
      googleIOSClientID: "ios.apps.googleusercontent.com",
      googleServerClientID: "server.apps.googleusercontent.com"
    )
    let telemetry = AppTelemetryClient(
      configuration: .recording,
      release: ReleaseMetadata(
        version: "test",
        build: "test",
        gitSHA: "test",
        environment: .staging
      )
    )
    let session = AppSession(
      authenticationRepository: SuccessfulNativeAuthenticationRepository(),
      profileRepository: NativeAuthenticationProfileRepository(),
      nativeSocialAuthConfiguration: configuration,
      telemetry: telemetry
    )

    try await session.signIn(
      with: NativeAuthCredentials(
        provider: .google,
        idToken: "id-token",
        accessToken: "access-token",
        nonce: "nonce"
      )
    )

    let record = telemetry.recentRecords.last
    #expect(record?.name == TelemetryEvent.authenticationCompleted.rawValue)
    #expect(record?.properties[.method] == .string("google"))
  }
}

private struct SuccessfulNativeAuthenticationRepository: AuthenticationRepository {
  var authenticationStateChanges: AsyncStream<AuthenticatedUser?> {
    AsyncStream { continuation in
      continuation.yield(nil)
      continuation.finish()
    }
  }

  func sendEmailOTP(to _: String) async throws {}
  func signInWithPassword(email _: String, password _: String) async throws {}
  func verifyEmailOTP(email _: String, code _: String) async throws {}
  func signIn(with _: NativeAuthCredentials) async throws {}
  func signOut() async throws {}
  func handleAuthCallback(_: URL) async throws {}
}

private struct NativeAuthenticationProfileRepository: ProfileRepository {
  func fetchProfile(for _: UUID) async throws -> Profile {
    throw AppFailure.unavailable
  }

  func isUsernameAvailable(_: String) async throws -> Bool {
    true
  }

  func completeOnboarding(username _: String, displayName _: String) async throws -> Profile {
    throw AppFailure.unavailable
  }

  func setAvatar(jpegData _: Data, for _: UUID) async throws -> Profile {
    throw AppFailure.unavailable
  }

  func removeAvatar(for _: UUID) async throws -> Profile {
    throw AppFailure.unavailable
  }

  func avatarURL(profileID _: UUID, objectPath _: String, version _: Int64) async throws -> URL {
    throw AppFailure.unavailable
  }
}
