import Foundation

struct AppConfiguration: Sendable {
  let supabaseURL: URL
  let supabasePublishableKey: String
  let environment: AppEnvironment
  let authCallbackURL: URL
  let authSessionStorageKey: String
  let authEmailDeliveryMode: AuthEmailDeliveryMode
  let usesLocalSimulatorAuthStorage: Bool

  static func load(bundle: Bundle? = nil) throws -> Self {
    let configurationBundle = bundle ?? Bundle(for: TunedInBundleMarker.self)
    return try load(configuration: configurationBundle.infoDictionary ?? [:])
  }

  static func load(configuration: [String: Any]) throws -> Self {
    guard let rawURLString = configuration["TUNEDIN_SUPABASE_URL"] as? String else {
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
      let supabasePublishableKey = configuration["TUNEDIN_SUPABASE_PUBLISHABLE_KEY"] as? String,
      !supabasePublishableKey.isEmpty,
      !supabasePublishableKey.hasPrefix("$(")
    else {
      throw AppConfigurationError.missing("SUPABASE_PUBLISHABLE_KEY")
    }

    guard
      let appEnvironment = configuration["TUNEDIN_APP_ENVIRONMENT"] as? String
    else {
      throw AppConfigurationError.missing("APP_ENVIRONMENT")
    }

    let environmentValue = appEnvironment.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let environment = AppEnvironment(rawValue: environmentValue) else {
      throw AppConfigurationError.invalid("APP_ENVIRONMENT")
    }

    guard
      let callbackScheme = configuration["TUNEDIN_AUTH_CALLBACK_SCHEME"] as? String,
      callbackScheme.range(of: #"^[A-Za-z][A-Za-z0-9+.-]*$"#, options: .regularExpression) != nil,
      let authCallbackURL = URL(string: "\(callbackScheme)://auth-callback")
    else {
      throw AppConfigurationError.invalid("AUTH_CALLBACK_SCHEME")
    }

    let usesLocalSimulatorAuthStorage = configuration["TUNEDIN_USE_LOCAL_AUTH_STORAGE"] as? String == "YES"

    if usesLocalSimulatorAuthStorage,
       !["127.0.0.1", "localhost"].contains(supabaseURL.host)
    {
      throw AppConfigurationError.invalid("TUNEDIN_USE_LOCAL_AUTH_STORAGE")
    }

    let authEmailDeliveryMode: AuthEmailDeliveryMode = environment == .development
      ? .magicLink
      : .oneTimeCode

    return Self(
      supabaseURL: supabaseURL,
      supabasePublishableKey: supabasePublishableKey,
      environment: environment,
      authCallbackURL: authCallbackURL,
      authSessionStorageKey: "\(callbackScheme).auth.session",
      authEmailDeliveryMode: authEmailDeliveryMode,
      usesLocalSimulatorAuthStorage: usesLocalSimulatorAuthStorage
    )
  }
}

enum AppEnvironment: String, Sendable {
  case development = "Development"
  case staging = "Staging"
  case production = "Production"
}

enum AuthEmailDeliveryMode: Equatable, Sendable {
  case magicLink
  case oneTimeCode
}

private final class TunedInBundleMarker {}

enum AppConfigurationError: LocalizedError {
  case missing(String)
  case invalid(String)

  var errorDescription: String? {
    switch self {
    case let .missing(key):
      "Missing app configuration for \(key). Copy the matching .xcconfig.example file before running."
    case let .invalid(key):
      "Invalid app configuration for \(key). Check the matching .xcconfig file."
    }
  }
}
