import SwiftUI

struct FeedbackView: View {
  let session: AppSession
  let onSubmitted: () -> Void

  @Environment(\.dismiss) private var dismiss
  @State private var category = TelemetryFeedbackCategory.bug
  @State private var message = ""
  @State private var isSubmitting = false
  @State private var errorMessage: String?

  private let characterLimit = 2_000

  var body: some View {
    ZStack {
      TunedInDesign.pageBackground.ignoresSafeArea()

      ScrollView {
        VStack(alignment: .leading, spacing: 22) {
          Text("Send feedback")
            .font(.system(.largeTitle, design: .serif).weight(.bold))
            .foregroundStyle(TunedInDesign.primaryText)

          Text("Tell us what happened or what would make tunedIn better. This message is voluntary and is deleted after 90 days.")
            .font(.subheadline)
            .foregroundStyle(TunedInDesign.mutedText)

          TunedInFormCard {
            Text("What kind of feedback is this?")
              .font(.headline)
            Picker("Feedback category", selection: $category) {
              ForEach(TelemetryFeedbackCategory.allCases) { category in
                Text(category.title).tag(category)
              }
            }
            .pickerStyle(.menu)
          }

          TunedInFormCard {
            Text("Message")
              .font(.headline)
            TextEditor(text: $message)
              .frame(minHeight: 180)
              .scrollContentBackground(.hidden)
              .onChange(of: message) { _, newValue in
                if newValue.count > characterLimit {
                  message = String(newValue.prefix(characterLimit))
                }
              }
            Text("\(message.count) of \(characterLimit)")
              .font(.caption.monospacedDigit())
              .foregroundStyle(TunedInDesign.mutedText)
              .frame(maxWidth: .infinity, alignment: .trailing)
          }

          if let errorMessage {
            Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
              .font(.footnote)
              .foregroundStyle(.red)
          }
        }
        .padding(20)
        .padding(.bottom, TunedInDesign.scrollContentBottomInset)
      }
    }
    .safeAreaInset(edge: .bottom, spacing: 0) {
      feedbackControls
        .padding(.horizontal, 18)
        .padding(.bottom, 10)
    }
    .interactiveDismissDisabled(isSubmitting)
    .tunedInKeyboardManaged()
  }

  private var feedbackControls: some View {
    TunedInGlassTraversalLayout {
      TunedInGlassIconButton(
        systemImage: "xmark",
        accessibilityLabel: "Close feedback"
      ) {
        dismiss()
      }
      .disabled(isSubmitting)
    } center: {
      TunedInGlassBottomBar {
        Text(isSubmitting ? "Sending…" : "Feedback")
          .font(.subheadline.weight(.bold))
          .foregroundStyle(TunedInDesign.primaryText)
          .frame(minWidth: 132, minHeight: 48)
          .padding(.horizontal, 14)
      }
    } trailing: {
      TunedInGlassIconButton(
        systemImage: "arrow.up",
        accessibilityLabel: "Send feedback",
        style: .accent
      ) {
        Task { await submit() }
      }
      .disabled(!canSubmit || isSubmitting)
    }
  }

  private var canSubmit: Bool {
    !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  private func submit() async {
    guard canSubmit else { return }
    isSubmitting = true
    errorMessage = nil
    defer { isSubmitting = false }
    do {
      try await session.submitFeedback(category: category, message: message)
      onSubmitted()
      dismiss()
    } catch {
      errorMessage = error.localizedDescription
    }
  }
}
