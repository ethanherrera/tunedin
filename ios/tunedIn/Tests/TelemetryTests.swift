import Foundation
import Testing
@testable import tunedIn

@MainActor
struct TelemetryTests {
  @Test
  func recordingClientKeepsOnlySanitizedRecordsWithoutNetworkConfiguration() {
    let defaults = isolatedDefaults()
    let client = AppTelemetryClient(
      configuration: .recording,
      release: release,
      defaults: defaults
    )

    client.capture(
      .concertUpdated,
      properties: [
        .changeKind: .string(TelemetryChangeKind.setlist.rawValue),
        .category: .string("must-be-dropped"),
        .destination: .string("https://private.example.com")
      ]
    )

    let record = client.recentRecords.last
    #expect(record?.name == TelemetryEvent.concertUpdated.rawValue)
    #expect(record?.properties[.changeKind] == .string("setlist"))
    #expect(record?.properties[.category] == nil)
    #expect(record?.properties[.destination] == nil)
  }

  @Test
  func collectionPreferenceDefaultsOnAndStopsCaptureWhenDisabled() {
    let defaults = isolatedDefaults()
    let client = AppTelemetryClient(
      configuration: .recording,
      release: release,
      defaults: defaults
    )

    #expect(client.isCollectionEnabled)
    client.setCollectionEnabled(false)
    let countAfterConsentRecord = client.recentRecords.count
    client.capture(.concertCreated)

    #expect(!client.isCollectionEnabled)
    #expect(client.recentRecords.count == countAfterConsentRecord)
    #expect(defaults.bool(forKey: AppTelemetryClient.collectionPreferenceKey) == false)
  }

  @Test
  func sanitizerDropsUnknownEventsAndFreeTextLikeValues() {
    #expect(
      TelemetrySanitizer.sanitizePostHogProperties(
        eventName: "unmanaged_event",
        properties: [:]
      ) == nil
    )

    let sanitized = TelemetrySanitizer.sanitize(
      event: .feedbackSubmitted,
      properties: [
        .category: .string("bug"),
        .environment: .string("staging"),
        .destination: .string("person@example.com")
      ]
    )
    #expect(sanitized[.category] == .string("bug"))
    #expect(sanitized[.destination] == nil)
  }

  @Test
  func sanitizerKeepsBoundedNativeAuthenticationDiagnostics() {
    let sanitized = TelemetrySanitizer.sanitize(
      event: .authenticationCompleted,
      properties: [
        .method: .string("apple"),
        .outcome: .string("failed"),
        .failureCategory: .string("unexpected"),
        .statusClass: .string("apple_authorization_1000"),
        .destination: .string("person@example.com")
      ]
    )

    #expect(sanitized[.method] == .string("apple"))
    #expect(sanitized[.statusClass] == .string("apple_authorization_1000"))
    #expect(sanitized[.destination] == nil)
  }

  @Test
  func recordingBufferIsBounded() {
    let client = AppTelemetryClient(
      configuration: .recording,
      release: release,
      defaults: isolatedDefaults()
    )

    for _ in 0 ..< 120 {
      client.capture(.concertCreated)
    }

    #expect(client.recentRecords.count == 100)
  }

  private var release: ReleaseMetadata {
    ReleaseMetadata(
      version: "0.1.0",
      build: "42",
      gitSHA: "0123456789abcdef",
      environment: .development
    )
  }

  private func isolatedDefaults() -> UserDefaults {
    let suiteName = "TelemetryTests.\(UUID().uuidString)"
    return UserDefaults(suiteName: suiteName)!
  }
}
