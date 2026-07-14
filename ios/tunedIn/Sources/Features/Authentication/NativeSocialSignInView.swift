import AuthenticationServices
import CryptoKit
import GoogleSignIn
import Security
import SwiftUI
import UIKit

struct NativeSocialSignInView: View {
  let session: AppSession
  let configuration: NativeSocialAuthConfiguration

  @State private var appleNonce: String?
  @State private var isSubmitting = false
  @State private var errorMessage: String?

  var body: some View {
    VStack(alignment: .leading, spacing: 24) {
      Spacer()

      Image(systemName: "music.note.list")
        .font(.system(size: 44, weight: .semibold))
        .foregroundStyle(.tint)
        .accessibilityHidden(true)

      VStack(alignment: .leading, spacing: 8) {
        Text("Welcome to tunedIn")
          .font(.largeTitle.bold())

        Text("Keep the concerts you love and share the night with your circle.")
          .foregroundStyle(.secondary)
      }

      VStack(spacing: 14) {
        SignInWithAppleButton(.signIn) { request in
          prepareAppleRequest(request)
        } onCompletion: { result in
          handleAppleCompletion(result)
        }
        .signInWithAppleButtonStyle(.white)
        .frame(maxWidth: .infinity)
        .frame(height: 56)
        .clipShape(Capsule())
        .allowsHitTesting(!isSubmitting)
        .opacity(isSubmitting ? 0.6 : 1)
        .accessibilityLabel("Continue with Apple")

        Button {
          signInWithGoogle()
        } label: {
          HStack(spacing: 12) {
            Image("GoogleSignInLogo")
              .resizable()
              .scaledToFit()
              .frame(width: 22, height: 22)

            Text("Sign in with Google")
              .font(.system(size: 19, weight: .semibold))
          }
          .foregroundStyle(.black)
          .frame(maxWidth: .infinity)
          .frame(height: 56)
          .background(.white, in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(isSubmitting)
        .opacity(isSubmitting ? 0.6 : 1)
        .accessibilityLabel("Continue with Google")
      }

      if isSubmitting {
        HStack(spacing: 10) {
          ProgressView()
          Text("Signing you in…")
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity)
      }

      if let errorMessage {
        Text(errorMessage)
          .font(.footnote)
          .foregroundStyle(.red)
          .accessibilityIdentifier("social-sign-in-error")
      }

      Text("Apple or Google will confirm your identity. tunedIn never receives your password.")
        .font(.footnote)
        .foregroundStyle(.tertiary)

      Spacer()
    }
    .padding(24)
  }

  private func prepareAppleRequest(_ request: ASAuthorizationAppleIDRequest) {
    errorMessage = nil
    do {
      let nonce = try NativeAuthNonce.random()
      appleNonce = nonce
      request.requestedScopes = [.email]
      request.nonce = NativeAuthNonce.hashed(nonce)
    } catch {
      appleNonce = nil
      session.recordNativeAuthenticationFailure(
        provider: .apple,
        error: error,
        statusClass: NativeSocialSignInError.statusClass(for: .apple, error: error)
      )
      errorMessage = error.localizedDescription
    }
  }

  private func handleAppleCompletion(_ result: Result<ASAuthorization, any Error>) {
    guard !isSubmitting else { return }

    do {
      let authorization = try result.get()
      guard
        let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
        let tokenData = credential.identityToken,
        let idToken = String(data: tokenData, encoding: .utf8),
        let nonce = appleNonce
      else {
        throw NativeSocialSignInError.missingAppleCredential
      }

      submit(
        NativeAuthCredentials(
          provider: .apple,
          idToken: idToken,
          accessToken: nil,
          nonce: nonce
        )
      )
    } catch {
      guard !NativeSocialSignInError.isCancellation(error) else { return }
      session.recordNativeAuthenticationFailure(
        provider: .apple,
        error: error,
        statusClass: NativeSocialSignInError.statusClass(for: .apple, error: error)
      )
      errorMessage = NativeSocialSignInError.message(for: error)
    }
  }

  private func signInWithGoogle() {
    guard !isSubmitting else { return }
    isSubmitting = true
    errorMessage = nil

    Task {
      let credentials: NativeAuthCredentials
      do {
        credentials = try await GoogleNativeSignIn.credentials(configuration: configuration)
      } catch {
        if !NativeSocialSignInError.isCancellation(error) {
          session.recordNativeAuthenticationFailure(
            provider: .google,
            error: error,
            statusClass: NativeSocialSignInError.statusClass(for: .google, error: error)
          )
          errorMessage = NativeSocialSignInError.message(for: error)
        }
        isSubmitting = false
        return
      }

      do {
        try await session.signIn(with: credentials)
      } catch {
        errorMessage = NativeSocialSignInError.message(for: error)
      }
      isSubmitting = false
    }
  }

  private func submit(_ credentials: NativeAuthCredentials) {
    isSubmitting = true
    errorMessage = nil

    Task {
      do {
        try await session.signIn(with: credentials)
      } catch {
        errorMessage = NativeSocialSignInError.message(for: error)
      }
      isSubmitting = false
    }
  }
}

enum NativeAuthNonce {
  private static let characters = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")

  static func random(length: Int = 32) throws -> String {
    precondition(length > 0)
    var bytes = [UInt8](repeating: 0, count: length)
    let status = bytes.withUnsafeMutableBytes { buffer in
      SecRandomCopyBytes(kSecRandomDefault, buffer.count, buffer.baseAddress!)
    }
    guard status == errSecSuccess else {
      throw NativeSocialSignInError.nonceGenerationFailed
    }
    return String(bytes.map { characters[Int($0) % characters.count] })
  }

  static func hashed(_ nonce: String) -> String {
    SHA256.hash(data: Data(nonce.utf8)).map { String(format: "%02x", $0) }.joined()
  }
}

@MainActor
private enum GoogleNativeSignIn {
  static func credentials(configuration: NativeSocialAuthConfiguration) async throws -> NativeAuthCredentials {
    let google = GIDSignIn.sharedInstance
    google.configuration = GIDConfiguration(
      clientID: configuration.googleIOSClientID,
      serverClientID: configuration.googleServerClientID
    )

    if google.hasPreviousSignIn(),
       let restoredCredentials = try? await restoredCredentials(using: google) {
      return restoredCredentials
    }

    guard let presentingViewController = presentingViewController() else {
      throw NativeSocialSignInError.missingPresentationContext
    }

    return try await withCheckedThrowingContinuation { continuation in
      google.signIn(
        withPresenting: presentingViewController,
        hint: nil,
        additionalScopes: nil
      ) { result, error in
        if let error {
          continuation.resume(throwing: error)
          return
        }
        guard let user = result?.user else {
          continuation.resume(throwing: NativeSocialSignInError.missingGoogleCredential)
          return
        }

        do {
          continuation.resume(returning: try credentials(for: user))
        } catch {
          continuation.resume(throwing: error)
        }
      }
    }
  }

  private static func restoredCredentials(using google: GIDSignIn) async throws -> NativeAuthCredentials {
    try await withCheckedThrowingContinuation { continuation in
      google.restorePreviousSignIn { user, error in
        if let error {
          continuation.resume(throwing: error)
          return
        }
        guard let user else {
          continuation.resume(throwing: NativeSocialSignInError.missingGoogleCredential)
          return
        }

        do {
          continuation.resume(returning: try credentials(for: user))
        } catch {
          continuation.resume(throwing: error)
        }
      }
    }
  }

  nonisolated private static func credentials(for user: GIDGoogleUser) throws -> NativeAuthCredentials {
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

private enum NativeSocialSignInError: LocalizedError {
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
