import Foundation

struct AppConfiguration: Sendable {
  let supabaseURL: URL
  let supabasePublishableKey: String

  static let authCallbackURL = URL(string: "com.ethanherrera.tunedin://auth-callback")!

  static func load(bundle: Bundle? = nil) throws -> Self {
    let configurationBundle = bundle ?? Bundle(for: TunedInBundleMarker.self)

    guard let rawURLString = configurationBundle.object(forInfoDictionaryKey: "TUNEDIN_SUPABASE_URL") as? String else {
      throw AppConfigurationError.missing("SUPABASE_URL")
    }

    let urlString = rawURLString
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .trimmingCharacters(in: CharacterSet(charactersIn: "\""))

    guard
      let supabaseURL = URL(string: urlString),
      supabaseURL.host != nil,
      !urlString.hasPrefix("$(")
    else {
      throw AppConfigurationError.missing("SUPABASE_URL")
    }

    guard
      let supabasePublishableKey = configurationBundle.object(
        forInfoDictionaryKey: "TUNEDIN_SUPABASE_PUBLISHABLE_KEY"
      ) as? String,
      !supabasePublishableKey.isEmpty,
      !supabasePublishableKey.hasPrefix("$(")
    else {
      throw AppConfigurationError.missing("SUPABASE_PUBLISHABLE_KEY")
    }

    return Self(
      supabaseURL: supabaseURL,
      supabasePublishableKey: supabasePublishableKey
    )
  }
}

private final class TunedInBundleMarker {}

enum AppConfigurationError: LocalizedError {
  case missing(String)

  var errorDescription: String? {
    switch self {
    case let .missing(key):
      "Missing app configuration for \(key). Copy the matching .xcconfig.example file before running."
    }
  }
}
