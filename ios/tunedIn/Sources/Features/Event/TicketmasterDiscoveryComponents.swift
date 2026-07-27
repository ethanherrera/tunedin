import SwiftUI

// swiftlint:disable:next inclusive_language
struct TicketmasterDiscoveryFilterBar: View {
  @Binding var dateRange: TicketmasterDiscoveryDateRange?
  @Binding var genre: String?
  let genres: [String]
  let onSelectDates: () -> Void

  var body: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 8) {
        Button(action: onSelectDates) {
          filterChip(
            title: dateRange?.title ?? "Dates",
            systemImage: "calendar",
            isSelected: dateRange != nil
          )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(dateRange.map { "Dates, \($0.title)" } ?? "Dates")
        .accessibilityHint("Changes the beginning and end dates")
        genreMenu
      }
    }
    .contentMargins(.horizontal, 0)
  }

  private var genreMenu: some View {
    Menu {
      Button {
        genre = nil
      } label: {
        if genre == nil {
          Label("All genres", systemImage: "checkmark")
        } else {
          Text("All genres")
        }
      }
      ForEach(genres, id: \.self) { option in
        Button {
          genre = option
        } label: {
          if option == genre {
            Label(option, systemImage: "checkmark")
          } else {
            Text(option)
          }
        }
      }
    } label: {
      filterChip(
        title: genre ?? "Genre",
        systemImage: "music.note",
        isSelected: genre != nil
      )
    }
  }

  private func filterChip(
    title: String,
    systemImage: String,
    isSelected: Bool
  ) -> some View {
    Label(title, systemImage: systemImage)
      .font(.subheadline.weight(.semibold))
      .foregroundStyle(
        isSelected ? TunedInDesign.selectedControlForeground : TunedInDesign.primaryText
      )
      .padding(.horizontal, 14)
      .frame(height: 42)
      .background(
        isSelected ? TunedInDesign.accentTint : TunedInDesign.raisedSurface,
        in: Capsule()
      )
      .overlay {
        Capsule().strokeBorder(
          isSelected ? TunedInDesign.accent.opacity(0.32) : TunedInDesign.cardBorder
        )
      }
  }
}

// swiftlint:disable:next inclusive_language
struct TicketmasterDiscoveryDateFilterSheet: View {
  let onApply: (TicketmasterDiscoveryDateRange) -> Void
  let onClear: () -> Void

  @Environment(\.dismiss) private var dismiss
  @State private var startDate: Date
  @State private var endDate: Date

  init(
    dateRange: TicketmasterDiscoveryDateRange?,
    onApply: @escaping (TicketmasterDiscoveryDateRange) -> Void,
    onClear: @escaping () -> Void
  ) {
    self.onApply = onApply
    self.onClear = onClear
    let initialRange = dateRange ?? .nextThirtyDays()
    _startDate = State(initialValue: initialRange.startDate)
    _endDate = State(initialValue: initialRange.endDate)
  }

  var body: some View {
    NavigationStack {
      ZStack {
        TunedInDesign.pageBackground.ignoresSafeArea()

        VStack(alignment: .leading, spacing: 18) {
          VStack(alignment: .leading, spacing: 5) {
            Text("Dates")
              .font(.title2.weight(.bold))
              .foregroundStyle(TunedInDesign.primaryText)
            Text("Choose the beginning and end of your concert search.")
              .font(.subheadline)
              .foregroundStyle(TunedInDesign.mutedText)
          }

          TunedInGlassSection {
            VStack(spacing: 0) {
              DatePicker("Beginning", selection: $startDate, displayedComponents: .date)
                .onChange(of: startDate) { _, startDate in
                  guard endDate < startDate else { return }
                  endDate = startDate
                }

              Divider()
                .overlay(TunedInDesign.cardBorder)
                .padding(.vertical, 10)

              DatePicker("End", selection: $endDate, in: startDate..., displayedComponents: .date)
            }
            .tint(TunedInDesign.accent)
          }

          Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 24)
        .padding(.bottom, TunedInDesign.scrollContentBottomInset + TunedInDesign.controlSize)
      }
      .toolbar(.hidden, for: .navigationBar)
      .safeAreaInset(edge: .bottom, spacing: 0) {
        TunedInPersistentControlRegion {
          bottomControls
            .padding(.horizontal, TunedInDesign.bottomControlHorizontalInset)
            .padding(.top, 8)
            .padding(.bottom, TunedInDesign.bottomControlInset)
        }
      }
    }
    .tunedInEdgeSwipeBack { dismiss() }
  }

  private var bottomControls: some View {
    TunedInGlassTraversalLayout {
      TunedInGlassIconButton(
        systemImage: "chevron.backward",
        accessibilityLabel: "Back to concert discovery",
        remainsVisibleWithKeyboard: true
      ) {
        dismiss()
      }
    } center: {
      TunedInGlassBottomBar {
        Button {
          onClear()
          dismiss()
        } label: {
          Text("Clear")
            .font(.subheadline.weight(.bold))
            .foregroundStyle(TunedInDesign.primaryText)
            .frame(minWidth: 112, minHeight: 48)
            .padding(.horizontal, 14)
            .contentShape(.interaction, Capsule())
        }
        .buttonStyle(.plain)
      }
    } trailing: {
      TunedInGlassIconButton(
        systemImage: "checkmark",
        accessibilityLabel: "Apply discovery dates",
        style: .accent,
        remainsVisibleWithKeyboard: true
      ) {
        onApply(TicketmasterDiscoveryDateRange(startDate: startDate, endDate: endDate))
        dismiss()
      }
    }
  }
}

// swiftlint:disable:next inclusive_language
struct TicketmasterDiscoveryCard: View {
  let event: TicketmasterDiscoveryEvent
  let isResolving: Bool

  var body: some View {
    HStack(spacing: 12) {
      artwork
        .frame(width: 88, height: 88)
        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))

      VStack(alignment: .leading, spacing: 4) {
        Text(event.headlinerName)
          .font(.headline)
          .foregroundStyle(TunedInDesign.primaryText)
          .lineLimit(1)
        if event.name != event.headlinerName {
          Text(event.name)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(TunedInDesign.primaryText)
            .lineLimit(1)
        }
        Text(eventTime)
          .font(.caption.weight(.semibold))
          .foregroundStyle(TunedInDesign.accent)
        Text("\(event.venue.name) · \(event.venue.city)")
          .font(.caption)
          .foregroundStyle(TunedInDesign.mutedText)
          .lineLimit(1)
        sourceAndStatus
      }
      .frame(maxWidth: .infinity, alignment: .leading)

      if isResolving {
        ProgressView()
      } else {
        Image(systemName: "chevron.right")
          .font(.caption.weight(.bold))
          .foregroundStyle(TunedInDesign.mutedText)
      }
    }
    .padding(10)
    .background(
      TunedInDesign.cardBackground,
      in: RoundedRectangle(cornerRadius: 20, style: .continuous)
    )
    .overlay {
      RoundedRectangle(cornerRadius: 20, style: .continuous)
        .strokeBorder(TunedInDesign.cardBorder)
    }
    .contentShape(Rectangle())
  }

  private var eventTime: String {
    event.displayDate.formatted(date: .omitted, time: .shortened)
  }

  @ViewBuilder
  private var sourceAndStatus: some View {
    HStack(spacing: 6) {
      Text("Ticketmaster")
      if event.status != "active" {
        Text("•")
        Text(event.status.capitalized)
          .foregroundStyle(.red)
      }
    }
    .font(.caption2.weight(.bold))
    .foregroundStyle(TunedInDesign.mutedText)
  }

  @ViewBuilder
  private var artwork: some View {
    if let imageURL = event.imageURL {
      CachedRemoteImage(
        url: imageURL,
        resource: .discoveryArtwork(externalID: event.id)
      ) { phase in
        switch phase {
        case let .success(image):
          image.resizable().scaledToFill()
        default:
          placeholder
        }
      }
    } else {
      placeholder
    }
  }

  private var placeholder: some View {
    ZStack {
      TunedInDesign.accentTint
      Image(systemName: "music.note")
        .font(.title2.bold())
        .foregroundStyle(TunedInDesign.accent)
    }
  }
}
