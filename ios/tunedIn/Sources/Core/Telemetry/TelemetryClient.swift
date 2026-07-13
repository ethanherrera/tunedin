import Foundation
import Observation
import OSLog
import SwiftUI

@MainActor
protocol TelemetryClient: AnyObject {
  var isCollectionEnabled: Bool { get }
  var recentRecords: [TelemetryRecord] { get }

  func identify(userID: UUID)
  func reset()
  func setCollectionEnabled(_ enabled: Bool)
  func capture(_ event: TelemetryEvent, properties: [TelemetryProperty: TelemetryValue])
  func captureOperation(
    _ operation: TelemetryOperation,
    outcome: TelemetryOutcome,
    duration: Duration,
    failure: AppFailure?
  )
  func log(
    _ level: TelemetryLogLevel,
    message: TelemetryLogMessage,
    properties: [TelemetryProperty: TelemetryValue]
  )
}

@MainActor
protocol TelemetryTransport: AnyObject {
  func identify(userID: UUID)
  func reset()
  func setCollectionEnabled(_ enabled: Bool)
  func capture(_ event: TelemetryEvent, properties: [TelemetryProperty: TelemetryValue])
  func log(
    _ level: TelemetryLogLevel,
    message: TelemetryLogMessage,
    properties: [TelemetryProperty: TelemetryValue]
  )
}

@MainActor
@Observable
final class AppTelemetryClient: TelemetryClient {
  static let collectionPreferenceKey = "tunedin.telemetry.collection-enabled"

  private let transport: any TelemetryTransport
  private let release: ReleaseMetadata
  private let defaults: UserDefaults
  private let recordsTelemetryLocally: Bool
  private(set) var recentRecords: [TelemetryRecord] = []
  private(set) var isCollectionEnabled: Bool
  private let startedAt = ContinuousClock.now
  private var hasCapturedAppUsable = false

  init(
    configuration: TelemetryConfiguration,
    release: ReleaseMetadata,
    defaults: UserDefaults = .standard
  ) {
    self.release = release
    self.defaults = defaults
    recordsTelemetryLocally = configuration == .recording
    let collectionEnabled = defaults.object(forKey: Self.collectionPreferenceKey) as? Bool ?? true
    isCollectionEnabled = collectionEnabled
    transport = TelemetryTransportFactory.make(
      configuration: configuration,
      release: release,
      collectionEnabled: collectionEnabled
    )
  }

  func identify(userID: UUID) {
    guard isCollectionEnabled else { return }
    transport.identify(userID: userID)
    record(kind: .identity, name: "identify", properties: [:])
  }

  func reset() {
    transport.reset()
    record(kind: .identity, name: "reset", properties: [:])
  }

  func setCollectionEnabled(_ enabled: Bool) {
    guard enabled != isCollectionEnabled else { return }
    isCollectionEnabled = enabled
    defaults.set(enabled, forKey: Self.collectionPreferenceKey)
    transport.setCollectionEnabled(enabled)
    record(kind: .consent, name: enabled ? "enabled" : "disabled", properties: [:])
  }

  func capture(
    _ event: TelemetryEvent,
    properties: [TelemetryProperty: TelemetryValue] = [:]
  ) {
    guard isCollectionEnabled else { return }
    let sanitized = TelemetrySanitizer.sanitize(
      event: event,
      properties: commonProperties.merging(properties) { _, new in new }
    )
    transport.capture(event, properties: sanitized)
    record(kind: .event, name: event.rawValue, properties: sanitized)
  }

  func captureAppBecameUsable(destination: String) {
    guard !hasCapturedAppUsable else { return }
    hasCapturedAppUsable = true
    capture(
      .appBecameUsable,
      properties: [
        .destination: .string(destination),
        .durationMilliseconds: .integer(startedAt.duration(to: .now).milliseconds)
      ]
    )
  }

  func captureOperation(
    _ operation: TelemetryOperation,
    outcome: TelemetryOutcome,
    duration: Duration,
    failure: AppFailure? = nil
  ) {
    var properties: [TelemetryProperty: TelemetryValue] = [
      .operation: .string(operation.rawValue),
      .outcome: .string(outcome.rawValue),
      .durationMilliseconds: .integer(duration.milliseconds)
    ]
    if let failure {
      properties[.failureCategory] = .string(TelemetryFailureCategory(failure).rawValue)
      properties[.retryable] = .boolean(failure.allowsRetry)
    }
    capture(.coreOperationCompleted, properties: properties)
  }

  func log(
    _ level: TelemetryLogLevel,
    message: TelemetryLogMessage,
    properties: [TelemetryProperty: TelemetryValue] = [:]
  ) {
    guard isCollectionEnabled else { return }
    let sanitized = TelemetrySanitizer.sanitizeLog(
      commonProperties.merging(properties) { _, new in new }
    )
    transport.log(level, message: message, properties: sanitized)
    record(kind: .log, name: message.rawValue, properties: sanitized)
  }

  private var commonProperties: [TelemetryProperty: TelemetryValue] {
    [
      .environment: .string(release.environment.rawValue.lowercased()),
      .releaseVersion: .string(release.version),
      .buildNumber: .string(release.build),
      .gitSHA: .string(String(release.gitSHA.prefix(12))),
      .osMajor: .integer(ProcessInfo.processInfo.operatingSystemVersion.majorVersion),
      .deviceClass: .string("phone")
    ]
  }

  private func record(
    kind: TelemetryRecord.Kind,
    name: String,
    properties: [TelemetryProperty: TelemetryValue]
  ) {
    guard recordsTelemetryLocally else { return }
    recentRecords.append(
      TelemetryRecord(
        id: UUID(),
        date: Date(),
        kind: kind,
        name: name,
        properties: properties
      )
    )
    if recentRecords.count > 100 {
      recentRecords.removeFirst(recentRecords.count - 100)
    }
  }
}

private struct TelemetryEnvironmentKey: EnvironmentKey {
  static let defaultValue: AppTelemetryClient? = nil
}

extension EnvironmentValues {
  var telemetry: AppTelemetryClient? {
    get { self[TelemetryEnvironmentKey.self] }
    set { self[TelemetryEnvironmentKey.self] = newValue }
  }
}

private extension Duration {
  var milliseconds: Int {
    let components = components
    let seconds = components.seconds * 1000
    let attoseconds = components.attoseconds / 1_000_000_000_000_000
    return Int(seconds + attoseconds)
  }
}

@MainActor
private enum TelemetryTransportFactory {
  static func make(
    configuration: TelemetryConfiguration,
    release: ReleaseMetadata,
    collectionEnabled: Bool
  ) -> any TelemetryTransport {
    switch configuration {
    case .recording:
      LocalTelemetryTransport()
    case .disabled:
      DisabledTelemetryTransport()
    case let .postHog(project):
      PostHogTelemetryTransport(
        project: project,
        release: release,
        collectionEnabled: collectionEnabled
      )
    }
  }
}

@MainActor
private final class LocalTelemetryTransport: TelemetryTransport {
  private let logger = Logger(subsystem: "com.ethanherrera.tunedin", category: "telemetry-local")

  func identify(userID _: UUID) {
    logger.debug("Recorded sanitized identity transition")
  }

  func reset() {
    logger.debug("Recorded sanitized identity reset")
  }

  func setCollectionEnabled(_ enabled: Bool) {
    logger.debug("Local telemetry collection enabled: \(enabled)")
  }

  func capture(_ event: TelemetryEvent, properties _: [TelemetryProperty: TelemetryValue]) {
    logger.debug("Recorded event: \(event.rawValue, privacy: .public)")
  }

  func log(
    _ level: TelemetryLogLevel,
    message: TelemetryLogMessage,
    properties _: [TelemetryProperty: TelemetryValue]
  ) {
    logger.debug("Recorded \(level.rawValue, privacy: .public) log: \(message.rawValue, privacy: .public)")
  }
}

@MainActor
private final class DisabledTelemetryTransport: TelemetryTransport {
  func identify(userID _: UUID) {}
  func reset() {}
  func setCollectionEnabled(_: Bool) {}
  func capture(_: TelemetryEvent, properties _: [TelemetryProperty: TelemetryValue]) {}
  func log(_: TelemetryLogLevel, message _: TelemetryLogMessage, properties _: [TelemetryProperty: TelemetryValue]) {}
}
