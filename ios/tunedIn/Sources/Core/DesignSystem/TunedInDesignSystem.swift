import SwiftUI

enum TunedInDesign {
  static let accent = Color(red: 1.0, green: 0.34, blue: 0.13)
  static let accentTint = Color(red: 0.24, green: 0.08, blue: 0.045)
  static let accentWash = Color(red: 1.0, green: 0.72, blue: 0.58)
  static let pageBackground = Color(red: 0.055, green: 0.047, blue: 0.043)
  static let cardBackground = Color(red: 0.115, green: 0.092, blue: 0.082)
  static let raisedSurface = Color(red: 0.17, green: 0.13, blue: 0.115)
  static let ink = Color(red: 0.12, green: 0.045, blue: 0.025)
  static let mutedText = Color(red: 0.72, green: 0.66, blue: 0.61)
  static let ticketViolet = Color(red: 0.88, green: 0.20, blue: 0.09)
  static let ticketRose = Color(red: 0.48, green: 0.08, blue: 0.15)
  static let cornerRadius: CGFloat = 18
}

struct TunedInFloatingAction: View {
  let title: String
  let systemImage: String
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Label(title, systemImage: systemImage)
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(TunedInDesign.ink)
        .padding(.horizontal, 18)
        .padding(.vertical, 13)
    }
    .buttonStyle(.plain)
    .background(TunedInDesign.accent, in: Capsule())
    .shadow(color: TunedInDesign.accent.opacity(0.25), radius: 18, y: 8)
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
    .overlay {
      RoundedRectangle(cornerRadius: TunedInDesign.cornerRadius, style: .continuous)
        .strokeBorder(.white.opacity(0.08))
    }
  }
}

struct TunedInTicketCard<Content: View>: View {
  @ViewBuilder let content: Content

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      content
    }
    .padding(20)
    .background {
      LinearGradient(
        colors: [TunedInDesign.ticketViolet, TunedInDesign.ticketRose],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
      )
      .overlay(alignment: .topTrailing) {
        Circle()
          .fill(.white.opacity(0.14))
          .frame(width: 180, height: 180)
          .offset(x: 60, y: -84)
      }
    }
    .clipShape(RoundedRectangle(cornerRadius: TunedInDesign.cornerRadius, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: TunedInDesign.cornerRadius, style: .continuous)
        .strokeBorder(.white.opacity(0.25))
    }
    .shadow(color: TunedInDesign.ticketRose.opacity(0.24), radius: 24, y: 12)
  }
}

struct TunedInPrivacyBadge: View {
  var body: some View {
    Label("Private", systemImage: "lock.fill")
      .font(.caption.weight(.semibold))
      .foregroundStyle(TunedInDesign.ink)
      .padding(.horizontal, 10)
      .padding(.vertical, 6)
      .background(TunedInDesign.accent, in: Capsule())
      .accessibilityLabel("Private concert")
  }
}
