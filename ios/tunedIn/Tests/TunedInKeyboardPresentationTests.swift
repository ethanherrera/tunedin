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
}
