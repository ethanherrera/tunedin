import Foundation
import Testing
@testable import tunedIn

struct AppConfigurationTests {
  @Test
  func stagingUsesItsOwnCallbackAndSessionNamespace() throws {
    let configuration = try AppConfiguration.load(configuration: [
      "TUNEDIN_SUPABASE_URL": "https://staging-project.supabase.co",
      "TUNEDIN_SUPABASE_PUBLISHABLE_KEY": "staging-publishable-key",
      "TUNEDIN_APP_ENVIRONMENT": "Staging",
      "TUNEDIN_AUTH_CALLBACK_SCHEME": "com.ethanherrera.tunedin.staging",
      "TUNEDIN_USE_LOCAL_AUTH_STORAGE": "NO"
    ])

    #expect(configuration.environment == .staging)
    #expect(configuration.authCallbackURL.absoluteString == "com.ethanherrera.tunedin.staging://auth-callback")
    #expect(configuration.authSessionStorageKey == "com.ethanherrera.tunedin.staging.auth.session")
    #expect(configuration.authEmailDeliveryMode == .oneTimeCode)
  }

  @Test
  func rejectsMalformedCallbackSchemes() {
    #expect(throws: AppConfigurationError.self) {
      try AppConfiguration.load(configuration: [
        "TUNEDIN_SUPABASE_URL": "https://staging-project.supabase.co",
        "TUNEDIN_SUPABASE_PUBLISHABLE_KEY": "staging-publishable-key",
        "TUNEDIN_APP_ENVIRONMENT": "Staging",
        "TUNEDIN_AUTH_CALLBACK_SCHEME": "https://wrong.example.com/callback",
        "TUNEDIN_USE_LOCAL_AUTH_STORAGE": "NO"
      ])
    }
  }
}
