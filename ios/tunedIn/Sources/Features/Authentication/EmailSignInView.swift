import SwiftUI

struct EmailSignInView: View {
  let session: AppSession

  @State private var email = ""
  @State private var path: [String] = []
  @State private var isSubmitting = false
  @State private var errorMessage: String?

  var body: some View {
    NavigationStack(path: $path) {
      ZStack {
        TunedInDesign.pageBackground
          .ignoresSafeArea()

        ScrollView {
          VStack(alignment: .leading, spacing: 22) {
            emailArtwork

            VStack(alignment: .leading, spacing: 8) {
              Text("Welcome to tunedIn")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(TunedInDesign.primaryText)

              Text(signInExplanation)
                .foregroundStyle(TunedInDesign.mutedText)
            }

            TextField("Email address", text: $email)
              .textContentType(.emailAddress)
              .textInputAutocapitalization(.never)
              .keyboardType(.emailAddress)
              .autocorrectionDisabled()
              .padding(.horizontal, 16)
              .frame(minHeight: 54)
              .background(
                TunedInDesign.cardBackground,
                in: RoundedRectangle(cornerRadius: TunedInDesign.mediumCornerRadius, style: .continuous)
              )
              .overlay {
                RoundedRectangle(cornerRadius: TunedInDesign.mediumCornerRadius, style: .continuous)
                  .strokeBorder(TunedInDesign.cardBorder.opacity(0.55))
              }

            if let errorMessage {
              Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                .font(.footnote)
                .foregroundStyle(.red)
            }

            Button {
              sendCode()
            } label: {
              HStack(spacing: 9) {
                if isSubmitting {
                  ProgressView()
                }
                Text(isSubmitting ? "Sending…" : submitButtonTitle)
              }
              .font(.body.weight(.bold))
              .foregroundStyle(TunedInDesign.actionForeground)
              .frame(maxWidth: .infinity)
              .frame(height: 54)
              .background(TunedInDesign.accent, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(isSubmitting || !isEmailValid)
            .opacity(isSubmitting || !isEmailValid ? 0.5 : 1)

            if session.allowsLocalSeededSignIn {
              localSeededAccountSignIn
            }

            Spacer(minLength: 24)
          }
          .padding(.horizontal, 22)
          .padding(.top, 12)
          .frame(maxWidth: 560)
          .frame(maxWidth: .infinity)
        }
      }
      .navigationDestination(for: String.self) { email in
        EmailVerificationView(session: session, email: email)
      }
    }
  }

  private var normalizedEmail: String {
    email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
  }

  private var emailArtwork: some View {
    ZStack(alignment: .bottomLeading) {
      LinearGradient(
        colors: [TunedInDesign.ticketViolet, TunedInDesign.ticketRose, TunedInDesign.ink],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
      )

      Circle()
        .fill(.white.opacity(0.16))
        .frame(width: 150, height: 150)
        .offset(x: 190, y: -54)

      Image(systemName: "waveform")
        .font(.system(size: 82, weight: .thin))
        .foregroundStyle(.white.opacity(0.17))
        .offset(x: 158, y: 18)

      VStack(alignment: .leading, spacing: 4) {
        Text("tunedIn")
          .font(.caption.weight(.black))
          .tracking(1.2)
          .textCase(.uppercase)
        Text("Keep the night.")
          .font(.system(size: 31, weight: .bold, design: .serif))
      }
      .foregroundStyle(.white)
      .padding(20)
    }
    .frame(maxWidth: .infinity)
    .frame(height: 188)
    .clipShape(RoundedRectangle(cornerRadius: TunedInDesign.largeCornerRadius, style: .continuous))
    .accessibilityHidden(true)
  }

  private var signInExplanation: String {
    switch session.authEmailDeliveryMode {
    case .magicLink:
      "Enter your email and we’ll send a secure sign-in link."
    case .oneTimeCode:
      "Enter your email and we’ll send a six-digit sign-in code."
    }
  }

  private var submitButtonTitle: String {
    switch session.authEmailDeliveryMode {
    case .magicLink:
      "Email me a sign-in link"
    case .oneTimeCode:
      "Email me a code"
    }
  }

  private var isEmailValid: Bool {
    normalizedEmail.range(
      of: "^[^\\s@]+@[^\\s@]+\\.[^\\s@]+$",
      options: .regularExpression
    ) != nil
  }

  private var localSeededAccountSignIn: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Local test accounts")
        .font(.headline)
        .foregroundStyle(TunedInDesign.primaryText)

      Text("Sign in as a seeded account without waiting for an email link.")
        .font(.footnote)
        .foregroundStyle(TunedInDesign.mutedText)

      Button {
        signIn(to: .listener)
      } label: {
        Label("Continue as Local Listener", systemImage: "person.fill.checkmark")
          .frame(maxWidth: .infinity)
      }
      .buttonStyle(.bordered)
      .controlSize(.large)
      .disabled(isSubmitting)

      Menu {
        ForEach(LocalSeededAccount.allCases) { account in
          Button(account.displayName) {
            signIn(to: account)
          }
        }
      } label: {
        Label("Choose another seeded account", systemImage: "person.2")
          .frame(maxWidth: .infinity)
      }
      .buttonStyle(.bordered)
      .controlSize(.large)
      .disabled(isSubmitting)
    }
    .padding(18)
    .background(
      TunedInDesign.cardBackground,
      in: RoundedRectangle(cornerRadius: TunedInDesign.cornerRadius, style: .continuous)
    )
  }

  private func sendCode() {
    isSubmitting = true
    errorMessage = nil
    let address = normalizedEmail

    Task {
      do {
        try await session.sendEmailOTP(to: address)
        path.append(address)
      } catch {
        errorMessage = error.localizedDescription
      }
      isSubmitting = false
    }
  }

  private func signIn(to account: LocalSeededAccount) {
    isSubmitting = true
    errorMessage = nil

    Task {
      do {
        try await session.signIn(to: account)
      } catch {
        errorMessage = error.localizedDescription
      }
      isSubmitting = false
    }
  }
}
