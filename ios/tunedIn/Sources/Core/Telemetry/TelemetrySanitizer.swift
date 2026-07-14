import Foundation

enum TelemetrySanitizer {
  private static let commonProperties: Set<TelemetryProperty> = [
    .environment,
    .releaseVersion,
    .buildNumber,
    .gitSHA,
    .osMajor,
    .deviceClass
  ]

  private static let eventProperties: [TelemetryEvent: Set<TelemetryProperty>] = [
    .appBecameUsable: [.durationMilliseconds, .destination],
    .authenticationCompleted: [
      .method,
      .durationMilliseconds,
      .firstSession,
      .outcome,
      .failureCategory,
      .retryable,
      .statusClass
    ],
    .profileSetupCompleted: [.durationMilliseconds],
    .friendRequestSent: [.durationMilliseconds],
    .friendRequestAccepted: [.durationMilliseconds],
    .collaboratorAdded: [.durationMilliseconds],
    .concertCreated: [.durationMilliseconds],
    .concertUpdated: [.durationMilliseconds, .changeKind],
    .commentCreated: [.durationMilliseconds],
    .photoUploadCompleted: [
      .durationMilliseconds,
      .attemptedCount,
      .succeededCount,
      .partialSuccess,
      .retryUsed,
      .outcome,
      .failureCategory
    ],
    .ownershipTransferred: [.durationMilliseconds],
    .feedbackSubmitted: [.durationMilliseconds, .category, .outcome, .failureCategory],
    .screenLoadCompleted: [.screen, .durationMilliseconds, .outcome, .failureCategory, .retryable],
    .coreOperationCompleted: [
      .operation,
      .durationMilliseconds,
      .outcome,
      .failureCategory,
      .retryable,
      .statusClass
    ]
  ]

  private static let logProperties: Set<TelemetryProperty> = commonProperties.union([
    .operation,
    .method,
    .failureCategory,
    .retryable,
    .statusClass
  ])

  static func sanitize(
    event: TelemetryEvent,
    properties: [TelemetryProperty: TelemetryValue]
  ) -> [TelemetryProperty: TelemetryValue] {
    let allowed = commonProperties.union(eventProperties[event] ?? [])
    return properties.filter { allowed.contains($0.key) && isSafe($0.value) }
  }

  static func sanitizeLog(
    _ properties: [TelemetryProperty: TelemetryValue]
  ) -> [TelemetryProperty: TelemetryValue] {
    properties.filter { logProperties.contains($0.key) && isSafe($0.value) }
  }

  static func sanitizePostHogProperties(
    eventName: String,
    properties: [String: Any]
  ) -> [String: Any]? {
    if eventName == "$identify" {
      return properties.filter { ["$anon_distinct_id", "$set", "$set_once"].contains($0.key) }
    }

    if eventName == "$exception" {
      let allowed = Set([
        "$exception_list",
        "$exception_level",
        "$exception_fingerprint",
        "$lib",
        "$lib_version",
        "environment",
        "release_version",
        "build_number",
        "git_sha",
        "os_major",
        "device_class"
      ])
      var sanitized = properties.filter { allowed.contains($0.key) }
      sanitized["$exception_list"] = sanitizeExceptionList(properties["$exception_list"])
      return sanitized
    }

    guard let event = TelemetryEvent(rawValue: eventName) else { return nil }
    let typed = properties.reduce(into: [TelemetryProperty: TelemetryValue]()) { result, item in
      guard let key = TelemetryProperty(rawValue: item.key), let value = telemetryValue(item.value) else { return }
      result[key] = value
    }
    return sanitize(event: event, properties: typed).foundationDictionary
  }

  private static func sanitizeExceptionList(_ value: Any?) -> Any {
    guard let exceptions = value as? [[String: Any]] else { return [] }
    return exceptions.map { exception in
      exception.filter { ["type", "mechanism", "stacktrace"].contains($0.key) }
    }
  }

  private static func telemetryValue(_ value: Any) -> TelemetryValue? {
    switch value {
    case let value as String: .string(value)
    case let value as Int: .integer(value)
    case let value as Double: .double(value)
    case let value as Bool: .boolean(value)
    default: nil
    }
  }

  private static func isSafe(_ value: TelemetryValue) -> Bool {
    guard case let .string(string) = value else { return true }
    return string.count <= 80
      && !string.contains("@")
      && !string.localizedCaseInsensitiveContains("http")
      && !string.contains("/")
      && !string.contains("\\")
  }
}

extension [TelemetryProperty: TelemetryValue] {
  var foundationDictionary: [String: Any] {
    reduce(into: [:]) { result, item in
      result[item.key.rawValue] = item.value.foundationValue
    }
  }
}
