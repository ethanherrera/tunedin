import SwiftUI

struct EmailVerificationView: View {
  let session: AppSession
  let email: String

  @State private var code = ""
  @State private var isVerifying = false
  @State private var isResending = false
  @State private var errorMessage: String?
  @State private var resendAvailableAt = Date().addingTimeInterval(60)

  var body: some View {
    VStack(alignment: .leading, spacing: 24) {
      Spacer()

      VStack(alignment: .leading, spacing: 8) {
        Text("Check your email")
          .font(.largeTitle.bold())

        Text(verificationExplanation)
          .foregroundStyle(.secondary)
      }

      if session.authEmailDeliveryMode == .oneTimeCode {
        TextField("Six-digit code", text: $code)
          .keyboardType(.numberPad)
          .textContentType(.oneTimeCode)
          .font(.title2.monospacedDigit())
          .multilineTextAlignment(.center)
          .padding(14)
          .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
          .onChange(of: code) { _, newValue in
            let digits = newValue.filter(\.isNumber).prefix(6)
            let sanitizedCode = String(digits)
            if sanitizedCode != newValue {
              code = sanitizedCode
            }
          }
      } else {
        Label("Open the link on this iPhone or Simulator to continue.", systemImage: "link.circle")
          .foregroundStyle(.secondary)
      }

      if let errorMessage {
        Text(errorMessage)
          .font(.footnote)
          .foregroundStyle(.red)
      }

      if session.authEmailDeliveryMode == .oneTimeCode {
        Button {
          verifyCode()
        } label: {
          if isVerifying {
            ProgressView()
              .frame(maxWidth: .infinity)
          } else {
            Text("Verify code")
              .frame(maxWidth: .infinity)
          }
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(isVerifying || code.count != 6)
      }

      TimelineView(.periodic(from: .now, by: 1)) { context in
        Button {
          resendCode()
        } label: {
          if isResending {
            ProgressView()
          } else if resendAvailableAt > context.date {
            Text("Resend available in \(remainingSeconds(from: context.date))s")
          } else {
            Text(resendButtonTitle)
          }
        }
        .disabled(isResending || resendAvailableAt > context.date)
      }

      if session.authEmailDeliveryMode == .magicLink {
        Text(
          "If you read email on your Mac, copy the Sign in link and open it in the Simulator."
        )
        .font(.footnote)
        .foregroundStyle(.secondary)
      }

      Spacer()
    }
    .padding(24)
    .navigationBarTitleDisplayMode(.inline)
  }

  private var verificationExplanation: String {
    switch session.authEmailDeliveryMode {
    case .magicLink:
      "We sent a sign-in link to \(email)."
    case .oneTimeCode:
      "We sent a six-digit code to \(email)."
    }
  }

  private var resendButtonTitle: String {
    switch session.authEmailDeliveryMode {
    case .magicLink:
      "Resend link"
    case .oneTimeCode:
      "Resend code"
    }
  }

  private func verifyCode() {
    isVerifying = true
    errorMessage = nil

    Task {
      do {
        try await session.verifyEmailOTP(email: email, code: code)
      } catch {
        errorMessage = error.localizedDescription
      }
      isVerifying = false
    }
  }

  private func resendCode() {
    isResending = true
    errorMessage = nil

    Task {
      do {
        try await session.sendEmailOTP(to: email)
        resendAvailableAt = Date().addingTimeInterval(60)
      } catch {
        errorMessage = error.localizedDescription
      }
      isResending = false
    }
  }

  private func remainingSeconds(from date: Date) -> Int {
    max(0, Int(resendAvailableAt.timeIntervalSince(date).rounded(.up)))
  }
}
