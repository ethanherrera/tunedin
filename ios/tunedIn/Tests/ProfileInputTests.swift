import Testing
@testable import tunedIn

struct ProfileInputTests {
  @Test
  func usernameNormalizesBeforeValidation() {
    #expect(ProfileInput.normalizedUsername("  River_SIDE  ") == "river_side")
    #expect(ProfileInput.isUsernameValid("river_side"))
    #expect(!ProfileInput.isUsernameValid("river-side"))
    #expect(!ProfileInput.isUsernameValid("ab"))
  }

  @Test
  func peopleSearchAcceptsAUsernameWithLeadingAtSign() {
    #expect(ProfileInput.normalizedSearchQuery("  @River_SIDE  ") == "river_side")
    #expect(ProfileInput.normalizedSearchQuery("River Side") == "river side")
  }

  @Test
  func displayNameNormalizesWhitespaceAndRejectsControlCharacters() {
    #expect(ProfileInput.normalizedDisplayName("  River   Side  ") == "River Side")
    #expect(ProfileInput.isDisplayNameValid("River Side"))
    #expect(!ProfileInput.isDisplayNameValid("River\nSide"))
  }
}
