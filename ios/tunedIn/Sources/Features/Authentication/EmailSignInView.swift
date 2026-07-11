import SwiftUI

struct EmailSignInView: View {
  let session: AppSession

  @State private var email = ""
  @State private var path: [String] = []
  @State private var isSubmitting = false
  @State private var errorMessage: String?

  var body: some View {
    NavigationStack(path: $path) {
      VStack(alignment: .leading, spacing: 24) {
        Spacer()

        Image(systemName: "music.note.list")
          .font(.system(size: 42, weight: .semibold))
          .foregroundStyle(.tint)
          .accessibilityHidden(true)

        VStack(alignment: .leading, spacing: 8) {
          Text("Welcome to tunedIn")
            .font(.largeTitle.bold())

          Text(signInExplanation)
            .foregroundStyle(.secondary)
        }

        TextField("Email address", text: $email)
          .textContentType(.emailAddress)
          .textInputAutocapitalization(.never)
          .keyboardType(.emailAddress)
          .autocorrectionDisabled()
          .padding(14)
          .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))

        if let errorMessage {
          Text(errorMessage)
            .font(.footnote)
            .foregroundStyle(.red)
        }

        Button {
          sendCode()
        } label: {
          if isSubmitting {
            ProgressView()
              .frame(maxWidth: .infinity)
          } else {
            Text(submitButtonTitle)
              .frame(maxWidth: .infinity)
          }
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(isSubmitting || !isEmailValid)

        Spacer()
      }
      .padding(24)
      .navigationDestination(for: String.self) { email in
        EmailVerificationView(session: session, email: email)
      }
    }
  }

  private var normalizedEmail: String {
    email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
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
}
