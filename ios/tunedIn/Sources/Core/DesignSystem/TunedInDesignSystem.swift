import Combine
import Observation
import SwiftUI
import UIKit

enum TunedInKeyboardPresentation: Equatable {
  case hidden
  case presented

  func update(to candidate: Self) -> Self? {
    candidate == self ? nil : candidate
  }

  static func resolved(endFrame: CGRect, screenBounds: CGRect) -> Self {
    endFrame.minY < screenBounds.maxY && endFrame.intersects(screenBounds)
      ? .presented
      : .hidden
  }

  static var immediateTransaction: Transaction {
    var transaction = Transaction(animation: nil)
    transaction.disablesAnimations = true
    return transaction
  }

  var showsPersistentGlass: Bool {
    self == .hidden
  }

  var showsDismissControl: Bool {
    self == .presented
  }
}

private struct TunedInKeyboardPresentationKey: EnvironmentKey {
  static let defaultValue = TunedInKeyboardPresentation.hidden
}

@MainActor
@Observable
final class TunedInKeyboardDismissControlCoordinator {
  private var owners: [UUID] = []

  var registeredOwnerCount: Int {
    owners.count
  }

  func register(_ owner: UUID) {
    owners.removeAll { $0 == owner }
    owners.append(owner)
  }

  func unregister(_ owner: UUID) {
    owners.removeAll { $0 == owner }
  }

  func isActive(_ owner: UUID) -> Bool {
    owners.last == owner
  }
}

private struct TunedInKeyboardDismissCoordinatorKey: EnvironmentKey {
  static let defaultValue: TunedInKeyboardDismissControlCoordinator? = nil
}

extension EnvironmentValues {
  var tunedInKeyboardPresentation: TunedInKeyboardPresentation {
    get { self[TunedInKeyboardPresentationKey.self] }
    set { self[TunedInKeyboardPresentationKey.self] = newValue }
  }

  var tunedInKeyboardDismissControlCoordinator: TunedInKeyboardDismissControlCoordinator? {
    get { self[TunedInKeyboardDismissCoordinatorKey.self] }
    set { self[TunedInKeyboardDismissCoordinatorKey.self] = newValue }
  }
}

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
  static let bottomControlInset: CGFloat = 44
  static let bottomControlHorizontalInset: CGFloat = 16
  static let scrollContentBottomInset: CGFloat = 88
  static let keyboardDismissControlClearance: CGFloat = 76

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
      .frame(width: 60, height: 60)
      .contentShape(.interaction, Circle())
      .accessibilityLabel(accessibilityLabel)
      .accessibilityHint(accessibilityHint)
    }
  }
}

struct TunedInFloatingActionLabel: View {
  let systemImage: String
  @Environment(\.tunedInKeyboardPresentation) private var keyboardPresentation

  var body: some View {
    if keyboardPresentation.showsPersistentGlass {
      Image(systemName: systemImage)
        .font(.system(size: 22, weight: .bold))
        .foregroundStyle(TunedInDesign.actionForeground)
        .frame(width: 60, height: 60)
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
          .frame(width: 60, height: 60)
          .contentShape(.interaction, Circle())
          .modifier(TunedInLiquidGlassIconSurface(style: style))
      }
      .buttonStyle(.plain)
      .frame(width: 60, height: 60)
      .contentShape(.interaction, Circle())
      .accessibilityLabel(accessibilityLabel)
    }
  }
}

struct TunedInGlassTraversalLayout<Leading: View, Center: View, Trailing: View>: View {
  var sideReservation: CGFloat = 74
  var height: CGFloat = 60
  @ViewBuilder let leading: Leading
  @ViewBuilder let center: Center
  @ViewBuilder let trailing: Trailing

  var body: some View {
    GeometryReader { proxy in
      ZStack(alignment: .bottom) {
        center
          .frame(maxWidth: max(0, proxy.size.width - (sideReservation * 2)))

        HStack(alignment: .bottom, spacing: 12) {
          leading
          Spacer(minLength: 12)
          trailing
        }
      }
    }
    .frame(height: height)
    .frame(maxWidth: .infinity)
    .dynamicTypeSize(DynamicTypeSize.xSmall ... DynamicTypeSize.xxxLarge)
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

  func body(content: Content) -> some View {
    if #available(iOS 26.0, *) {
      if style == .accent {
        content.glassEffect(.regular.tint(TunedInDesign.accent.opacity(0.28)).interactive(), in: .circle)
      } else {
        content.glassEffect(.regular.interactive(), in: .circle)
      }
    } else {
      content
        .background(.ultraThinMaterial, in: Circle())
        .background(style == .accent ? TunedInDesign.accent.opacity(0.18) : .clear, in: Circle())
        .overlay { Circle().strokeBorder(.white.opacity(0.42)) }
        .shadow(color: style == .accent ? TunedInDesign.accent.opacity(0.2) : .clear, radius: 10, y: 5)
    }
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
    .frame(maxWidth: .infinity, alignment: .leading)
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
  @Environment(\.tunedInKeyboardPresentation) private var keyboardPresentation

  var body: some View {
    content
      .padding(16)
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
  @Environment(\.tunedInKeyboardPresentation) private var keyboardPresentation

  init(text: Binding<String>, prompt: String, style: Style = .standard) {
    _text = text
    self.prompt = prompt
    self.style = style
  }

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
    .modifier(
      TunedInLiquidGlassSearchSurface(
        style: style,
        isGlassEnabled: keyboardPresentation.showsPersistentGlass
      )
    )
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
      TunedInGlassIconButton(systemImage: "chevron.backward", accessibilityLabel: "Back to previous screen", action: action)
    } center: {
      TunedInGlassBottomBar {
        Text(title)
          .font(.subheadline.weight(.bold))
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
      .background { surfaceBackground }
      .overlay { surfaceBorder }
  }

  private var sectionShape: RoundedRectangle {
    RoundedRectangle(cornerRadius: TunedInDesign.cornerRadius, style: .continuous)
  }

  @ViewBuilder
  private var surfaceBackground: some View {
    if #available(iOS 26.0, *) {
      ZStack {
        sectionShape.fill(isGlassEnabled ? .clear : TunedInDesign.cardBackground)
        sectionShape
          .fill(.clear)
          .glassEffect(
            .regular.tint(TunedInDesign.accent.opacity(0.08)).interactive(),
            in: sectionShape
          )
          .opacity(isGlassEnabled ? 1 : 0)
      }
      .allowsHitTesting(false)
    } else {
      fallbackBackground
    }
  }

  @ViewBuilder
  private var surfaceBorder: some View {
    if #available(iOS 26.0, *) {
      if !isGlassEnabled {
        sectionShape.strokeBorder(TunedInDesign.cardBorder.opacity(0.72))
      }
    } else {
      sectionShape.strokeBorder(
        isGlassEnabled ? .white.opacity(0.46) : TunedInDesign.cardBorder.opacity(0.72)
      )
    }
  }

  @ViewBuilder
  private var fallbackBackground: some View {
    if isGlassEnabled {
      ZStack {
        sectionShape.fill(TunedInDesign.cardBackground.opacity(0.72))
        sectionShape.fill(.thinMaterial)
      }
    } else {
      sectionShape.fill(TunedInDesign.cardBackground)
    }
  }
}

private struct TunedInLiquidGlassSearchSurface: ViewModifier {
  let style: TunedInGlassSearchField.Style
  let isGlassEnabled: Bool

  func body(content: Content) -> some View {
    content
      .background { surfaceBackground }
      .overlay { surfaceBorder }
  }

  @ViewBuilder
  private var surfaceBackground: some View {
    if #available(iOS 26.0, *) {
      ZStack {
        Capsule().fill(isGlassEnabled ? .clear : TunedInDesign.raisedSurface)
        Capsule()
          .fill(.clear)
          .glassEffect(.regular.tint(tint).interactive(), in: Capsule())
          .opacity(isGlassEnabled ? 1 : 0)
      }
      .allowsHitTesting(false)
    } else {
      fallbackBackground
    }
  }

  @ViewBuilder
  private var surfaceBorder: some View {
    if #available(iOS 26.0, *) {
      if !isGlassEnabled {
        Capsule().strokeBorder(TunedInDesign.cardBorder.opacity(0.72))
      }
    } else {
      Capsule().strokeBorder(
        isGlassEnabled
          ? TunedInDesign.cardBorder.opacity(0.85)
          : TunedInDesign.cardBorder.opacity(0.72)
      )
    }
  }

  @ViewBuilder
  private var fallbackBackground: some View {
    if isGlassEnabled {
      ZStack {
        Capsule().fill(backgroundTint)
        Capsule().fill(.ultraThinMaterial)
      }
    } else {
      Capsule().fill(TunedInDesign.raisedSurface)
    }
  }

  private var tint: Color {
    style == .neutralPopover ? .white.opacity(0.1) : TunedInDesign.accent.opacity(0.05)
  }

  private var backgroundTint: Color {
    style == .neutralPopover ? .white.opacity(0.08) : TunedInDesign.cardBackground.opacity(0.8)
  }
}

private struct TunedInLiquidGlassPopoverSurface: ViewModifier {
  let isGlassEnabled: Bool

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
        popoverShape.fill(isGlassEnabled ? .clear : TunedInDesign.cardBackground)
        popoverShape
          .fill(.clear)
          .glassEffect(.regular.tint(.white.opacity(0.08)).interactive(), in: popoverShape)
          .opacity(isGlassEnabled ? 1 : 0)
      }
      .allowsHitTesting(false)
    } else {
      fallbackBackground
    }
  }

  @ViewBuilder
  private var fallbackBackground: some View {
    if isGlassEnabled {
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
    if #unavailable(iOS 26.0), isGlassEnabled {
      popoverShape.strokeBorder(.white.opacity(0.34))
    }
  }
}

private struct TunedInLiquidGlassBottomBarSurface: ViewModifier {
  func body(content: Content) -> some View {
    if #available(iOS 26.0, *) {
      content
        .glassEffect(
          .regular.tint(TunedInDesign.accent.opacity(0.06)).interactive(),
          in: Capsule()
        )
    } else {
      content
        .background(.ultraThinMaterial, in: Capsule())
        .background(TunedInDesign.cardBackground.opacity(0.86), in: Capsule())
        .overlay {
          Capsule()
            .strokeBorder(TunedInDesign.cardBorder.opacity(0.85))
        }
    }
  }
}

private struct TunedInKeyboardDismissControl: View {
  var body: some View {
    Button {
      UIApplication.shared.sendAction(
        #selector(UIResponder.resignFirstResponder),
        to: nil,
        from: nil,
        for: nil
      )
    } label: {
      Image(systemName: "xmark")
        .font(.body.weight(.bold))
        .foregroundStyle(TunedInDesign.primaryText)
        .frame(width: 60, height: 60)
        .contentShape(Circle())
        .modifier(TunedInLiquidGlassIconSurface(style: .neutral))
    }
    .buttonStyle(.plain)
    .accessibilityLabel("Dismiss keyboard")
  }
}

private struct TunedInKeyboardPresentationModifier: ViewModifier {
  let showsDismissControl: Bool
  @Environment(\.tunedInKeyboardDismissControlCoordinator) private var inheritedCoordinator
  @State private var presentation = TunedInKeyboardPresentation.hidden
  @State private var localCoordinator = TunedInKeyboardDismissControlCoordinator()
  @State private var dismissControlOwner = UUID()

  func body(content: Content) -> some View {
    content
      .environment(\.tunedInKeyboardPresentation, presentation)
      .environment(\.tunedInKeyboardDismissControlCoordinator, coordinator)
      .safeAreaInset(edge: .bottom, spacing: 0) {
        if presentation.showsDismissControl
          && showsDismissControl
          && coordinator.isActive(dismissControlOwner) {
          HStack {
            Spacer(minLength: 0)
            TunedInKeyboardDismissControl()
          }
          .padding(.horizontal, TunedInDesign.bottomControlHorizontalInset)
          .padding(.vertical, 8)
        }
      }
      .onAppear {
        guard showsDismissControl else { return }
        coordinator.register(dismissControlOwner)
      }
      .onDisappear {
        guard showsDismissControl else { return }
        coordinator.unregister(dismissControlOwner)
      }
      .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
        setPresentation(.presented)
      }
      .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidHideNotification)) { _ in
        setPresentation(.hidden)
      }
      .onReceive(
        NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)
      ) { notification in
        guard presentation(for: notification) == .presented else { return }
        setPresentation(.presented)
      }
  }

  private var coordinator: TunedInKeyboardDismissControlCoordinator {
    inheritedCoordinator ?? localCoordinator
  }

  private func presentation(for notification: Notification) -> TunedInKeyboardPresentation {
    guard
      let endFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect,
      let screenBounds = UIApplication.shared.connectedScenes
        .compactMap({ ($0 as? UIWindowScene)?.screen.bounds })
        .first
    else {
      return presentation
    }

    return TunedInKeyboardPresentation.resolved(
      endFrame: endFrame,
      screenBounds: screenBounds
    )
  }

  private func setPresentation(_ newPresentation: TunedInKeyboardPresentation) {
    guard let updatedPresentation = presentation.update(to: newPresentation) else { return }

    withTransaction(TunedInKeyboardPresentation.immediateTransaction) {
      presentation = updatedPresentation
    }
  }
}

extension View {
  func tunedInKeyboardManaged(showsDismissControl: Bool = true) -> some View {
    modifier(TunedInKeyboardPresentationModifier(showsDismissControl: showsDismissControl))
  }
}
