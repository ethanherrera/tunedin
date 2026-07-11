import Testing
@testable import tunedIn

struct AppFoundationTests {
  @Test
  func launchCopyIsPresent() {
    #expect(AppFoundation.title == "tunedIn")
    #expect(!AppFoundation.message.isEmpty)
  }
}
