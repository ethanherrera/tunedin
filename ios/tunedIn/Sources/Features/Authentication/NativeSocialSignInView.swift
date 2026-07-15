import AuthenticationServices
import CryptoKit
import Security
import SwiftUI

struct NativeSocialSignInView: View {
  let session: AppSession

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
        Button {
          signInWithGoogle()
        } label: {
          HStack(spacing: 12) {
            Image("GoogleSignInLogo")
              .resizable()
              .scaledToFit()
              .frame(width: 22, height: 22)

            Text("Continue with Google")
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

      Text("Google will confirm your identity. tunedIn never receives your password.")
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
        credentials = try await session.googleCredentials()
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
        if !NativeSocialSignInError.isCancellation(error) {
          errorMessage = NativeSocialSignInError.message(for: error)
        }
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
