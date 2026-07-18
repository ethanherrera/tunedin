import SwiftUI
import Testing
@testable import tunedIn

struct TunedInAppearanceTests {
  @Test
  func usesExpectedColorSchemeChoices() {
    #expect(TunedInAppearance.defaultAppearance == .light)
    #expect(TunedInAppearance.system.colorScheme == nil)
    #expect(TunedInAppearance.light.colorScheme == .light)
    #expect(TunedInAppearance.dark.colorScheme == .dark)
  }
}
