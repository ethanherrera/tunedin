import SwiftUI

struct EventTimeZonePickerView: View {
  let selectedIdentifier: String
  let referenceDate: Date
  let onSelect: (String) -> Void
  let onDismiss: () -> Void

  @State private var query = ""

  var body: some View {
    ZStack {
      TunedInDesign.pageBackground.ignoresSafeArea()

      ScrollView {
        VStack(alignment: .leading, spacing: 18) {
          EventScreenHeader(
            eyebrow: "Venue local time",
            title: "Time zone",
            subtitle: "Concert dates and start times stay anchored to where the show happens."
          )

          TunedInGlassSearchField(text: $query, prompt: "City or time zone")

          LazyVStack(spacing: 10) {
            ForEach(filteredIdentifiers, id: \.self) { identifier in
              Button { onSelect(identifier) } label: {
                HStack(spacing: 12) {
                  VStack(alignment: .leading, spacing: 3) {
                    Text(EventTimeZoneText.name(for: identifier))
                      .font(.body.weight(.semibold))
                      .foregroundStyle(TunedInDesign.primaryText)
                    Text(EventTimeZoneText.detail(for: identifier, at: referenceDate))
                      .font(.caption)
                      .foregroundStyle(TunedInDesign.mutedText)
                  }
                  Spacer()
                  if identifier == selectedIdentifier {
                    Image(systemName: "checkmark.circle.fill")
                      .foregroundStyle(TunedInDesign.accent)
                  }
                }
                .padding(14)
                .background(TunedInDesign.raisedSurface, in: RoundedRectangle(cornerRadius: 16))
              }
              .buttonStyle(.plain)
            }
          }
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, TunedInDesign.scrollContentBottomInset)
      }
    }
    .toolbar(.hidden, for: .navigationBar)
    .safeAreaInset(edge: .bottom, spacing: 0) {
      TunedInPersistentControlRegion {
        TunedInSubscreenBackBar(title: "Time zone", action: onDismiss)
          .padding(.horizontal, TunedInDesign.bottomControlHorizontalInset)
          .padding(.top, 8)
          .padding(.bottom, TunedInDesign.bottomControlInset)
      }
    }
    .tunedInEdgeSwipeBack(action: onDismiss)
  }

  private var filteredIdentifiers: [String] {
    let normalized = CatalogInput.normalizedText(query).lowercased()
    return TimeZone.knownTimeZoneIdentifiers
      .filter { identifier in
        normalized.isEmpty
          || identifier.lowercased().contains(normalized)
          || EventTimeZoneText.name(for: identifier).lowercased().contains(normalized)
      }
      .sorted { EventTimeZoneText.name(for: $0) < EventTimeZoneText.name(for: $1) }
  }
}

enum EventTimeZoneText {
  static func name(for identifier: String) -> String {
    identifier
      .split(separator: "/")
      .last
      .map(String.init)?
      .replacingOccurrences(of: "_", with: " ")
      ?? identifier
  }

  static func detail(for identifier: String, at date: Date) -> String {
    guard let timeZone = TimeZone(identifier: identifier) else { return identifier }
    let seconds = timeZone.secondsFromGMT(for: date)
    let sign = seconds < 0 ? "−" : "+"
    let absoluteSeconds = abs(seconds)
    let hours = absoluteSeconds / 3_600
    let minutes = (absoluteSeconds % 3_600) / 60
    return String(format: "%@ · GMT%@%02d:%02d", identifier, sign, hours, minutes)
  }
}
