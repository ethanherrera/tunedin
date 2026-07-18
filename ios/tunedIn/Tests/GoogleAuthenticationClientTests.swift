import Foundation
import Testing
@testable import tunedIn

struct GoogleAuthenticationClientTests {
  private let rawNonce = "deterministic-google-nonce"

  @MainActor
  @Test
  func legacyCachedSessionRestoresWithoutExplicitSignOut() async throws {
    let restored = try credentials(payload: ["sub": "cached-user"])
    let sdk = GoogleSignInSDKSpy(
      hasPreviousSignIn: true,
      restoreResult: .success(restored),
      interactiveResults: [.success(interactiveCredentials)]
    )
    let client = googleClient(sdk: sdk)

    let result = try await client.credentials(
      configuration: configuration,
      allowsPreviousSignInRestore: true
    )

    #expect(result == restored)
    #expect(sdk.restoreCallCount == 1)
    #expect(sdk.interactiveCallCount == 0)
    #expect(sdk.signOutCallCount == 0)
  }

  @MainActor
  @Test
  func explicitSignOutClearsGoogleCacheAndForcesInteractiveSignIn() async throws {
    let sdk = try GoogleSignInSDKSpy(
      hasPreviousSignIn: true,
      restoreResult: .success(credentials(payload: ["sub": "cached-user"])),
      interactiveResults: [.success(interactiveCredentials)]
    )
    let client = googleClient(sdk: sdk)

    client.signOut()
    let result = try await client.credentials(
      configuration: configuration,
      allowsPreviousSignInRestore: false
    )

    #expect(result == interactiveCredentials)
    #expect(sdk.signOutCallCount == 1)
    #expect(sdk.restoreCallCount == 0)
    #expect(sdk.interactiveCallCount == 1)
    #expect(sdk.interactiveHashedNonces == [NativeAuthNonce.hashed(rawNonce)])
  }

  @MainActor
  @Test
  func cancelledInteractiveAttemptNeverFallsBackToCachedAccount() async throws {
    let sdk = try GoogleSignInSDKSpy(
      hasPreviousSignIn: true,
      restoreResult: .success(credentials(payload: ["sub": "cached-user"])),
      interactiveResults: [.failure(.cancelled), .success(interactiveCredentials)]
    )
    let client = googleClient(sdk: sdk)
    client.signOut()

    await #expect(throws: GoogleSignInSDKSpy.Failure.cancelled) {
      try await client.credentials(
        configuration: configuration,
        allowsPreviousSignInRestore: false
      )
    }
    let result = try await client.credentials(
      configuration: configuration,
      allowsPreviousSignInRestore: false
    )

    #expect(result == interactiveCredentials)
    #expect(sdk.restoreCallCount == 0)
    #expect(sdk.interactiveCallCount == 2)
  }

  @MainActor
  @Test
  func nonceBearingRestoredTokenFallsBackToInteractiveSignIn() async throws {
    let restored = try credentials(
      payload: ["sub": "legacy-user", "nonce": "legacy-hashed-nonce"]
    )
    let sdk = GoogleSignInSDKSpy(
      hasPreviousSignIn: true,
      restoreResult: .success(restored),
      interactiveResults: [.success(interactiveCredentials)]
    )
    let client = googleClient(sdk: sdk)

    let result = try await client.credentials(
      configuration: configuration,
      allowsPreviousSignInRestore: true
    )

    #expect(result == interactiveCredentials)
    #expect(sdk.restoreCallCount == 1)
    #expect(sdk.signOutCallCount == 1)
    #expect(sdk.interactiveCallCount == 1)
    #expect(result.nonce == rawNonce)
  }

  @MainActor
  @Test
  func recreatedClientCannotRestoreAccountClearedBeforeRelaunch() async throws {
    let sdk = try GoogleSignInSDKSpy(
      hasPreviousSignIn: true,
      restoreResult: .success(credentials(payload: ["sub": "cached-user"])),
      interactiveResults: [.success(interactiveCredentials)]
    )
    googleClient(sdk: sdk).signOut()
    let recreatedClient = googleClient(sdk: sdk)

    let result = try await recreatedClient.credentials(
      configuration: configuration,
      allowsPreviousSignInRestore: true
    )

    #expect(result == interactiveCredentials)
    #expect(sdk.restoreCallCount == 0)
    #expect(sdk.interactiveCallCount == 1)
  }

  @MainActor
  @Test
  func taskCancellationDuringRestoreNeverStartsInteractiveSignIn() async throws {
    let sdk = try GoogleSignInSDKSpy(
      hasPreviousSignIn: true,
      restoreResult: .success(credentials(payload: ["sub": "cached-user"])),
      interactiveResults: [.success(interactiveCredentials)],
      restoreThrowsCancellation: true
    )
    let client = googleClient(sdk: sdk)

    await #expect(throws: CancellationError.self) {
      try await client.credentials(
        configuration: configuration,
        allowsPreviousSignInRestore: true
      )
    }

    #expect(sdk.restoreCallCount == 1)
    #expect(sdk.interactiveCallCount == 0)
    #expect(sdk.signOutCallCount == 0)
    #expect(NativeSocialSignInError.isCancellation(CancellationError()))
  }

  @MainActor
  @Test
  func interactiveSignInSendsGoogleTheHashAndReturnsSupabaseTheRawNonce() async throws {
    let sdk = GoogleSignInSDKSpy(
      hasPreviousSignIn: false,
      restoreResult: .success(interactiveCredentials),
      interactiveResults: [.success(interactiveCredentials)]
    )
    let client = googleClient(sdk: sdk)

    let result = try await client.credentials(
      configuration: configuration,
      allowsPreviousSignInRestore: true
    )

    #expect(sdk.interactiveHashedNonces == [NativeAuthNonce.hashed(rawNonce)])
    #expect(result.provider == .google)
    #expect(result.idToken == interactiveCredentials.idToken)
    #expect(result.accessToken == interactiveCredentials.accessToken)
    #expect(result.nonce == rawNonce)
  }

  @MainActor
  private func googleClient(sdk: GoogleSignInSDKSpy) -> LiveGoogleAuthenticationClient {
    LiveGoogleAuthenticationClient(sdk: sdk, nonceGenerator: { rawNonce })
  }

  private var configuration: NativeSocialAuthConfiguration {
    NativeSocialAuthConfiguration(
      googleIOSClientID: "ios.apps.googleusercontent.com",
      googleServerClientID: "server.apps.googleusercontent.com"
    )
  }

  private var interactiveCredentials: NativeAuthCredentials {
    NativeAuthCredentials(
      provider: .google,
      idToken: "interactive-id-token",
      accessToken: "interactive-access-token",
      nonce: rawNonce
    )
  }

  private func credentials(payload: [String: String]) throws -> NativeAuthCredentials {
    let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
    let encodedPayload = data.base64EncodedString()
      .replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: "=", with: "")
    return NativeAuthCredentials(
      provider: .google,
      idToken: "header.\(encodedPayload).signature",
      accessToken: "restored-access-token",
      nonce: nil
    )
  }
}

@MainActor
private final class GoogleSignInSDKSpy: GoogleSignInSDK {
  enum Failure: Error {
    case cancelled
  }

  private(set) var hasPreviousSignIn: Bool
  private let restoreResult: Result<NativeAuthCredentials, Failure>
  private let restoreThrowsCancellation: Bool
  private var interactiveResults: [Result<NativeAuthCredentials, Failure>]
  private(set) var restoreCallCount = 0
  private(set) var interactiveCallCount = 0
  private(set) var signOutCallCount = 0
  private(set) var interactiveHashedNonces: [String] = []

  init(
    hasPreviousSignIn: Bool,
    restoreResult: Result<NativeAuthCredentials, Failure>,
    interactiveResults: [Result<NativeAuthCredentials, Failure>],
    restoreThrowsCancellation: Bool = false
  ) {
    self.hasPreviousSignIn = hasPreviousSignIn
    self.restoreResult = restoreResult
    self.interactiveResults = interactiveResults
    self.restoreThrowsCancellation = restoreThrowsCancellation
  }

  func configure(with _: NativeSocialAuthConfiguration) {}

  func restorePreviousSignIn() async throws -> NativeAuthCredentials {
    restoreCallCount += 1
    if restoreThrowsCancellation {
      throw CancellationError()
    }
    return try restoreResult.get()
  }

  func signInInteractively(hashedNonce: String) async throws -> NativeAuthCredentials {
    interactiveHashedNonces.append(hashedNonce)
    let result = interactiveResults[min(interactiveCallCount, interactiveResults.count - 1)]
    interactiveCallCount += 1
    return try result.get()
  }

  func signOut() {
    signOutCallCount += 1
    hasPreviousSignIn = false
  }
}
