import SwiftUI
import UIKit

enum TunedInDesign {
  static let accent = Color(red: 1.0, green: 0.34, blue: 0.13)
  static let accentTint = adaptive(light: 0xF8DCCD, dark: 0x3D150B)
  static let accentWash = adaptive(light: 0xF7A489, dark: 0xFFB899)
  static let pageBackground = adaptive(light: 0xFCF6EF, dark: 0x0E0C0B)
  static let cardBackground = adaptive(light: 0xFFFCF8, dark: 0x1D1715)
  static let raisedSurface = adaptive(light: 0xF1E7DC, dark: 0x2B211D)
  static let primaryText = adaptive(light: 0x2C1711, dark: 0xFFF8F3)
  static let mutedText = adaptive(light: 0x715B51, dark: 0xB8A8A0)
  static let cardBorder = adaptive(light: 0xE9D9CB, dark: 0xFFFFFF)
  static let ink = Color(red: 0.12, green: 0.045, blue: 0.025)
  static let actionForeground = adaptive(light: 0x2C1711, dark: 0xFFF8F3)
  static let ticketViolet = adaptive(light: 0xFC552B, dark: 0xE03317)
  static let ticketRose = adaptive(light: 0xB52E46, dark: 0x701626)
  static let cornerRadius: CGFloat = 18

  private static func adaptive(light: Int, dark: Int) -> Color {
    Color(
      uiColor: UIColor { traitCollection in
        UIColor(
          rgb: traitCollection.userInterfaceStyle == .dark ? dark : light
        )
      }
    )
  }
}

private extension UIColor {
  convenience init(rgb: Int) {
    self.init(
      red: CGFloat((rgb >> 16) & 0xFF) / 255,
      green: CGFloat((rgb >> 8) & 0xFF) / 255,
      blue: CGFloat(rgb & 0xFF) / 255,
      alpha: 1
    )
  }
}

struct TunedInFloatingAction: View {
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Image(systemName: "plus")
        .font(.system(size: 20, weight: .bold))
        .foregroundStyle(TunedInDesign.actionForeground)
    }
    .buttonStyle(.plain)
    .frame(width: 56, height: 56)
    .contentShape(Circle())
    .modifier(TunedInLiquidGlassActionSurface())
    .accessibilityLabel("Log concert")
    .accessibilityHint("Opens the new concert form")
  }
}

private struct TunedInLiquidGlassActionSurface: ViewModifier {
  func body(content: Content) -> some View {
    if #available(iOS 26.0, *) {
      content
        .glassEffect(.regular.tint(TunedInDesign.accent.opacity(0.28)).interactive(), in: .circle)
    } else {
      content
        .background(.ultraThinMaterial, in: Circle())
        .background(TunedInDesign.accent.opacity(0.18), in: Circle())
        .overlay {
          Circle()
            .strokeBorder(.white.opacity(0.52))
        }
        .shadow(color: TunedInDesign.accent.opacity(0.2), radius: 12, y: 6)
    }
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
        .strokeBorder(TunedInDesign.cardBorder.opacity(0.72))
    }
  }
}

struct TunedInGlassSection<Content: View>: View {
  @ViewBuilder let content: Content

  var body: some View {
    content
      .padding(16)
      .modifier(TunedInLiquidGlassSectionSurface())
  }
}

struct TunedInGlassSearchField: View {
  @Binding var text: String
  let prompt: String

  var body: some View {
    HStack(spacing: 10) {
      Image(systemName: "magnifyingglass")
        .foregroundStyle(TunedInDesign.mutedText)

      TextField(prompt, text: $text)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .foregroundStyle(TunedInDesign.primaryText)

      if !text.isEmpty {
        Button {
          text = ""
        } label: {
          Image(systemName: "xmark.circle.fill")
            .foregroundStyle(TunedInDesign.mutedText)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Clear search")
      }
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 13)
    .modifier(TunedInLiquidGlassSearchSurface())
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
      .foregroundStyle(TunedInDesign.actionForeground)
      .padding(.horizontal, 10)
      .padding(.vertical, 6)
      .background(TunedInDesign.accent, in: Capsule())
      .accessibilityLabel("Private concert")
  }
}

private struct TunedInLiquidGlassSectionSurface: ViewModifier {
  func body(content: Content) -> some View {
    if #available(iOS 26.0, *) {
      content
        .glassEffect(
          .regular.tint(TunedInDesign.accent.opacity(0.08)).interactive(),
          in: RoundedRectangle(cornerRadius: TunedInDesign.cornerRadius, style: .continuous)
        )
    } else {
      content
        .background(
          .thinMaterial,
          in: RoundedRectangle(cornerRadius: TunedInDesign.cornerRadius, style: .continuous)
        )
        .background(
          TunedInDesign.cardBackground.opacity(0.72),
          in: RoundedRectangle(cornerRadius: TunedInDesign.cornerRadius, style: .continuous)
        )
        .overlay {
          RoundedRectangle(cornerRadius: TunedInDesign.cornerRadius, style: .continuous)
            .strokeBorder(.white.opacity(0.46))
        }
    }
  }
}

private struct TunedInLiquidGlassSearchSurface: ViewModifier {
  func body(content: Content) -> some View {
    if #available(iOS 26.0, *) {
      content
        .glassEffect(
          .regular.tint(TunedInDesign.accent.opacity(0.05)).interactive(),
          in: Capsule()
        )
    } else {
      content
        .background(.ultraThinMaterial, in: Capsule())
        .background(TunedInDesign.cardBackground.opacity(0.8), in: Capsule())
        .overlay {
          Capsule()
            .strokeBorder(TunedInDesign.cardBorder.opacity(0.85))
        }
    }
  }
}
