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
}

private struct TunedInKeyboardPresentationKey: EnvironmentKey {
  static let defaultValue = TunedInKeyboardPresentation.hidden
}

@MainActor
@Observable
final class TunedInKeyboardAccessoryCoordinator {
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

private struct TunedInKeyboardAccessoryCoordinatorKey: EnvironmentKey {
  static let defaultValue: TunedInKeyboardAccessoryCoordinator? = nil
}

extension EnvironmentValues {
  var tunedInKeyboardPresentation: TunedInKeyboardPresentation {
    get { self[TunedInKeyboardPresentationKey.self] }
    set { self[TunedInKeyboardPresentationKey.self] = newValue }
  }

  var tunedInKeyboardAccessoryCoordinator: TunedInKeyboardAccessoryCoordinator? {
    get { self[TunedInKeyboardAccessoryCoordinatorKey.self] }
    set { self[TunedInKeyboardAccessoryCoordinatorKey.self] = newValue }
  }
}

private struct TunedInKeyboardPresentationModifier: ViewModifier {
  @Environment(\.tunedInKeyboardAccessoryCoordinator) private var inheritedCoordinator
  @State private var presentation = TunedInKeyboardPresentation.hidden
  @State private var localCoordinator = TunedInKeyboardAccessoryCoordinator()
  @State private var accessoryOwner = UUID()

  func body(content: Content) -> some View {
    content
      .scrollDismissesKeyboard(.interactively)
      .environment(\.tunedInKeyboardPresentation, presentation)
      .environment(\.tunedInKeyboardAccessoryCoordinator, coordinator)
      .onAppear { coordinator.register(accessoryOwner) }
      .onDisappear { coordinator.unregister(accessoryOwner) }
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

  private var coordinator: TunedInKeyboardAccessoryCoordinator {
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
  func tunedInKeyboardManaged() -> some View {
    modifier(TunedInKeyboardPresentationModifier())
  }
}
