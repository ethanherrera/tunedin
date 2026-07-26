import SwiftUI
import UIKit

enum TunedInDesign {
  static let accent = adaptive(light: 0x5747E8, dark: 0xA89FFF)
  static let accentTint = adaptive(light: 0xECE9FF, dark: 0x292544)
  static let accentWash = adaptive(light: 0x7D70F2, dark: 0xC2BCFF)
  static let pageBackground = adaptive(light: 0xFAFAF7, dark: 0x121211)
  static let cardBackground = adaptive(light: 0xFFFFFF, dark: 0x1C1C1A)
  static let raisedSurface = adaptive(light: 0xF0F0EC, dark: 0x282825)
  static let primaryText = adaptive(light: 0x11110F, dark: 0xF8F8F4)
  static let mutedText = adaptive(light: 0x696962, dark: 0xAAA9A1)
  static let selectedControlForeground = adaptive(light: 0x3324B5, dark: 0xD6D1FF)
  static let cardBorder = adaptive(light: 0xE3E3DE, dark: 0x3B3B37)
  static let ink = Color(red: 0.05, green: 0.05, blue: 0.045)
  static let actionForeground = adaptive(light: 0xFFFFFF, dark: 0x11110F)
  static let ticketViolet = adaptive(light: 0x6252E8, dark: 0x776AEA)
  static let ticketRose = adaptive(light: 0x3325A8, dark: 0x4438AD)
  static let smallCornerRadius: CGFloat = 12
  static let mediumCornerRadius: CGFloat = 18
  static let cornerRadius: CGFloat = 22
  static let largeCornerRadius: CGFloat = 28
  static let controlSize: CGFloat = 56
  static let bottomControlInset: CGFloat = 8
  static let bottomControlHorizontalInset: CGFloat = 14
  static let scrollContentBottomInset: CGFloat = 24

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

enum TunedInMotion {
  static func press(reduceMotion: Bool) -> Animation {
    reduceMotion
      ? .easeOut(duration: 0.08)
      : .easeOut(duration: 0.14)
  }

  static func selection(reduceMotion: Bool) -> Animation {
    reduceMotion
      ? .easeOut(duration: 0.12)
      : .smooth(duration: 0.24, extraBounce: 0)
  }

  static func navigation(reduceMotion: Bool) -> Animation {
    reduceMotion
      ? .easeOut(duration: 0.14)
      : .spring(response: 0.34, dampingFraction: 0.86, blendDuration: 0.08)
  }

  static func feedback(reduceMotion: Bool) -> Animation {
    reduceMotion
      ? .easeOut(duration: 0.12)
      : .smooth(duration: 0.22, extraBounce: 0)
  }

  static func controlSceneTransition(reduceMotion: Bool) -> AnyTransition {
    reduceMotion ? .opacity : .identity
  }

  static func compactIdentityTransition(reduceMotion: Bool) -> AnyTransition {
    reduceMotion
      ? .opacity
      : .move(edge: .top).combined(with: .opacity)
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
  let systemImage: String
  let accessibilityLabel: String
  let accessibilityHint: String
  let action: () -> Void
  @Environment(\.tunedInKeyboardPresentation) private var keyboardPresentation

  init(
    systemImage: String = "plus",
    accessibilityLabel: String = "Log concert",
    accessibilityHint: String = "Opens the new concert form",
    action: @escaping () -> Void
  ) {
    self.systemImage = systemImage
    self.accessibilityLabel = accessibilityLabel
    self.accessibilityHint = accessibilityHint
    self.action = action
  }

  var body: some View {
    if keyboardPresentation.showsPersistentGlass {
      Button(action: action) {
        TunedInFloatingActionLabel(systemImage: systemImage)
      }
      .buttonStyle(.plain)
      .frame(width: TunedInDesign.controlSize, height: TunedInDesign.controlSize)
      .contentShape(.interaction, Circle())
      .accessibilityLabel(accessibilityLabel)
      .accessibilityHint(accessibilityHint)
    }
  }
}

struct TunedInSelectionLens: View {
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
  @Environment(\.colorSchemeContrast) private var colorSchemeContrast

  var body: some View {
    if #available(iOS 26.0, *), !reduceTransparency {
      Capsule()
        .fill(.clear)
        .glassEffect(
          .regular.tint(TunedInDesign.accent.opacity(0.14)),
          in: Capsule()
        )
    } else {
      Capsule()
        .fill(TunedInDesign.accentTint)
        .overlay {
          Capsule()
            .strokeBorder(
              TunedInDesign.accent.opacity(colorSchemeContrast == .increased ? 0.72 : 0.2)
            )
        }
    }
  }
}

struct TunedInPosterButtonStyle: ButtonStyle {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .scaleEffect(configuration.isPressed && !reduceMotion ? 0.985 : 1)
      .opacity(configuration.isPressed ? 0.92 : 1)
      .animation(
        TunedInMotion.press(reduceMotion: reduceMotion),
        value: configuration.isPressed
      )
  }
}

struct TunedInGlassIdentitySurface<Content: View>: View {
  @ViewBuilder let content: Content

  var body: some View {
    content
      .padding(.horizontal, 14)
      .padding(.vertical, 10)
      .modifier(TunedInLiquidGlassIdentitySurface())
  }
}

struct TunedInFloatingActionLabel: View {
  let systemImage: String
  @Environment(\.tunedInKeyboardPresentation) private var keyboardPresentation

  var body: some View {
    if keyboardPresentation.showsPersistentGlass {
      Image(systemName: systemImage)
        .font(.system(size: 20, weight: .bold))
        .foregroundStyle(TunedInDesign.actionForeground)
        .frame(width: TunedInDesign.controlSize, height: TunedInDesign.controlSize)
        .contentShape(.interaction, Circle())
        .modifier(TunedInLiquidGlassActionSurface())
    }
  }
}

struct TunedInGlassIconButton: View {
  enum Style: Equatable {
    case neutral
    case accent
  }

  let systemImage: String
  let accessibilityLabel: String
  var style: Style = .neutral
  let action: () -> Void
  @Environment(\.tunedInKeyboardPresentation) private var keyboardPresentation

  var body: some View {
    if keyboardPresentation.showsPersistentGlass {
      Button(action: action) {
        Image(systemName: systemImage)
          .font(.body.weight(.bold))
          .foregroundStyle(TunedInDesign.primaryText)
          .frame(width: TunedInDesign.controlSize, height: TunedInDesign.controlSize)
          .contentShape(.interaction, Circle())
          .modifier(TunedInLiquidGlassIconSurface(style: style))
      }
      .buttonStyle(.plain)
      .frame(width: TunedInDesign.controlSize, height: TunedInDesign.controlSize)
      .contentShape(.interaction, Circle())
      .accessibilityLabel(accessibilityLabel)
    }
  }
}

struct TunedInGlassTraversalLayout<Leading: View, Center: View, Trailing: View>: View {
  let sideReservation: CGFloat
  let height: CGFloat
  let glassNamespace: Namespace.ID?
  let leading: Leading
  let center: Center
  let trailing: Trailing
  @Namespace private var localGlassNamespace

  init(
    sideReservation: CGFloat = 68,
    height: CGFloat = TunedInDesign.controlSize,
    glassNamespace: Namespace.ID? = nil,
    @ViewBuilder leading: () -> Leading,
    @ViewBuilder center: () -> Center,
    @ViewBuilder trailing: () -> Trailing
  ) {
    self.sideReservation = sideReservation
    self.height = height
    self.glassNamespace = glassNamespace
    self.leading = leading()
    self.center = center()
    self.trailing = trailing()
  }

  var body: some View {
    GeometryReader { proxy in
      if #available(iOS 26.0, *) {
        GlassEffectContainer(spacing: 12) {
          controlLayout(proxy: proxy)
        }
      } else {
        controlLayout(proxy: proxy)
      }
    }
    .frame(height: height)
    .frame(maxWidth: .infinity)
  }

  private var resolvedGlassNamespace: Namespace.ID {
    glassNamespace ?? localGlassNamespace
  }

  private func controlLayout(proxy: GeometryProxy) -> some View {
    ZStack(alignment: .bottom) {
      center
        .frame(maxWidth: max(0, proxy.size.width - (sideReservation * 2)))
        .modifier(
          TunedInGlassEffectIdentity(
            id: "center",
            namespace: resolvedGlassNamespace
          )
        )

      HStack(alignment: .bottom, spacing: 12) {
        leading
          .modifier(
            TunedInGlassEffectIdentity(
              id: "leading",
              namespace: resolvedGlassNamespace
            )
          )
        Spacer(minLength: 12)
        trailing
          .modifier(
            TunedInGlassEffectIdentity(
              id: "trailing",
              namespace: resolvedGlassNamespace
            )
          )
      }
    }
  }
}

private struct TunedInGlassEffectIdentity: ViewModifier {
  let id: String
  let namespace: Namespace.ID
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  func body(content: Content) -> some View {
    if #available(iOS 26.0, *) {
      if reduceMotion {
        content
          .glassEffectID(id, in: namespace)
      } else {
        content
          .glassEffectID(id, in: namespace)
          .glassEffectTransition(.matchedGeometry)
      }
    } else {
      content
    }
  }
}

struct TunedInPersistentControlRegion<Content: View>: View {
  @ViewBuilder let content: Content
  @Environment(\.tunedInKeyboardPresentation) private var keyboardPresentation

  var body: some View {
    if keyboardPresentation.showsPersistentGlass {
      content
    }
  }
}

private struct TunedInLiquidGlassIconSurface: ViewModifier {
  let style: TunedInGlassIconButton.Style
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
  @Environment(\.colorSchemeContrast) private var colorSchemeContrast

  func body(content: Content) -> some View {
    if #available(iOS 26.0, *), !reduceTransparency {
      if style == .accent {
        content.glassEffect(.regular.tint(TunedInDesign.accent.opacity(0.22)).interactive(), in: .circle)
      } else {
        content.glassEffect(.regular.interactive(), in: .circle)
      }
    } else {
      content
        .background {
          if reduceTransparency {
            Circle().fill(style == .accent ? TunedInDesign.accentTint : TunedInDesign.raisedSurface)
          } else {
            Circle().fill(.ultraThinMaterial)
          }
        }
        .background(style == .accent ? TunedInDesign.accent.opacity(0.14) : .clear, in: Circle())
        .overlay {
          Circle().strokeBorder(
            TunedInDesign.cardBorder.opacity(colorSchemeContrast == .increased ? 1 : 0.85)
          )
        }
        .shadow(color: style == .accent ? TunedInDesign.accent.opacity(0.2) : .clear, radius: 10, y: 5)
    }
  }
}

private struct TunedInLiquidGlassActionSurface: ViewModifier {
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
  @Environment(\.colorSchemeContrast) private var colorSchemeContrast

  func body(content: Content) -> some View {
    if #available(iOS 26.0, *), !reduceTransparency {
      content
        .glassEffect(.regular.tint(TunedInDesign.accent.opacity(0.22)).interactive(), in: .circle)
    } else {
      content
        .background {
          if reduceTransparency {
            Circle().fill(TunedInDesign.accent)
          } else {
            Circle().fill(.ultraThinMaterial)
          }
        }
        .background(TunedInDesign.accent.opacity(0.14), in: Circle())
        .overlay {
          Circle()
            .strokeBorder(
              TunedInDesign.cardBorder.opacity(colorSchemeContrast == .increased ? 1 : 0.85)
            )
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
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(18)
    .background(
      TunedInDesign.cardBackground,
      in: RoundedRectangle(cornerRadius: TunedInDesign.cornerRadius, style: .continuous)
    )
    .overlay {
      RoundedRectangle(cornerRadius: TunedInDesign.cornerRadius, style: .continuous)
        .strokeBorder(TunedInDesign.cardBorder.opacity(0.55))
    }
  }
}

struct TunedInGlassSection<Content: View>: View {
  @ViewBuilder let content: Content
  @Environment(\.tunedInKeyboardPresentation) private var keyboardPresentation

  var body: some View {
    content
      .padding(18)
      .modifier(
        TunedInLiquidGlassSectionSurface(
          isGlassEnabled: keyboardPresentation.showsPersistentGlass
        )
      )
  }
}

struct TunedInGlassSearchField: View {
  enum Style: Equatable {
    case standard
    case neutralPopover
  }

  @Binding var text: String
  let prompt: String
  let style: Style
  let onActivate: (() -> Void)?
  @Environment(\.tunedInKeyboardPresentation) private var keyboardPresentation
  @FocusState private var isFocused: Bool

  init(
    text: Binding<String>,
    prompt: String,
    style: Style = .standard,
    onActivate: (() -> Void)? = nil
  ) {
    _text = text
    self.prompt = prompt
    self.style = style
    self.onActivate = onActivate
  }

  var body: some View {
    HStack(spacing: 10) {
      HStack(spacing: 10) {
        Image(systemName: "magnifyingglass")
          .foregroundStyle(TunedInDesign.mutedText)

        TextField(prompt, text: $text, onEditingChanged: { isEditing in
          if isEditing {
            onActivate?()
          }
        })
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled()
          .submitLabel(.search)
          .focused($isFocused)
          .onSubmit { isFocused = false }
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
      .modifier(
        TunedInLiquidGlassSearchSurface(
          style: style,
          isGlassEnabled: keyboardPresentation.showsPersistentGlass
        )
      )

      if isFocused {
        Button("Done") { isFocused = false }
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(TunedInDesign.accent)
          .transition(.opacity)
          .accessibilityHint("Keeps the current search results visible")
      }
    }
  }
}

struct TunedInGlassBottomBar<Content: View>: View {
  @ViewBuilder let content: Content
  @Environment(\.tunedInKeyboardPresentation) private var keyboardPresentation

  var body: some View {
    if keyboardPresentation.showsPersistentGlass {
      content
        .padding(6)
        .modifier(TunedInLiquidGlassBottomBarSurface())
    }
  }
}

struct TunedInSubscreenBackBar: View {
  let title: String
  let action: () -> Void

  var body: some View {
    TunedInGlassTraversalLayout {
      TunedInGlassIconButton(
        systemImage: "chevron.backward",
        accessibilityLabel: "Back to previous screen",
        action: action
      )
    } center: {
      TunedInGlassBottomBar {
        Text(title)
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(TunedInDesign.primaryText)
          .lineLimit(1)
          .frame(minWidth: 112, minHeight: 48, alignment: .center)
          .padding(.horizontal, 14)
      }
    } trailing: {
      EmptyView()
    }
  }
}

struct TunedInSkeletonBlock: View {
  var cornerRadius: CGFloat = 16

  @State private var isHighlighted = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
      .fill(TunedInDesign.accentTint.opacity(isHighlighted ? 0.9 : 0.5))
      .overlay {
        LinearGradient(
          colors: [.clear, TunedInDesign.accent.opacity(0.14), .clear],
          startPoint: .leading,
          endPoint: .trailing
        )
        .offset(x: isHighlighted ? 180 : -180)
        .clipped()
      }
      .onAppear {
        guard !reduceMotion else { return }
        withAnimation(.easeInOut(duration: 1.05).repeatForever(autoreverses: true)) {
          isHighlighted = true
        }
      }
      .accessibilityHidden(true)
  }
}

struct TunedInImagePlaceholder: View {
  var failed = false

  var body: some View {
    ZStack {
      TunedInSkeletonBlock(cornerRadius: 0)
      Image(systemName: failed ? "exclamationmark.triangle.fill" : "photo.on.rectangle.angled")
        .font(.title2.weight(.semibold))
        .foregroundStyle(TunedInDesign.accent.opacity(0.75))
    }
  }
}

private struct TunedInEdgeSwipeBackModifier: ViewModifier {
  let isEnabled: Bool
  let action: () -> Void

  func body(content: Content) -> some View {
    content.simultaneousGesture(
      DragGesture(minimumDistance: 18, coordinateSpace: .global)
        .onEnded { value in
          guard isEnabled,
                value.startLocation.x <= 28,
                value.translation.width >= 72,
                abs(value.translation.height) < abs(value.translation.width) * 0.7
          else { return }
          action()
        }
    )
  }
}

extension View {
  func tunedInEdgeSwipeBack(isEnabled: Bool = true, action: @escaping () -> Void) -> some View {
    modifier(TunedInEdgeSwipeBackModifier(isEnabled: isEnabled, action: action))
  }
}

struct TunedInGlassPopover<Content: View>: View {
  @ViewBuilder let content: Content
  @Environment(\.tunedInKeyboardPresentation) private var keyboardPresentation

  var body: some View {
    content
      .modifier(
        TunedInLiquidGlassPopoverSurface(
          isGlassEnabled: keyboardPresentation.showsPersistentGlass
        )
      )
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
  let isGlassEnabled: Bool

  func body(content: Content) -> some View {
    content
      .background(TunedInDesign.cardBackground, in: sectionShape)
      .overlay {
        sectionShape
          .strokeBorder(TunedInDesign.cardBorder.opacity(isGlassEnabled ? 0.42 : 0.55))
      }
  }

  private var sectionShape: RoundedRectangle {
    RoundedRectangle(cornerRadius: TunedInDesign.cornerRadius, style: .continuous)
  }
}

private struct TunedInLiquidGlassSearchSurface: ViewModifier {
  let style: TunedInGlassSearchField.Style
  let isGlassEnabled: Bool
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
  @Environment(\.colorSchemeContrast) private var colorSchemeContrast

  func body(content: Content) -> some View {
    content
      .background { surfaceBackground }
      .overlay { surfaceBorder }
  }

  @ViewBuilder
  private var surfaceBackground: some View {
    if #available(iOS 26.0, *) {
      ZStack {
        Capsule().fill(effectiveGlassEnabled ? .clear : TunedInDesign.raisedSurface)
        Capsule()
          .fill(.clear)
          .glassEffect(.regular.tint(tint).interactive(), in: Capsule())
          .opacity(effectiveGlassEnabled ? 1 : 0)
      }
      .allowsHitTesting(false)
    } else {
      fallbackBackground
    }
  }

  @ViewBuilder
  private var surfaceBorder: some View {
    if #available(iOS 26.0, *) {
      if !effectiveGlassEnabled {
        Capsule().strokeBorder(TunedInDesign.cardBorder.opacity(borderOpacity))
      }
    } else {
      Capsule().strokeBorder(
        TunedInDesign.cardBorder.opacity(borderOpacity)
      )
    }
  }

  @ViewBuilder
  private var fallbackBackground: some View {
    if effectiveGlassEnabled {
      ZStack {
        Capsule().fill(backgroundTint)
        Capsule().fill(.ultraThinMaterial)
      }
    } else {
      Capsule().fill(TunedInDesign.raisedSurface)
    }
  }

  private var tint: Color {
    style == .neutralPopover ? .white.opacity(0.06) : .clear
  }

  private var backgroundTint: Color {
    style == .neutralPopover ? .white.opacity(0.06) : TunedInDesign.cardBackground.opacity(0.84)
  }

  private var effectiveGlassEnabled: Bool {
    isGlassEnabled && !reduceTransparency
  }

  private var borderOpacity: Double {
    colorSchemeContrast == .increased ? 1 : (effectiveGlassEnabled ? 0.85 : 0.72)
  }
}

private struct TunedInLiquidGlassPopoverSurface: ViewModifier {
  let isGlassEnabled: Bool
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
  @Environment(\.colorSchemeContrast) private var colorSchemeContrast

  func body(content: Content) -> some View {
    content
      .background { surfaceBackground }
      .overlay { surfaceBorder }
  }

  private var popoverShape: RoundedRectangle {
    RoundedRectangle(cornerRadius: TunedInDesign.cornerRadius, style: .continuous)
  }

  @ViewBuilder
  private var surfaceBackground: some View {
    if #available(iOS 26.0, *) {
      ZStack {
        popoverShape.fill(effectiveGlassEnabled ? .clear : TunedInDesign.cardBackground)
        popoverShape
          .fill(.clear)
          .glassEffect(.regular, in: popoverShape)
          .opacity(effectiveGlassEnabled ? 1 : 0)
      }
      .allowsHitTesting(false)
    } else {
      fallbackBackground
    }
  }

  @ViewBuilder
  private var fallbackBackground: some View {
    if effectiveGlassEnabled {
      ZStack {
        popoverShape.fill(.white.opacity(0.05))
        popoverShape.fill(.ultraThinMaterial)
      }
    } else {
      popoverShape.fill(TunedInDesign.cardBackground)
    }
  }

  @ViewBuilder
  private var surfaceBorder: some View {
    if !effectiveGlassEnabled || colorSchemeContrast == .increased {
      popoverShape.strokeBorder(
        TunedInDesign.cardBorder.opacity(colorSchemeContrast == .increased ? 1 : 0.72)
      )
    }
  }

  private var effectiveGlassEnabled: Bool {
    isGlassEnabled && !reduceTransparency
  }
}

private struct TunedInLiquidGlassBottomBarSurface: ViewModifier {
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
  @Environment(\.colorSchemeContrast) private var colorSchemeContrast

  func body(content: Content) -> some View {
    if #available(iOS 26.0, *), !reduceTransparency {
      content
        .glassEffect(.regular, in: Capsule())
    } else {
      content
        .background {
          if reduceTransparency {
            Capsule().fill(TunedInDesign.cardBackground)
          } else {
            Capsule().fill(.ultraThinMaterial)
          }
        }
        .background(TunedInDesign.cardBackground.opacity(0.86), in: Capsule())
        .overlay {
          Capsule()
            .strokeBorder(
              TunedInDesign.cardBorder.opacity(colorSchemeContrast == .increased ? 1 : 0.85)
            )
        }
    }
  }
}

private struct TunedInLiquidGlassIdentitySurface: ViewModifier {
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
  @Environment(\.colorSchemeContrast) private var colorSchemeContrast

  func body(content: Content) -> some View {
    if #available(iOS 26.0, *), !reduceTransparency {
      content
        .glassEffect(.regular, in: Capsule())
    } else {
      content
        .background {
          if reduceTransparency {
            Capsule().fill(TunedInDesign.cardBackground)
          } else {
            Capsule().fill(.ultraThinMaterial)
          }
        }
        .background(TunedInDesign.cardBackground.opacity(0.9), in: Capsule())
        .overlay {
          Capsule()
            .strokeBorder(
              TunedInDesign.cardBorder.opacity(colorSchemeContrast == .increased ? 1 : 0.85)
            )
        }
    }
  }
}

private struct TunedInMatchedNavigationSourceModifier<SourceID: Hashable>: ViewModifier {
  let id: SourceID
  let namespace: Namespace.ID
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  func body(content: Content) -> some View {
    if #available(iOS 18.0, *), !reduceMotion {
      content
        .matchedTransitionSource(id: id, in: namespace)
    } else {
      content
    }
  }
}

private struct TunedInNavigationZoomModifier<SourceID: Hashable>: ViewModifier {
  let sourceID: SourceID
  let namespace: Namespace.ID
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  func body(content: Content) -> some View {
    if #available(iOS 18.0, *), !reduceMotion {
      content
        .navigationTransition(.zoom(sourceID: sourceID, in: namespace))
    } else {
      content
    }
  }
}

extension View {
  func tunedInMatchedNavigationSource<SourceID: Hashable>(
    id: SourceID,
    in namespace: Namespace.ID
  ) -> some View {
    modifier(TunedInMatchedNavigationSourceModifier(id: id, namespace: namespace))
  }

  func tunedInNavigationZoom<SourceID: Hashable>(
    sourceID: SourceID,
    in namespace: Namespace.ID
  ) -> some View {
    modifier(TunedInNavigationZoomModifier(sourceID: sourceID, namespace: namespace))
  }

  func tunedInSelectionFeedback<Trigger: Equatable>(trigger: Trigger) -> some View {
    sensoryFeedback(.selection, trigger: trigger)
  }

}
