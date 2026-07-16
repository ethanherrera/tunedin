import SwiftUI

struct TunedInGlassTextButton: View {
  let title: String
  let systemImage: String
  let accessibilityHint: String
  let action: () -> Void
  @Environment(\.tunedInKeyboardPresentation) private var keyboardPresentation

  init(
    _ title: String,
    systemImage: String,
    accessibilityHint: String = "",
    action: @escaping () -> Void
  ) {
    self.title = title
    self.systemImage = systemImage
    self.accessibilityHint = accessibilityHint
    self.action = action
  }

  var body: some View {
    if keyboardPresentation.showsPersistentGlass {
      Button(action: action) {
        Label(title, systemImage: systemImage)
          .font(.subheadline.weight(.bold))
          .foregroundStyle(TunedInDesign.actionForeground)
          .padding(.horizontal, 18)
          .frame(height: TunedInDesign.controlSize)
          .contentShape(.interaction, Capsule())
          .modifier(TunedInLiquidGlassTextActionSurface())
      }
      .buttonStyle(.plain)
      .contentShape(.interaction, Capsule())
      .accessibilityHint(accessibilityHint)
    }
  }
}

private struct TunedInLiquidGlassTextActionSurface: ViewModifier {
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
  @Environment(\.colorSchemeContrast) private var colorSchemeContrast

  func body(content: Content) -> some View {
    if #available(iOS 26.0, *), !reduceTransparency {
      content
        .glassEffect(.regular.tint(TunedInDesign.accent.opacity(0.22)).interactive(), in: .capsule)
    } else {
      content
        .background {
          if reduceTransparency {
            Capsule().fill(TunedInDesign.accent)
          } else {
            Capsule().fill(.ultraThinMaterial)
          }
        }
        .background(TunedInDesign.accent.opacity(0.14), in: Capsule())
        .overlay {
          Capsule()
            .strokeBorder(
              TunedInDesign.cardBorder.opacity(colorSchemeContrast == .increased ? 1 : 0.85)
            )
        }
        .shadow(color: TunedInDesign.accent.opacity(0.2), radius: 12, y: 6)
    }
  }
}
