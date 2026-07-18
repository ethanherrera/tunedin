import AuthenticationServices
import SwiftUI

struct NativeSocialSignInView: View {
  let session: AppSession

  @State private var appleNonce: String?
  @State private var isSubmitting = false
  @State private var errorMessage: String?

  var body: some View {
    ZStack {
      TunedInDesign.pageBackground
        .ignoresSafeArea()

      ScrollView {
        VStack(alignment: .leading, spacing: 22) {
          signInArtwork

          VStack(alignment: .leading, spacing: 8) {
            Text("Your concert life, beautifully kept.")
              .font(.system(size: 34, weight: .bold, design: .rounded))
              .foregroundStyle(TunedInDesign.primaryText)
              .fixedSize(horizontal: false, vertical: true)

            Text("Save every setlist, photo, and shared night in one place.")
              .font(.body)
              .foregroundStyle(TunedInDesign.mutedText)
          }

          Button {
            signInWithGoogle()
          } label: {
            HStack(spacing: 12) {
              Image("GoogleSignInLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 21, height: 21)

              Text("Continue with Google")
                .font(.body.weight(.semibold))
            }
            .foregroundStyle(.black)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(.white, in: Capsule())
            .overlay {
              Capsule().strokeBorder(.black.opacity(0.08))
            }
          }
          .buttonStyle(.plain)
          .disabled(isSubmitting)
          .opacity(isSubmitting ? 0.62 : 1)
          .accessibilityLabel("Continue with Google")

          if isSubmitting {
            HStack(spacing: 10) {
              ProgressView()
              Text("Signing you in…")
            }
            .font(.footnote.weight(.medium))
            .foregroundStyle(TunedInDesign.mutedText)
            .frame(maxWidth: .infinity)
          }

          if let errorMessage {
            Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
              .font(.footnote)
              .foregroundStyle(.red)
              .padding(14)
              .frame(maxWidth: .infinity, alignment: .leading)
              .background(TunedInDesign.cardBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
              .accessibilityIdentifier("social-sign-in-error")
          }

          Text("Google confirms your identity. tunedIn never receives your password.")
            .font(.footnote)
            .foregroundStyle(TunedInDesign.mutedText)
            .frame(maxWidth: .infinity, alignment: .center)
            .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 28)
      }
    }
    .tint(TunedInDesign.accent)
  }

  private var signInArtwork: some View {
    ZStack(alignment: .bottomLeading) {
      LinearGradient(
        colors: [TunedInDesign.ticketViolet, TunedInDesign.ticketRose, TunedInDesign.ink],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
      )

      Circle()
        .fill(.white.opacity(0.18))
        .frame(width: 220, height: 220)
        .blur(radius: 2)
        .offset(x: 150, y: -100)

      Image(systemName: "waveform")
        .font(.system(size: 118, weight: .thin))
        .foregroundStyle(.white.opacity(0.17))
        .offset(x: 118, y: 22)

      VStack(alignment: .leading, spacing: 7) {
        Text("tunedIn")
          .font(.caption.weight(.black))
          .tracking(1.3)
          .textCase(.uppercase)
        Text("Keep the night.")
          .font(.system(size: 38, weight: .bold, design: .serif))
      }
      .foregroundStyle(.white)
      .padding(22)
    }
    .frame(maxWidth: .infinity)
    .frame(height: 284)
    .clipShape(RoundedRectangle(cornerRadius: TunedInDesign.largeCornerRadius, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: TunedInDesign.largeCornerRadius, style: .continuous)
        .strokeBorder(.white.opacity(0.18))
    }
    .accessibilityHidden(true)
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
