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

  @Test
  func restoredGoogleTokenWithoutNonceCanBeReused() throws {
    let token = try googleIDToken(payload: ["sub": "google-user", "aud": "server-client"])

    #expect(RestoredGoogleIDTokenPolicy.canReuse(token))
  }

  @Test
  func restoredLegacyGoogleTokenWithNonceRequiresInteractiveMigration() throws {
    let token = try googleIDToken(
      payload: [
        "sub": "google-user",
        "aud": "server-client",
        "nonce": "hashed-legacy-nonce"
      ]
    )

    #expect(!RestoredGoogleIDTokenPolicy.canReuse(token))
  }

  @Test
  func malformedRestoredGoogleTokenRequiresInteractiveMigration() {
    #expect(!RestoredGoogleIDTokenPolicy.canReuse("not-a-google-id-token"))
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
        nonce: nil
      )
    )

    let record = telemetry.recentRecords.last
    #expect(record?.name == TelemetryEvent.authenticationCompleted.rawValue)
    #expect(record?.properties[.method] == .string("google"))
  }

  @MainActor
  @Test
  func sessionRecordsSanitizedNativeProviderFailures() {
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

    session.recordNativeAuthenticationFailure(
      provider: .apple,
      error: AppFailure.unexpected,
      statusClass: "apple_authorization_1000"
    )

    let event = telemetry.recentRecords.first { $0.name == TelemetryEvent.authenticationCompleted.rawValue }
    #expect(event?.properties[.method] == .string("apple"))
    #expect(event?.properties[.outcome] == .string("failed"))
    #expect(event?.properties[.failureCategory] == .string("unexpected"))
    #expect(event?.properties[.statusClass] == .string("apple_authorization_1000"))
    let log = telemetry.recentRecords.first { $0.name == TelemetryLogMessage.nativeAuthenticationFailed.rawValue }
    #expect(log?.properties[.operation] == .string("authenticate"))
    #expect(log?.properties[.method] == .string("apple"))
  }

  private func googleIDToken(payload: [String: String]) throws -> String {
    let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
    let encodedPayload = data.base64EncodedString()
      .replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: "=", with: "")
    return "header.\(encodedPayload).signature"
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
  func signIn(with _: NativeAuthCredentials) async throws -> AuthenticatedUser {
    AuthenticatedUser(
      id: UUID(uuidString: "99999999-9999-9999-9999-999999999999")!,
      email: "google@example.test"
    )
  }

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
