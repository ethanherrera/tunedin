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
      "TUNEDIN_AUTH_EXPERIENCE": "NativeSocial",
      "TUNEDIN_AUTH_CALLBACK_SCHEME": "com.ethanherrera.tunedin.staging",
      "GIDClientID": "staging-ios.apps.googleusercontent.com",
      "GIDServerClientID": "staging-server.apps.googleusercontent.com",
      "TUNEDIN_USE_LOCAL_AUTH_STORAGE": "NO",
      "TUNEDIN_POSTHOG_PROJECT_TOKEN": "phc_staging-token",
      "TUNEDIN_POSTHOG_PROJECT_ID": "507318",
      "TUNEDIN_POSTHOG_HOST": "https://us.i.posthog.com",
      "CFBundleShortVersionString": "0.1.0",
      "CFBundleVersion": "42",
      "TUNEDIN_GIT_SHA": "0123456789abcdef"
    ])

    #expect(configuration.environment == .staging)
    #expect(configuration.authCallbackURL.absoluteString == "com.ethanherrera.tunedin.staging://auth-callback")
    #expect(configuration.authSessionStorageKey == "com.ethanherrera.tunedin.staging.auth.session")
    #expect(
      configuration.nativeSocialAuthConfiguration == NativeSocialAuthConfiguration(
        googleIOSClientID: "staging-ios.apps.googleusercontent.com",
        googleServerClientID: "staging-server.apps.googleusercontent.com"
      )
    )
    #expect(
      try configuration.telemetry == .postHog(
        PostHogProjectConfiguration(
          projectToken: "phc_staging-token",
          projectID: "507318",
          host: #require(URL(string: "https://us.i.posthog.com"))
        )
      )
    )
    #expect(configuration.release.build == "42")
  }

  @Test
  func developmentAndLocalNeverConfigurePostHog() throws {
    for usesLocalStorage in ["NO", "YES"] {
      let configuration = try AppConfiguration.load(configuration: [
        "TUNEDIN_SUPABASE_URL": usesLocalStorage == "YES"
          ? "http://127.0.0.1:54321"
          : "https://development-project.supabase.co",
        "TUNEDIN_SUPABASE_PUBLISHABLE_KEY": "development-publishable-key",
        "TUNEDIN_APP_ENVIRONMENT": "Development",
        "TUNEDIN_AUTH_EXPERIENCE": "Email",
        "TUNEDIN_AUTH_CALLBACK_SCHEME": "com.ethanherrera.tunedin",
        "TUNEDIN_USE_LOCAL_AUTH_STORAGE": usesLocalStorage,
        "TUNEDIN_POSTHOG_PROJECT_TOKEN": "must-be-ignored",
        "TUNEDIN_POSTHOG_PROJECT_ID": "507318",
        "TUNEDIN_POSTHOG_HOST": "https://us.i.posthog.com"
      ])

      #expect(configuration.telemetry == .recording)
    }
  }

  @Test
  func stagingRejectsTheWrongPostHogProject() {
    #expect(throws: AppConfigurationError.self) {
      try AppConfiguration.load(configuration: [
        "TUNEDIN_SUPABASE_URL": "https://staging-project.supabase.co",
        "TUNEDIN_SUPABASE_PUBLISHABLE_KEY": "staging-publishable-key",
        "TUNEDIN_APP_ENVIRONMENT": "Staging",
        "TUNEDIN_AUTH_EXPERIENCE": "NativeSocial",
        "TUNEDIN_AUTH_CALLBACK_SCHEME": "com.ethanherrera.tunedin.staging",
        "GIDClientID": "staging-ios.apps.googleusercontent.com",
        "GIDServerClientID": "staging-server.apps.googleusercontent.com",
        "TUNEDIN_USE_LOCAL_AUTH_STORAGE": "NO",
        "TUNEDIN_POSTHOG_PROJECT_TOKEN": "phc_wrong-project",
        "TUNEDIN_POSTHOG_PROJECT_ID": "507315",
        "TUNEDIN_POSTHOG_HOST": "https://us.i.posthog.com"
      ])
    }
  }

  @Test
  func rejectsMalformedCallbackSchemes() {
    #expect(throws: AppConfigurationError.self) {
      try AppConfiguration.load(configuration: [
        "TUNEDIN_SUPABASE_URL": "https://staging-project.supabase.co",
        "TUNEDIN_SUPABASE_PUBLISHABLE_KEY": "staging-publishable-key",
        "TUNEDIN_APP_ENVIRONMENT": "Staging",
        "TUNEDIN_AUTH_EXPERIENCE": "Email",
        "TUNEDIN_AUTH_CALLBACK_SCHEME": "https://wrong.example.com/callback",
        "TUNEDIN_USE_LOCAL_AUTH_STORAGE": "NO"
      ])
    }
  }
}
