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

        Text("We sent a six-digit code to \(email).")
          .foregroundStyle(.secondary)
      }

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

      if let errorMessage {
        Text(errorMessage)
          .font(.footnote)
          .foregroundStyle(.red)
      }

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

      TimelineView(.periodic(from: .now, by: 1)) { context in
        Button {
          resendCode()
        } label: {
          if isResending {
            ProgressView()
          } else if resendAvailableAt > context.date {
            Text("Resend available in \(remainingSeconds(from: context.date))s")
          } else {
            Text("Resend code")
          }
        }
        .disabled(isResending || resendAvailableAt > context.date)
      }

      Text(
        "During Development, the temporary email provider may send a sign-in link instead. "
          + "Opening it on this device will finish sign-in."
      )
      .font(.footnote)
      .foregroundStyle(.secondary)

      Spacer()
    }
    .padding(24)
    .navigationBarTitleDisplayMode(.inline)
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
