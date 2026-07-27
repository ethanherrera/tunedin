import SwiftUI

// swiftlint:disable:next inclusive_language
struct TicketmasterDiscoveryView: View {
  private struct LoadRequest: Equatable {
    let location: TicketmasterDiscoveryLocation
    let dateRange: TicketmasterDiscoveryDateRange?
    let genre: String?
  }

  private struct EventGroup: Identifiable {
    let id: String
    let title: String
    let events: [TicketmasterDiscoveryEvent]
  }

  let viewerID: UUID
  let eventRepository: any EventRepository
  let onOpenEvent: (CommunityEventSummary) -> Void

  @Environment(\.ticketmasterDiscoveryRepository) private var repository
  @State private var location = TicketmasterDiscoveryLocation.sanFrancisco
  @State private var dateRange: TicketmasterDiscoveryDateRange?
  @State private var genre: String?
  @State private var isShowingDateFilter = false
  @State private var events: [TicketmasterDiscoveryEvent] = []
  @State private var hasMore = false
  @State private var isLoading = false
  @State private var isLoadingMore = false
  @State private var resolvingEventID: String?
  @State private var errorMessage: String?

  private let genres = ["Alternative", "Country", "Hip-Hop/Rap", "Jazz", "Latin", "Pop", "R&B", "Rock"]

  var body: some View {
    LazyVStack(alignment: .leading, spacing: 20) {
      discoveryHeader
      filters

      if isLoading {
        loadingState
      } else if let errorMessage {
        EventFailureView(message: errorMessage) {
          Task { await load(reset: true) }
        }
      } else if events.isEmpty {
        EventEmptyView(
          systemImage: "ticket",
          title: "No concerts found",
          message: "Try another date, genre, or city."
        )
      } else {
        feedHeader
        eventFeed
      }

      attribution
    }
    .task(id: LoadRequest(location: location, dateRange: dateRange, genre: genre)) {
      await load(reset: true)
    }
    .sheet(isPresented: $isShowingDateFilter) {
      TicketmasterDiscoveryDateFilterSheet(
        dateRange: dateRange,
        onApply: { dateRange = $0 },
        onClear: { dateRange = nil }
      )
      .presentationDetents([.medium, .large])
    }
  }

  private var discoveryHeader: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("DISCOVER")
        .font(.caption.weight(.bold))
        .tracking(1.4)
        .foregroundStyle(TunedInDesign.accent)

      Menu {
        ForEach(TicketmasterDiscoveryLocation.featured) { option in
          Button {
            location = option
          } label: {
            if option == location {
              Label(option.displayName, systemImage: "checkmark")
            } else {
              Text(option.displayName)
            }
          }
        }
      } label: {
        HStack(spacing: 8) {
          Image(systemName: "location.fill")
            .font(.headline)
            .foregroundStyle(TunedInDesign.accent)
          Text(location.displayName)
            .font(.title.bold())
            .foregroundStyle(TunedInDesign.primaryText)
          Image(systemName: "chevron.down")
            .font(.caption.bold())
            .foregroundStyle(TunedInDesign.mutedText)
        }
      }
      .buttonStyle(.plain)
      .accessibilityHint("Changes the city used for Ticketmaster discovery")

      Text("Find a concert that fits your night.")
        .font(.subheadline)
        .foregroundStyle(TunedInDesign.mutedText)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var filters: some View {
    TicketmasterDiscoveryFilterBar(
      dateRange: $dateRange,
      genre: $genre,
      genres: genres,
      onSelectDates: {
        isShowingDateFilter = true
      }
    )
  }

  private var feedHeader: some View {
    HStack(alignment: .firstTextBaseline) {
      VStack(alignment: .leading, spacing: 3) {
        Text(feedTitle)
          .font(.title2.bold())
          .foregroundStyle(TunedInDesign.primaryText)
        Text(resultSummary)
          .font(.caption)
          .foregroundStyle(TunedInDesign.mutedText)
      }

      Spacer()

      if hasActiveFilters {
        Button("Reset") {
          dateRange = nil
          genre = nil
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(TunedInDesign.accent)
      }
    }
  }

  private var eventFeed: some View {
    LazyVStack(alignment: .leading, spacing: 22) {
      ForEach(eventGroups) { group in
        VStack(alignment: .leading, spacing: 10) {
          Text(group.title)
            .font(.caption.weight(.bold))
            .tracking(0.8)
            .foregroundStyle(TunedInDesign.mutedText)

          LazyVStack(spacing: 10) {
            ForEach(group.events) { event in
              eventButton(event)
                .onAppear {
                  guard event.id == events.last?.id, hasMore, !isLoadingMore else { return }
                  Task { await loadMore() }
                }
            }
          }
        }
      }

      if isLoadingMore {
        ProgressView("Loading more concerts")
          .frame(maxWidth: .infinity)
          .padding(.vertical, 12)
      }
    }
  }

  private var loadingState: some View {
    VStack(spacing: 12) {
      ForEach(0 ..< 5, id: \.self) { _ in
        TunedInSkeletonBlock(cornerRadius: TunedInDesign.mediumCornerRadius)
          .frame(height: 106)
      }
    }
    .accessibilityLabel("Loading Ticketmaster concerts")
  }

  private var attribution: some View {
    HStack(spacing: 5) {
      Image(systemName: "checkmark.seal")
      Text("Event discovery powered by Ticketmaster")
    }
    .font(.caption2.weight(.semibold))
    .foregroundStyle(TunedInDesign.mutedText)
    .frame(maxWidth: .infinity)
    .padding(.top, 4)
  }

  private func eventButton(_ event: TicketmasterDiscoveryEvent) -> some View {
    Button {
      Task { await open(event) }
    } label: {
      TicketmasterDiscoveryCard(
        event: event,
        isResolving: resolvingEventID == event.id
      )
    }
    .buttonStyle(TunedInPosterButtonStyle())
    .disabled(resolvingEventID != nil)
    .accessibilityLabel(
      "\(event.name), \(event.displayDate.formatted(date: .abbreviated, time: .shortened)), "
        + "\(event.venue.name), Ticketmaster"
    )
  }
}

private extension TicketmasterDiscoveryView {
  private var feedTitle: String {
    if let genre {
      return "\(genre) near \(location.city)"
    }
    return "Concerts near \(location.city)"
  }

  private var resultSummary: String {
    let suffix = events.count == 1 ? "concert" : "concerts"
    guard let dateRange else {
      return "\(events.count) \(suffix) · Next 30 days"
    }
    return "\(events.count) \(suffix) · \(dateRange.title)"
  }

  private var hasActiveFilters: Bool {
    dateRange != nil || genre != nil
  }

  private var eventGroups: [EventGroup] {
    let calendar = Calendar.current
    let grouped = Dictionary(grouping: events) {
      calendar.startOfDay(for: $0.displayDate)
    }
    return grouped.keys.sorted().map { day in
      EventGroup(
        id: String(day.timeIntervalSinceReferenceDate),
        title: dayTitle(day, calendar: calendar),
        events: grouped[day, default: []]
      )
    }
  }

  private func dayTitle(_ day: Date, calendar: Calendar) -> String {
    if calendar.isDateInToday(day) {
      return "TODAY"
    }
    if calendar.isDateInTomorrow(day) {
      return "TOMORROW"
    }
    return day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()).uppercased()
  }

  @MainActor
  private func load(reset: Bool) async {
    if reset {
      isLoading = true
      events = []
      errorMessage = nil
    }
    defer { isLoading = false }
    do {
      let page = try await repository.discover(
        location: location,
        dateRange: effectiveDateRange.interval(),
        genre: genre,
        page: 0
      )
      guard !Task.isCancelled else { return }
      events = page.events
      hasMore = page.hasMore
    } catch is CancellationError {
      return
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  @MainActor
  private func loadMore() async {
    guard hasMore, !isLoadingMore else { return }
    isLoadingMore = true
    defer { isLoadingMore = false }
    do {
      let nextPage = events.count / 20
      let page = try await repository.discover(
        location: location,
        dateRange: effectiveDateRange.interval(),
        genre: genre,
        page: nextPage
      )
      let existingIDs = Set(events.map(\.id))
      events.append(contentsOf: page.events.filter { !existingIDs.contains($0.id) })
      hasMore = page.hasMore
    } catch is CancellationError {
      return
    } catch {
      hasMore = false
    }
  }

  private var effectiveDateRange: TicketmasterDiscoveryDateRange {
    dateRange ?? .nextThirtyDays()
  }

  @MainActor
  private func open(_ event: TicketmasterDiscoveryEvent) async {
    resolvingEventID = event.id
    defer { resolvingEventID = nil }
    do {
      let eventID = try await repository.resolveEvent(id: event.id)
      let summary = try await eventRepository.eventDetail(id: eventID, viewerID: viewerID).summary
      onOpenEvent(summary)
    } catch {
      errorMessage = error.localizedDescription
    }
  }
}
