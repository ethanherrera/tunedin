import SwiftUI

enum TunedInDesign {
  static let accent = Color(red: 0.36, green: 0.24, blue: 0.86)
  static let accentTint = Color(red: 0.93, green: 0.90, blue: 1.0)
  static let cardBackground = Color(uiColor: .secondarySystemGroupedBackground)
  static let pageBackground = Color(uiColor: .systemGroupedBackground)
  static let cornerRadius: CGFloat = 20
}

struct TunedInFloatingAction: View {
  let title: String
  let systemImage: String
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Label(title, systemImage: systemImage)
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.primary)
        .padding(.horizontal, 18)
        .padding(.vertical, 13)
    }
    .buttonStyle(.plain)
    .background {
      if #available(iOS 26.0, *) {
        Capsule()
          .fill(.clear)
          .glassEffect(.regular.interactive())
      } else {
        Capsule()
          .fill(.ultraThinMaterial)
          .overlay {
            Capsule()
              .strokeBorder(.white.opacity(0.35))
          }
      }
    }
    .shadow(color: .black.opacity(0.16), radius: 16, y: 8)
    .accessibilityHint("Opens the new concert form")
  }
}

struct TunedInFormCard<Content: View>: View {
  @ViewBuilder let content: Content

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      content
    }
    .padding(16)
    .background(
      TunedInDesign.cardBackground,
      in: RoundedRectangle(cornerRadius: TunedInDesign.cornerRadius, style: .continuous)
    )
  }
}
