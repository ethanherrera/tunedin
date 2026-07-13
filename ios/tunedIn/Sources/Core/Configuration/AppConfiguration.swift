import Foundation

struct AppConfiguration: Sendable {
  let supabaseURL: URL
  let supabasePublishableKey: String
  let environment: AppEnvironment
  let authCallbackURL: URL
  let authSessionStorageKey: String
  let authEmailDeliveryMode: AuthEmailDeliveryMode
  let nativeSocialAuthConfiguration: NativeSocialAuthConfiguration?
  let usesLocalSimulatorAuthStorage: Bool
  let telemetry: TelemetryConfiguration
  let release: ReleaseMetadata

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
    let isLocalSupabaseHost = ["127.0.0.1", "localhost"].contains(supabaseURL.host)

    if usesLocalSimulatorAuthStorage && !isLocalSupabaseHost {
      throw AppConfigurationError.invalid("TUNEDIN_USE_LOCAL_AUTH_STORAGE")
    }

    let authEmailDeliveryMode: AuthEmailDeliveryMode = environment == .development
      ? .magicLink
      : .oneTimeCode

    let authExperience = configuration["TUNEDIN_AUTH_EXPERIENCE"] as? String
    let nativeSocialAuthConfiguration: NativeSocialAuthConfiguration?
    switch authExperience {
    case "Email":
      nativeSocialAuthConfiguration = nil
    case "NativeSocial":
      guard environment == .staging || environment == .production else {
        throw AppConfigurationError.invalid("AUTH_EXPERIENCE")
      }
      nativeSocialAuthConfiguration = try NativeSocialAuthConfiguration.load(configuration: configuration)
    default:
      throw AppConfigurationError.invalid("AUTH_EXPERIENCE")
    }

    let telemetry = try TelemetryConfiguration.load(
      configuration: configuration,
      environment: environment,
      usesLocalSimulatorAuthStorage: usesLocalSimulatorAuthStorage
    )

    let release = ReleaseMetadata(
      version: normalizedValue(configuration["CFBundleShortVersionString"]) ?? "unknown",
      build: normalizedValue(configuration["CFBundleVersion"]) ?? "unknown",
      gitSHA: normalizedValue(configuration["TUNEDIN_GIT_SHA"]) ?? "unknown",
      environment: environment
    )

    return Self(
      supabaseURL: supabaseURL,
      supabasePublishableKey: supabasePublishableKey,
      environment: environment,
      authCallbackURL: authCallbackURL,
      authSessionStorageKey: "\(callbackScheme).auth.session",
      authEmailDeliveryMode: authEmailDeliveryMode,
      nativeSocialAuthConfiguration: nativeSocialAuthConfiguration,
      usesLocalSimulatorAuthStorage: usesLocalSimulatorAuthStorage,
      telemetry: telemetry,
      release: release
    )
  }

  fileprivate static func normalizedValue(_ value: Any?) -> String? {
    guard let string = value as? String else { return nil }
    let normalized = string.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalized.isEmpty, !normalized.hasPrefix("$("), !normalized.hasPrefix("REPLACE_WITH_") else {
      return nil
    }
    return normalized
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

struct NativeSocialAuthConfiguration: Equatable, Sendable {
  let googleIOSClientID: String
  let googleServerClientID: String

  fileprivate static func load(configuration: [String: Any]) throws -> Self {
    guard
      let googleIOSClientID = AppConfiguration.normalizedValue(configuration["GIDClientID"]),
      googleIOSClientID.hasSuffix(".apps.googleusercontent.com")
    else {
      throw AppConfigurationError.missing("GOOGLE_IOS_CLIENT_ID")
    }
    guard
      let googleServerClientID = AppConfiguration.normalizedValue(configuration["GIDServerClientID"]),
      googleServerClientID.hasSuffix(".apps.googleusercontent.com")
    else {
      throw AppConfigurationError.missing("GOOGLE_SERVER_CLIENT_ID")
    }

    return Self(
      googleIOSClientID: googleIOSClientID,
      googleServerClientID: googleServerClientID
    )
  }
}

struct ReleaseMetadata: Equatable, Sendable {
  let version: String
  let build: String
  let gitSHA: String
  let environment: AppEnvironment
}

enum TelemetryConfiguration: Equatable, Sendable {
  case recording
  case disabled
  case postHog(PostHogProjectConfiguration)

  fileprivate static func load(
    configuration: [String: Any],
    environment: AppEnvironment,
    usesLocalSimulatorAuthStorage: Bool
  ) throws -> Self {
    if usesLocalSimulatorAuthStorage || environment == .development {
      return .recording
    }

    let projectToken = AppConfiguration.normalizedValue(configuration["TUNEDIN_POSTHOG_PROJECT_TOKEN"])
    let projectID = AppConfiguration.normalizedValue(configuration["TUNEDIN_POSTHOG_PROJECT_ID"])
    let hostValue = AppConfiguration.normalizedValue(configuration["TUNEDIN_POSTHOG_HOST"])

    if environment == .production, projectToken == nil, projectID == nil, hostValue == nil {
      return .disabled
    }

    guard let projectToken else {
      throw AppConfigurationError.missing("POSTHOG_PROJECT_TOKEN")
    }
    guard let projectID else {
      throw AppConfigurationError.missing("POSTHOG_PROJECT_ID")
    }
    guard
      let hostValue,
      let host = URL(string: hostValue),
      host.scheme == "https",
      host.host == "us.i.posthog.com"
    else {
      throw AppConfigurationError.invalid("POSTHOG_HOST")
    }

    if environment == .staging, projectID != PostHogProjectConfiguration.stagingProjectID {
      throw AppConfigurationError.invalid("POSTHOG_PROJECT_ID")
    }

    return .postHog(
      PostHogProjectConfiguration(
        projectToken: projectToken,
        projectID: projectID,
        host: host
      )
    )
  }
}

struct PostHogProjectConfiguration: Equatable, Sendable {
  static let stagingProjectID = "507318"

  let projectToken: String
  let projectID: String
  let host: URL
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
