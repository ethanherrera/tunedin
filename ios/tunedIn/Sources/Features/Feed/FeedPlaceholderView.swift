import SwiftUI

struct FeedPlaceholderView: View {
  let onCreateConcert: () -> Void

  var body: some View {
    ZStack {
      TunedInDesign.pageBackground
        .ignoresSafeArea()

      ScrollView {
        VStack(alignment: .leading, spacing: 28) {
          VStack(alignment: .leading, spacing: 8) {
            Text("tunedIn")
              .font(.title3.weight(.black))
              .foregroundStyle(TunedInDesign.accent)

            Text("Every show\nyou keep.")
              .font(.system(size: 40, weight: .bold, design: .serif))
              .foregroundStyle(TunedInDesign.primaryText)

            Text("A private concert diary for the nights that stay with you.")
              .font(.subheadline)
              .foregroundStyle(TunedInDesign.mutedText)
          }

          TunedInTicketCard {
            VStack(alignment: .leading, spacing: 18) {
              Label("YOUR NEXT MEMORY", systemImage: "sparkles")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white.opacity(0.82))

              Text("What was the last show you saw?")
                .font(.title2.weight(.bold))
                .foregroundStyle(.white)

              Button(action: onCreateConcert) {
                Label("Log the night", systemImage: "arrow.up.right")
                  .font(.subheadline.weight(.bold))
                  .foregroundStyle(TunedInDesign.actionForeground)
                  .padding(.horizontal, 16)
                  .padding(.vertical, 12)
                  .background(TunedInDesign.accent, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
              }
              .buttonStyle(.plain)
            }
          }

          VStack(alignment: .leading, spacing: 10) {
            Text("Your archive starts here.")
              .font(.headline)
              .foregroundStyle(TunedInDesign.primaryText)
            Text("Log the show now. Add every detail that makes it yours whenever you’re ready.")
              .font(.subheadline)
              .foregroundStyle(TunedInDesign.mutedText)
          }
          .padding(.horizontal, 4)
        }
        .padding(.horizontal, 24)
        .padding(.top, 24)
        .padding(.bottom, 112)
      }
    }
    .toolbar(.hidden, for: .navigationBar)
  }
}
