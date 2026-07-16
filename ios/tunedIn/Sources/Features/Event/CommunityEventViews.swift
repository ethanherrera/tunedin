import SwiftUI

struct CommunityActivityFeedView: View {
  let viewerID: UUID
  let repository: any EventRepository
  let onOpenEvent: (CommunityEventSummary) -> Void

  @State private var activities: [EventActivity] = []
  @State private var isLoading = true
  @State private var errorMessage: String?

  var body: some View {
    ZStack {
      TunedInDesign.pageBackground.ignoresSafeArea()

      ScrollView {
        VStack(alignment: .leading, spacing: 22) {
          EventScreenHeader(
            eyebrow: "Your circle",
            title: "Feed",
            subtitle: "Plans before the show. Memories after it."
          )

          if isLoading {
            ForEach(0 ..< 3, id: \.self) { _ in
              TunedInSkeletonBlock(cornerRadius: TunedInDesign.cornerRadius)
                .frame(height: 150)
            }
          } else if let errorMessage {
            EventFailureView(message: errorMessage) { Task { await load() } }
          } else if activities.isEmpty {
            EventEmptyView(
              systemImage: "person.2.wave.2",
              title: "Your circle is quiet",
              message: "When friends make plans or share concert memories, they’ll appear here."
            )
          } else {
            LazyVStack(spacing: 14) {
              ForEach(activities) { activity in
                Button { onOpenEvent(activity.event) } label: {
                  CommunityActivityCard(activity: activity)
                }
                .buttonStyle(TunedInPosterButtonStyle())
              }
            }
          }
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, TunedInDesign.scrollContentBottomInset)
      }
      .refreshable { await load() }
    }
    .toolbar(.hidden, for: .navigationBar)
    .task { await load() }
  }

  @MainActor
  private func load() async {
    isLoading = activities.isEmpty
    defer { isLoading = false }
    do {
      activities = try await repository.activityFeed(viewerID: viewerID)
      errorMessage = nil
    } catch {
      errorMessage = error.localizedDescription
    }
  }
}

struct CommunityPlansView: View {
  private enum Presentation: String, CaseIterable {
    case list = "List"
    case calendar = "Calendar"
  }

  let viewerID: UUID
  let repository: any EventRepository
  let onOpenEvent: (CommunityEventSummary) -> Void

  @State private var events: [CommunityEventSummary] = []
  @State private var isLoading = true
  @State private var errorMessage: String?
  @State private var presentation = Presentation.list

  var body: some View {
    ZStack {
      TunedInDesign.pageBackground.ignoresSafeArea()

      ScrollView {
        VStack(alignment: .leading, spacing: 22) {
          EventScreenHeader(
            eyebrow: "Your calendar",
            title: "Plans",
            subtitle: "Every show you’re going to—and the friends joining you."
          )

          Picker("Plans view", selection: $presentation) {
            ForEach(Presentation.allCases, id: \.self) { option in
              Label(
                option.rawValue,
                systemImage: option == .list ? "list.bullet" : "calendar"
              )
              .tag(option)
            }
          }
          .pickerStyle(.segmented)

          if isLoading {
            ForEach(0 ..< 3, id: \.self) { _ in
              TunedInSkeletonBlock(cornerRadius: TunedInDesign.cornerRadius)
                .frame(height: 126)
            }
          } else if let errorMessage {
            EventFailureView(message: errorMessage) { Task { await load() } }
          } else if events.isEmpty {
            EventEmptyView(
              systemImage: "calendar.badge.plus",
              title: "No plans yet",
              message: "Find a concert and say you’re going. It will land here automatically."
            )
          } else {
            if presentation == .calendar, !upcoming.isEmpty {
              PlansCalendarOverview(events: upcoming, onOpenEvent: onOpenEvent)
            }
            eventSection(title: "Coming up", events: upcoming)
            eventSection(title: "Past shows", events: past)
          }
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, TunedInDesign.scrollContentBottomInset)
      }
      .refreshable { await load() }
    }
    .toolbar(.hidden, for: .navigationBar)
    .task { await load() }
  }

  @ViewBuilder
  private func eventSection(title: String, events: [CommunityEventSummary]) -> some View {
    if !events.isEmpty {
      VStack(alignment: .leading, spacing: 12) {
        Text(title)
          .font(.headline)
          .foregroundStyle(TunedInDesign.primaryText)

        ForEach(events) { event in
          Button { onOpenEvent(event) } label: {
            CommunityEventRow(event: event, showsSource: false)
          }
          .buttonStyle(TunedInPosterButtonStyle())
        }
      }
    }
  }

  private var upcoming: [CommunityEventSummary] {
    events.filter { $0.phase() != .memories }
  }

  private var past: [CommunityEventSummary] {
    events.filter { $0.phase() == .memories }
  }

  @MainActor
  private func load() async {
    isLoading = events.isEmpty
    defer { isLoading = false }
    do {
      events = try await repository.plans(viewerID: viewerID)
      errorMessage = nil
    } catch {
      errorMessage = error.localizedDescription
    }
  }
}

private struct PlansCalendarOverview: View {
  let events: [CommunityEventSummary]
  let onOpenEvent: (CommunityEventSummary) -> Void

  private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("Concert calendar")
        .font(.headline)
        .foregroundStyle(TunedInDesign.primaryText)

      ScrollView(.horizontal) {
        LazyHStack(alignment: .top, spacing: 12) {
          ForEach(months) { month in
            VStack(alignment: .leading, spacing: 12) {
              Text(month.title)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(TunedInDesign.primaryText)

              LazyVGrid(columns: columns, spacing: 7) {
                ForEach(Self.weekdaySymbols, id: \.self) { symbol in
                  Text(symbol)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(TunedInDesign.mutedText)
                    .frame(maxWidth: .infinity)
                }
                ForEach(0 ..< month.leadingEmptyDays, id: \.self) { _ in
                  Color.clear.frame(height: 32)
                }
                ForEach(1 ... month.dayCount, id: \.self) { day in
                  let dayEvents = month.eventsByDay[day] ?? []
                  Button {
                    if let event = dayEvents.first { onOpenEvent(event) }
                  } label: {
                    VStack(spacing: 2) {
                      Text("\(day)")
                        .font(.caption.weight(dayEvents.isEmpty ? .regular : .bold))
                      Circle()
                        .fill(dayEvents.isEmpty ? Color.clear : TunedInDesign.accent)
                        .frame(width: 4, height: 4)
                    }
                    .foregroundStyle(TunedInDesign.primaryText)
                    .frame(maxWidth: .infinity, minHeight: 32)
                    .background(
                      dayEvents.isEmpty ? Color.clear : TunedInDesign.accentTint,
                      in: RoundedRectangle(cornerRadius: 8)
                    )
                  }
                  .buttonStyle(.plain)
                  .disabled(dayEvents.isEmpty)
                  .accessibilityLabel(accessibilityLabel(day: day, events: dayEvents))
                }
              }
            }
            .padding(14)
            .frame(width: 290)
            .background(
              TunedInDesign.cardBackground,
              in: RoundedRectangle(cornerRadius: TunedInDesign.cornerRadius)
            )
            .overlay {
              RoundedRectangle(cornerRadius: TunedInDesign.cornerRadius)
                .strokeBorder(TunedInDesign.cardBorder)
            }
          }
        }
      }
      .scrollIndicators(.hidden)

      Text("Tap a highlighted date to open that concert. Your social context stays in the agenda below.")
        .font(.caption)
        .foregroundStyle(TunedInDesign.mutedText)
    }
  }

  private var months: [PlansCalendarMonth] {
    Dictionary(grouping: events) { event in
      Self.calendar.dateComponents([.year, .month], from: event.eventDate)
    }
    .compactMap { components, events in
      guard let monthStart = Self.calendar.date(from: components) else { return nil }
      return PlansCalendarMonth(monthStart: monthStart, events: events)
    }
    .sorted(by: { $0.monthStart < $1.monthStart })
  }

  private func accessibilityLabel(day: Int, events: [CommunityEventSummary]) -> String {
    guard !events.isEmpty else { return "Day \(day), no concerts" }
    return "Day \(day), " + events.map(\.title).joined(separator: ", ")
  }

  private static var calendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
    return calendar
  }

  private static let weekdaySymbols = Calendar(identifier: .gregorian).veryShortWeekdaySymbols
}

private struct PlansCalendarMonth: Identifiable {
  let monthStart: Date
  let events: [CommunityEventSummary]

  var id: Date { monthStart }

  var title: String {
    monthStart.formatted(.dateTime.month(.wide).year())
  }

  var dayCount: Int {
    Self.calendar.range(of: .day, in: .month, for: monthStart)?.count ?? 30
  }

  var leadingEmptyDays: Int {
    max(0, Self.calendar.component(.weekday, from: monthStart) - 1)
  }

  var eventsByDay: [Int: [CommunityEventSummary]] {
    Dictionary(grouping: events) { Self.calendar.component(.day, from: $0.eventDate) }
  }

  private static var calendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
    return calendar
  }
}
