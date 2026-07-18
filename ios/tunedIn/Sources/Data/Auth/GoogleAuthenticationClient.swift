import AuthenticationServices
import Foundation
import GoogleSignIn
import UIKit

@MainActor
protocol GoogleAuthenticationClient: AnyObject {
  func credentials(
    configuration: NativeSocialAuthConfiguration,
    allowsPreviousSignInRestore: Bool
  ) async throws -> NativeAuthCredentials

  func signOut()
}

@MainActor
final class LiveGoogleAuthenticationClient: GoogleAuthenticationClient {
  private let sdk: any GoogleSignInSDK
  private let nonceGenerator: () throws -> String

  init(
    sdk: any GoogleSignInSDK = LiveGoogleSignInSDK(),
    nonceGenerator: @escaping () throws -> String = { try NativeAuthNonce.random() }
  ) {
    self.sdk = sdk
    self.nonceGenerator = nonceGenerator
  }

  func credentials(
    configuration: NativeSocialAuthConfiguration,
    allowsPreviousSignInRestore: Bool
  ) async throws -> NativeAuthCredentials {
    sdk.configure(with: configuration)

    if allowsPreviousSignInRestore, sdk.hasPreviousSignIn {
      do {
        let restoredCredentials = try await sdk.restorePreviousSignIn()
        if RestoredGoogleIDTokenPolicy.canReuse(restoredCredentials.idToken) {
          return restoredCredentials
        }
      } catch is CancellationError {
        throw CancellationError()
      } catch {
        // A stale or unreadable SDK session should not block a fresh interactive sign-in.
      }
      sdk.signOut()
    }

    let rawNonce = try nonceGenerator()
    let credentials = try await sdk.signInInteractively(
      hashedNonce: NativeAuthNonce.hashed(rawNonce)
    )
    return NativeAuthCredentials(
      provider: .google,
      idToken: credentials.idToken,
      accessToken: credentials.accessToken,
      nonce: rawNonce
    )
  }

  func signOut() {
    sdk.signOut()
  }
}

@MainActor
final class UnavailableGoogleAuthenticationClient: GoogleAuthenticationClient {
  func credentials(
    configuration _: NativeSocialAuthConfiguration,
    allowsPreviousSignInRestore _: Bool
  ) async throws -> NativeAuthCredentials {
    throw AppSessionError.nativeSocialSignInUnavailable
  }

  func signOut() {}
}

@MainActor
protocol GoogleSignInSDK: AnyObject {
  var hasPreviousSignIn: Bool { get }

  func configure(with configuration: NativeSocialAuthConfiguration)
  func restorePreviousSignIn() async throws -> NativeAuthCredentials
  func signInInteractively(hashedNonce: String) async throws -> NativeAuthCredentials
  func signOut()
}

@MainActor
final class LiveGoogleSignInSDK: GoogleSignInSDK {
  private let google: GIDSignIn

  init(google: GIDSignIn = .sharedInstance) {
    self.google = google
  }

  var hasPreviousSignIn: Bool {
    google.hasPreviousSignIn()
  }

  func configure(with configuration: NativeSocialAuthConfiguration) {
    google.configuration = GIDConfiguration(
      clientID: configuration.googleIOSClientID,
      serverClientID: configuration.googleServerClientID
    )
  }

  func restorePreviousSignIn() async throws -> NativeAuthCredentials {
    let user = try await google.restorePreviousSignIn()
    return try Self.credentials(for: user)
  }

  func signInInteractively(hashedNonce: String) async throws -> NativeAuthCredentials {
    guard let presentingViewController = Self.presentingViewController() else {
      throw NativeSocialSignInError.missingPresentationContext
    }

    let result = try await google.signIn(
      withPresenting: presentingViewController,
      hint: nil,
      additionalScopes: nil,
      nonce: hashedNonce
    )
    return try Self.credentials(for: result.user)
  }

  func signOut() {
    google.signOut()
  }

  private nonisolated static func credentials(for user: GIDGoogleUser) throws -> NativeAuthCredentials {
    guard let idToken = user.idToken?.tokenString else {
      throw NativeSocialSignInError.missingGoogleCredential
    }

    return NativeAuthCredentials(
      provider: .google,
      idToken: idToken,
      accessToken: user.accessToken.tokenString,
      nonce: nil
    )
  }

  private static func presentingViewController() -> UIViewController? {
    let root = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .flatMap(\.windows)
      .first(where: \.isKeyWindow)?
      .rootViewController

    var presenter = root
    while let presented = presenter?.presentedViewController {
      presenter = presented
    }
    return presenter
  }
}

enum RestoredGoogleIDTokenPolicy {
  static func canReuse(_ idToken: String) -> Bool {
    let segments = idToken.split(separator: ".", omittingEmptySubsequences: false)
    guard segments.count == 3 else { return false }

    var payload = String(segments[1])
      .replacingOccurrences(of: "-", with: "+")
      .replacingOccurrences(of: "_", with: "/")
    let paddingCount = (4 - payload.count % 4) % 4
    payload.append(String(repeating: "=", count: paddingCount))

    guard
      let data = Data(base64Encoded: payload),
      let claims = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else {
      return false
    }

    return !claims.keys.contains("nonce")
  }
}

enum NativeSocialSignInError: LocalizedError {
  case missingAppleCredential
  case missingGoogleCredential
  case missingPresentationContext
  case nonceGenerationFailed

  var errorDescription: String? {
    switch self {
    case .missingAppleCredential:
      "Apple didn’t return a valid sign-in credential. Please try again."
    case .missingGoogleCredential:
      "Google didn’t return a valid sign-in credential. Please try again."
    case .missingPresentationContext:
      "The sign-in screen isn’t ready yet. Please try again."
    case .nonceGenerationFailed:
      "A secure sign-in request couldn’t be created. Please try again."
    }
  }

  static func isCancellation(_ error: any Error) -> Bool {
    if error is CancellationError {
      return true
    }
    let error = error as NSError
    let isAppleCancellation = error.domain == ASAuthorizationError.errorDomain
      && error.code == ASAuthorizationError.canceled.rawValue
    if isAppleCancellation {
      return true
    }
    return error.domain == kGIDSignInErrorDomain && error.code == -5
  }

  static func message(for error: any Error) -> String {
    if let error = error as? NativeSocialSignInError {
      return error.localizedDescription
    }
    return AppFailure(error).localizedDescription
  }

  static func statusClass(for provider: NativeAuthProvider, error: any Error) -> String {
    if let error = error as? NativeSocialSignInError {
      return switch error {
      case .missingAppleCredential: "apple_missing_credential"
      case .missingGoogleCredential: "google_missing_credential"
      case .missingPresentationContext: "presentation_unavailable"
      case .nonceGenerationFailed: "nonce_generation"
      }
    }

    let error = error as NSError
    if provider == .apple, error.domain == ASAuthorizationError.errorDomain {
      return "apple_authorization_\(error.code)"
    }
    if provider == .google, error.domain == kGIDSignInErrorDomain {
      return "google_sdk_\(error.code)"
    }
    return "provider_response"
  }
}
