import Foundation
import PostHog

@MainActor
final class PostHogTelemetryTransport: TelemetryTransport {
  private let sdk = PostHogSDK.shared

  init(
    project: PostHogProjectConfiguration,
    release: ReleaseMetadata,
    collectionEnabled: Bool
  ) {
    let configuration = PostHogConfig(
      projectToken: project.projectToken,
      host: project.host.absoluteString
    )
    configuration.captureApplicationLifecycleEvents = false
    configuration.captureScreenViews = false
    configuration.enableSwizzling = false
    configuration.captureElementInteractions = false
    configuration.rageClickConfig.enabled = false
    configuration.sessionReplay = false
    configuration.surveys = false
    configuration.preloadFeatureFlags = false
    configuration.sendFeatureFlagEvent = false
    configuration.setDefaultPersonProperties = false
    configuration.personProfiles = .identifiedOnly
    configuration.errorTrackingConfig.autoCapture = true
    configuration.errorTrackingConfig.exceptionSteps.enabled = false
    configuration.optOut = !collectionEnabled
    configuration.maxQueueSize = 100
    configuration.logs.maxBufferSize = 100
    configuration.logs.serviceName = "tunedIn"
    configuration.logs.serviceVersion = release.version
    configuration.logs.environment = release.environment.rawValue.lowercased()
    configuration.logs.resourceAttributes = [
      "build_number": release.build,
      "git_sha": String(release.gitSHA.prefix(12))
    ]
    configuration.setBeforeSend { event in
      guard let properties = TelemetrySanitizer.sanitizePostHogProperties(
        eventName: event.event,
        properties: event.properties
      ) else {
        return nil
      }
      event.properties = properties
      return event
    }
    configuration.logs.setBeforeSend { record in
      guard [.warn, .error, .fatal].contains(record.level) else { return nil }
      record.body = TelemetryLogMessage(rawValue: record.body)?.rawValue ?? ""
      record.screenName = nil
      record.sessionId = nil
      record.featureFlagKeys = []
      record.attributes = record.attributes.filter { TelemetryProperty(rawValue: $0.key) != nil }
      return record
    }
    sdk.setup(configuration)
  }

  func identify(userID: UUID) {
    sdk.identify(userID.uuidString.lowercased())
  }

  func reset() {
    sdk.reset()
  }

  func setCollectionEnabled(_ enabled: Bool) {
    if enabled {
      sdk.optIn()
    } else {
      sdk.optOut()
      sdk.reset()
    }
  }

  func capture(
    _ event: TelemetryEvent,
    properties: [TelemetryProperty: TelemetryValue]
  ) {
    sdk.capture(event.rawValue, properties: properties.foundationDictionary)
  }

  func log(
    _ level: TelemetryLogLevel,
    message: TelemetryLogMessage,
    properties: [TelemetryProperty: TelemetryValue]
  ) {
    let severity: PostHogLogSeverity = switch level {
    case .warning: .warn
    case .error: .error
    case .fatal: .fatal
    }
    sdk.captureLog(
      message.rawValue,
      level: severity,
      attributes: properties.foundationDictionary
    )
  }
}
