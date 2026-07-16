import Combine
import SwiftUI
import Testing
import UIKit
@testable import tunedIn

@Suite(.serialized)
@MainActor
struct TunedInGlassSearchFieldFocusTests {
  @Test
  func keyboardPresentationChangePreservesFocusedSearchField() async throws {
    try await verifyFocusPersistence(wrappedInPopover: false)
  }

  @Test
  func keyboardPresentationChangePreservesFocusedSearchFieldInsidePopover() async throws {
    try await verifyFocusPersistence(wrappedInPopover: true)
  }

  @Test
  func nestedKeyboardManagersRegisterAndUnregisterWithSharedAccessoryCoordinator() async {
    let model = NestedKeyboardManagerHarness()
    let coordinator = TunedInKeyboardAccessoryCoordinator()
    let host = UIHostingController(
      rootView: NestedKeyboardManagerHarnessView(model: model)
        .environment(\.tunedInKeyboardAccessoryCoordinator, coordinator)
    )
    let previousKeyWindow = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .flatMap(\.windows)
      .first(where: \.isKeyWindow)
    let window = makeWindow(rootViewController: host)
    defer {
      window.isHidden = true
      previousKeyWindow?.makeKey()
    }

    window.makeKeyAndVisible()
    host.view.setNeedsLayout()
    host.view.layoutIfNeeded()
    await settleViewUpdates()
    #expect(await registeredOwnerCount(1, in: coordinator) == 1)

    model.showsInnerManager = true
    #expect(await registeredOwnerCount(2, in: coordinator) == 2)

    model.showsInnerManager = false
    #expect(await registeredOwnerCount(1, in: coordinator) == 1)
  }

  private func verifyFocusPersistence(wrappedInPopover: Bool) async throws {
    let model = SearchFocusHarness()
    let host = UIHostingController(
      rootView: SearchFocusHarnessView(
        model: model,
        wrappedInPopover: wrappedInPopover
      )
    )
    let previousKeyWindow = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .flatMap(\.windows)
      .first(where: \.isKeyWindow)
    let window = makeWindow(rootViewController: host)
    defer {
      window.endEditing(true)
      window.isHidden = true
      previousKeyWindow?.makeKey()
    }

    window.makeKeyAndVisible()
    host.view.setNeedsLayout()
    host.view.layoutIfNeeded()
    await settleViewUpdates()

    let originalField = try #require(host.view.descendant(of: UITextField.self))
    #expect(originalField.becomeFirstResponder())
    await settleViewUpdates()
    #expect(originalField.isFirstResponder)

    model.presentation = .presented
    host.view.setNeedsLayout()
    host.view.layoutIfNeeded()
    await settleViewUpdates()

    let updatedField = try #require(host.view.descendant(of: UITextField.self))
    #expect(updatedField === originalField)
    #expect(updatedField.isFirstResponder)

    updatedField.insertText("mitski")
    await settleViewUpdates()
    #expect(model.text == "mitski")
  }

  private func makeWindow(rootViewController: UIViewController) -> UIWindow {
    let scene = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .first
    let window = scene.map(UIWindow.init(windowScene:)) ?? UIWindow(frame: UIScreen.main.bounds)
    window.frame = scene?.screen.bounds ?? UIScreen.main.bounds
    window.rootViewController = rootViewController
    return window
  }

  private func settleViewUpdates() async {
    await Task.yield()
    await Task.yield()
  }

  private func registeredOwnerCount(
    _ expectedCount: Int,
    in coordinator: TunedInKeyboardAccessoryCoordinator
  ) async -> Int {
    for _ in 0..<50 {
      let count = coordinator.registeredOwnerCount
      guard count != expectedCount else { return count }
      try? await Task.sleep(for: .milliseconds(20))
    }

    return coordinator.registeredOwnerCount
  }
}

@MainActor
private final class SearchFocusHarness: ObservableObject {
  @Published var text = ""
  @Published var presentation = TunedInKeyboardPresentation.hidden
}

@MainActor
private final class NestedKeyboardManagerHarness: ObservableObject {
  @Published var showsInnerManager = false
}

private struct NestedKeyboardManagerHarnessView: View {
  @ObservedObject var model: NestedKeyboardManagerHarness

  var body: some View {
    VStack {
      Text("Outer keyboard manager")

      if model.showsInnerManager {
        Color.clear
          .frame(height: 100)
          .tunedInKeyboardManaged()
      }
    }
    .frame(width: 390, height: 300)
    .tunedInKeyboardManaged()
  }
}

private struct SearchFocusHarnessView: View {
  @ObservedObject var model: SearchFocusHarness
  let wrappedInPopover: Bool

  var body: some View {
    Group {
      if wrappedInPopover {
        TunedInGlassPopover {
          searchField
        }
      } else {
        searchField
      }
    }
    .padding(20)
    .frame(width: 390, height: 300, alignment: .top)
    .environment(\.tunedInKeyboardPresentation, model.presentation)
  }

  private var searchField: some View {
    TunedInGlassSearchField(text: $model.text, prompt: "Search")
  }
}

private extension UIView {
  func descendant<View: UIView>(of type: View.Type) -> View? {
    if let view = self as? View {
      return view
    }

    for subview in subviews {
      if let match = subview.descendant(of: type) {
        return match
      }
    }

    return nil
  }
}
