import SwiftUI

struct TelemetrySettingsSection: View {
  let telemetry: AppTelemetryClient

  var body: some View {
    TunedInFormCard {
      Text("Privacy")
        .font(.headline)
        .foregroundStyle(TunedInDesign.primaryText)

      Toggle(
        "Share diagnostics & usage",
        isOn: Binding(
          get: { telemetry.isCollectionEnabled },
          set: { telemetry.setCollectionEnabled($0) }
        )
      )
      .tint(TunedInDesign.accent)

      Text(
        "Shares app reliability and journey outcomes without names, email, concert details, comments, captions, or photos."
      )
      .font(.footnote)
      .foregroundStyle(TunedInDesign.mutedText)

      #if DEBUG
        NavigationLink("Telemetry inspector") {
          TelemetryInspectorView(telemetry: telemetry)
        }
        .font(.subheadline.weight(.semibold))
      #endif
    }
  }
}

#if DEBUG
  private struct TelemetryInspectorView: View {
    let telemetry: AppTelemetryClient

    var body: some View {
      List {
        Section("Synthetic checks") {
          Button("Record product event") {
            telemetry.capture(
              .eventUpdated,
              properties: [.durationMilliseconds: .integer(180)]
            )
          }
          Button("Record handled failure") {
            telemetry.captureOperation(
              .loadProfile,
              outcome: .failed,
              duration: .milliseconds(240),
              failure: .retryable
            )
          }
          Button("Record sanitized log") {
            telemetry.log(
              .error,
              message: .profileLoadFailed,
              properties: [
                .operation: .string(TelemetryOperation.loadProfile.rawValue),
                .failureCategory: .string(TelemetryFailureCategory.retryable.rawValue)
              ]
            )
          }
        }

        Section("Last \(telemetry.recentRecords.count) records") {
          if telemetry.recentRecords.isEmpty {
            ContentUnavailableView(
              "No telemetry yet",
              systemImage: "waveform.path.ecg",
              description: Text("Use a synthetic check or complete a journey in the app.")
            )
          } else {
            ForEach(telemetry.recentRecords.reversed()) { record in
              VStack(alignment: .leading, spacing: 5) {
                HStack {
                  Text(record.kind.rawValue.uppercased())
                    .font(.caption2.weight(.black))
                    .foregroundStyle(TunedInDesign.accent)
                  Spacer()
                  Text(record.date, style: .time)
                    .font(.caption)
                    .foregroundStyle(TunedInDesign.mutedText)
                }
                Text(record.name)
                  .font(.subheadline.weight(.semibold))
                if !record.properties.isEmpty {
                  Text(record.properties.displayString)
                    .font(.caption.monospaced())
                    .foregroundStyle(TunedInDesign.mutedText)
                }
              }
              .padding(.vertical, 4)
            }
          }
        }
      }
      .scrollContentBackground(.hidden)
      .background(TunedInDesign.pageBackground)
      .navigationTitle("Telemetry")
      .navigationBarTitleDisplayMode(.inline)
    }
  }

  private extension [TelemetryProperty: TelemetryValue] {
    var displayString: String {
      sorted { $0.key.rawValue < $1.key.rawValue }
        .map { "\($0.key.rawValue)=\($0.value.displayString)" }
        .joined(separator: " · ")
    }
  }

  private extension TelemetryValue {
    var displayString: String {
      switch self {
      case let .string(value): value
      case let .integer(value): String(value)
      case let .double(value): String(value)
      case let .boolean(value): String(value)
      }
    }
  }
#endif
