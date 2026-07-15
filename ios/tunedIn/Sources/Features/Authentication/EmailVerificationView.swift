import SwiftUI

struct EmailVerificationView: View {
  let session: AppSession
  let email: String

  @Environment(\.dismiss) private var dismiss
  @State private var code = ""
  @State private var isVerifying = false
  @State private var isResending = false
  @State private var errorMessage: String?
  @State private var resendAvailableAt = Date().addingTimeInterval(60)

  var body: some View {
    ZStack {
      TunedInDesign.pageBackground
        .ignoresSafeArea()

      ScrollView {
        VStack(alignment: .leading, spacing: 24) {
          Spacer(minLength: 56)

          Image(systemName: "envelope.open.fill")
            .font(.system(size: 32, weight: .semibold))
            .foregroundStyle(TunedInDesign.accent)
            .frame(width: 68, height: 68)
            .background(TunedInDesign.accentTint, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .accessibilityHidden(true)

          VStack(alignment: .leading, spacing: 8) {
            Text("Check your email")
              .font(.system(size: 34, weight: .bold, design: .rounded))
              .foregroundStyle(TunedInDesign.primaryText)

            Text(verificationExplanation)
              .foregroundStyle(TunedInDesign.mutedText)
          }

          if session.authEmailDeliveryMode == .oneTimeCode {
            TextField("Six-digit code", text: $code)
              .keyboardType(.numberPad)
              .textContentType(.oneTimeCode)
              .font(.title2.monospacedDigit().weight(.semibold))
              .multilineTextAlignment(.center)
              .padding(.horizontal, 14)
              .frame(minHeight: 58)
              .background(
                TunedInDesign.cardBackground,
                in: RoundedRectangle(cornerRadius: TunedInDesign.mediumCornerRadius, style: .continuous)
              )
              .overlay {
                RoundedRectangle(cornerRadius: TunedInDesign.mediumCornerRadius, style: .continuous)
                  .strokeBorder(TunedInDesign.cardBorder.opacity(0.55))
              }
              .onChange(of: code) { _, newValue in
                let digits = newValue.filter(\.isNumber).prefix(6)
                let sanitizedCode = String(digits)
                if sanitizedCode != newValue {
                  code = sanitizedCode
                }
              }
          } else {
            Label("Open the link on this iPhone or Simulator to continue.", systemImage: "link.circle")
              .foregroundStyle(TunedInDesign.mutedText)
          }

          if let errorMessage {
            Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
              .font(.footnote)
              .foregroundStyle(.red)
          }

          if session.authEmailDeliveryMode == .oneTimeCode {
            Button {
              verifyCode()
            } label: {
              HStack(spacing: 9) {
                if isVerifying {
                  ProgressView()
                }
                Text(isVerifying ? "Verifying…" : "Verify code")
              }
              .font(.body.weight(.bold))
              .foregroundStyle(TunedInDesign.actionForeground)
              .frame(maxWidth: .infinity)
              .frame(height: 54)
              .background(TunedInDesign.accent, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(isVerifying || code.count != 6)
            .opacity(isVerifying || code.count != 6 ? 0.5 : 1)
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
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(TunedInDesign.primaryText)
            .disabled(isResending || resendAvailableAt > context.date)
          }

          if session.authEmailDeliveryMode == .magicLink {
            Text(
              "If you read email on your Mac, copy the Sign in link and open it in the Simulator."
            )
            .font(.footnote)
            .foregroundStyle(TunedInDesign.mutedText)
          }

          Spacer(minLength: 24)
        }
        .padding(.horizontal, 22)
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity)
      }
    }
    .navigationBarTitleDisplayMode(.inline)
    .navigationBarBackButtonHidden()
    .safeAreaInset(edge: .bottom, spacing: 0) {
      TunedInPersistentControlRegion {
        TunedInSubscreenBackBar(title: "Email", action: dismiss.callAsFunction)
          .padding(.horizontal, TunedInDesign.bottomControlHorizontalInset)
          .padding(.top, 6)
          .padding(.bottom, TunedInDesign.bottomControlInset)
      }
    }
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
