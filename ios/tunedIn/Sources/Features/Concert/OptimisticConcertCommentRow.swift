import SwiftUI

struct OptimisticConcertCommentRow: View {
  let comment: OptimisticConcertComment
  let viewerUsername: String
  let onRetry: (OptimisticConcertComment) -> Void

  var body: some View {
    HStack(alignment: .top, spacing: 11) {
      Text(String(viewerUsername.prefix(1)).uppercased())
        .font(.caption.weight(.black))
        .foregroundStyle(.white)
        .frame(width: 40, height: 40)
        .background(TunedInDesign.accent, in: Circle())

      VStack(alignment: .leading, spacing: 6) {
        HStack(spacing: 7) {
          Text("@\(viewerUsername)")
            .font(.subheadline.weight(.bold))
            .foregroundStyle(TunedInDesign.primaryText)
          Spacer()
          status
        }

        Text(comment.body)
          .font(.body)
          .foregroundStyle(TunedInDesign.primaryText)
      }
    }
    .padding(.vertical, 14)
    .overlay(alignment: .bottom) {
      Divider()
        .overlay(TunedInDesign.cardBorder.opacity(0.5))
        .padding(.leading, 51)
    }
  }

  @ViewBuilder
  private var status: some View {
    switch comment.status {
    case .posting:
      HStack(spacing: 5) {
        ProgressView().controlSize(.mini)
        Text("Posting…")
      }
      .font(.caption)
      .foregroundStyle(TunedInDesign.mutedText)
    case .failed:
      Button("Retry") { onRetry(comment) }
        .font(.caption.weight(.bold))
        .foregroundStyle(TunedInDesign.accent)
        .accessibilityHint("Attempts to post this moment again")
    }
  }
}
