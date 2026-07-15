import CoreGraphics
import Foundation
import Testing
@testable import tunedIn

struct TunedInKeyboardPresentationTests {
  @Test
  func hiddenKeyboardKeepsPersistentGlassAvailable() {
    let presentation = TunedInKeyboardPresentation.hidden

    #expect(presentation.showsPersistentGlass)
    #expect(!presentation.showsDismissControl)
  }

  @Test
  func presentedKeyboardExchangesPersistentGlassForDismissControl() {
    let presentation = TunedInKeyboardPresentation.presented

    #expect(!presentation.showsPersistentGlass)
    #expect(presentation.showsDismissControl)
  }

  @Test
  func repeatedPresentationUpdatesAreIgnored() {
    #expect(TunedInKeyboardPresentation.hidden.update(to: .hidden) == nil)
    #expect(TunedInKeyboardPresentation.presented.update(to: .presented) == nil)
    #expect(TunedInKeyboardPresentation.hidden.update(to: .presented) == .presented)
    #expect(TunedInKeyboardPresentation.presented.update(to: .hidden) == .hidden)
  }

  @Test
  func presentationUpdatesDisableAnimation() {
    let transaction = TunedInKeyboardPresentation.immediateTransaction

    #expect(transaction.animation == nil)
    #expect(transaction.disablesAnimations)
  }

  @Test
  func intersectingKeyboardFrameIsPresented() {
    let screenBounds = CGRect(x: 0, y: 0, width: 390, height: 844)
    let keyboardFrame = CGRect(x: 0, y: 504, width: 390, height: 340)

    #expect(
      TunedInKeyboardPresentation.resolved(
        endFrame: keyboardFrame,
        screenBounds: screenBounds
      ) == .presented
    )
  }

  @Test
  func offscreenKeyboardFrameIsHidden() {
    let screenBounds = CGRect(x: 0, y: 0, width: 390, height: 844)
    let keyboardFrame = CGRect(x: 0, y: 844, width: 390, height: 340)

    #expect(
      TunedInKeyboardPresentation.resolved(
        endFrame: keyboardFrame,
        screenBounds: screenBounds
      ) == .hidden
    )
  }

  @Test
  @MainActor
  func nestedDismissOwnershipKeepsOneActiveOwnerAndRestoresOuterOwner() {
    let coordinator = TunedInKeyboardDismissControlCoordinator()
    let outerOwner = UUID()
    let innerOwner = UUID()

    coordinator.register(outerOwner)
    #expect(coordinator.isActive(outerOwner))

    coordinator.register(innerOwner)
    #expect(!coordinator.isActive(outerOwner))
    #expect(coordinator.isActive(innerOwner))

    coordinator.register(innerOwner)
    #expect(!coordinator.isActive(outerOwner))
    #expect(coordinator.isActive(innerOwner))

    coordinator.unregister(innerOwner)
    #expect(coordinator.isActive(outerOwner))
    #expect(!coordinator.isActive(innerOwner))
  }
}
