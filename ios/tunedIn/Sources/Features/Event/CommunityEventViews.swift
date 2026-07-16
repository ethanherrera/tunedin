import SwiftUI

struct CommunityProfileHistorySection: View {
  private enum Page: String, CaseIterable {
    case diaries = "Posts"
    case going = "Going"
    case went = "Went"
  }

  let history: CommunityProfileHistory
  let concertRepository: any ConcertRepository
  let onOpenEvent: (CommunityEventSummary, UUID?) -> Void

  @State private var selectedPage = Page.diaries
  @Namespace private var selectionNamespace
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack(spacing: 0) {
        ForEach(Page.allCases, id: \.self) { page in
          Button { selectedPage = page } label: {
            VStack(spacing: 4) {
              Text("\(count(for: page))")
                .font(.title3.weight(.bold))
              Text(page.rawValue)
                .font(.caption.weight(.semibold))
            }
            .foregroundStyle(TunedInDesign.primaryText)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .overlay(alignment: .bottom) {
              if selectedPage == page {
                Capsule()
                  .fill(TunedInDesign.accent)
                  .frame(height: 3)
                  .matchedGeometryEffect(id: "profile-history-page", in: selectionNamespace)
              }
            }
          }
          .buttonStyle(.plain)
          .accessibilityAddTraits(selectedPage == page ? .isSelected : [])
        }
      }

      Divider().overlay(TunedInDesign.cardBorder)

      switch selectedPage {
      case .diaries:
        if history.diaries.isEmpty {
          emptyState("No posts yet.")
        } else {
          LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 3),
            spacing: 2
          ) {
            ForEach(history.diaries) { entry in
              Button { onOpenEvent(entry.event, entry.diary.id) } label: {
                ProfileDiaryGridTile(
                  entry: entry,
                  concertRepository: concertRepository
                )
              }
              .buttonStyle(TunedInPosterButtonStyle())
              .accessibilityLabel(
                "Open post about \(entry.event.title), "
                  + CommunityEventDateText.compactDate(entry.event.eventDate)
              )
              .accessibilityValue(
                entry.diary.score.map {
                  "Score \($0.formatted(.number.precision(.fractionLength(1)))), "
                    + CommunityEventScoreBand(score: $0).accessibilityDescription
                } ?? "Not scored"
              )
            }
          }
          .padding(.horizontal, -20)
        }
      case .going:
        if history.going.isEmpty {
          emptyState("No upcoming plans shared yet.")
        } else {
          ForEach(history.going) { event in
            Button { onOpenEvent(event, nil) } label: {
              CommunityEventRow(event: event, showsSource: false)
            }
            .buttonStyle(TunedInPosterButtonStyle())
          }
        }
      case .went:
        if history.went.isEmpty {
          emptyState("No attended concerts shared yet.")
        } else {
          ForEach(history.went) { event in
            Button { onOpenEvent(event, nil) } label: {
              CommunityEventRow(event: event, showsSource: false)
            }
            .buttonStyle(TunedInPosterButtonStyle())
          }
        }
      }
    }
    .animation(TunedInMotion.selection(reduceMotion: reduceMotion), value: selectedPage)
  }

  private func count(for page: Page) -> Int {
    switch page {
    case .diaries: history.diaries.count
    case .going: history.going.count
    case .went: history.went.count
    }
  }

  private func emptyState(_ message: String) -> some View {
    Text(message)
      .font(.subheadline)
      .foregroundStyle(TunedInDesign.mutedText)
      .frame(maxWidth: .infinity, minHeight: 96, alignment: .center)
  }
}

private struct ProfileDiaryGridTile: View {
  let entry: EventProfileDiary
  let concertRepository: any ConcertRepository

  var body: some View {
    GeometryReader { proxy in
      ZStack(alignment: .bottomLeading) {
        DiaryMediaPreview(
          diaryID: entry.diary.id,
          reportedPhotoCount: entry.diary.photoCount,
          concertRepository: concertRepository,
          height: proxy.size.width,
          maximumVisiblePhotos: 1
        )

        LinearGradient(
          colors: [.clear, .black.opacity(0.76)],
          startPoint: .center,
          endPoint: .bottom
        )

        VStack(alignment: .leading, spacing: 2) {
          if let score = entry.diary.score {
            CommunityEventScoreBadge(score: score, size: .compact)
          }
          Text(entry.event.title)
            .font(.caption2.weight(.semibold))
            .lineLimit(2)
          Text(CommunityEventDateText.compactDate(entry.event.eventDate))
            .font(.caption2)
            .foregroundStyle(.white.opacity(0.86))
            .lineLimit(1)
        }
        .foregroundStyle(.white)
        .padding(8)
      }
      .frame(width: proxy.size.width, height: proxy.size.width)
      .clipped()
    }
    .aspectRatio(1, contentMode: .fit)
  }
}

struct CommunityActivityFeedView: View {
  let viewerID: UUID
  let repository: any EventRepository
  let concertRepository: any ConcertRepository
  let onOpenActivity: (EventActivity) -> Void

  @State private var activities: [EventActivity] = []
  @State private var isLoading = true
  @State private var errorMessage: String?

  var body: some View {
    ZStack {
      TunedInDesign.pageBackground.ignoresSafeArea()

      ScrollView {
        VStack(alignment: .leading, spacing: 0) {
          Text("Feed")
            .font(.largeTitle.weight(.bold))
            .foregroundStyle(TunedInDesign.primaryText)
            .padding(.horizontal, 18)
            .padding(.bottom, 20)

          if isLoading {
            ForEach(0 ..< 3, id: \.self) { _ in
              TunedInSkeletonBlock(cornerRadius: 0)
                .frame(height: 280)
            }
          } else if let errorMessage {
            EventFailureView(message: errorMessage) { Task { await load() } }
          } else if activities.isEmpty {
            EventEmptyView(
              systemImage: "person.2.wave.2",
              title: "Your circle is quiet",
              message: "When friends make plans or share concert posts, they’ll appear here."
            )
          } else {
            LazyVStack(spacing: 20) {
              ForEach(activities) { activity in
                Button { onOpenActivity(activity) } label: {
                  CommunityActivityCard(
                    activity: activity,
                    concertRepository: concertRepository
                  )
                }
                .buttonStyle(TunedInPosterButtonStyle())
              }
            }
          }
        }
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
  @State private var invitations: [EventInvitation] = []
  @State private var isLoading = true
  @State private var errorMessage: String?
  @State private var presentation = Presentation.list
  @State private var respondingInvitationID: UUID?

  var body: some View {
    ZStack {
      TunedInDesign.pageBackground.ignoresSafeArea()

      ScrollView {
        VStack(alignment: .leading, spacing: 18) {
          Text("Plans")
            .font(.largeTitle.weight(.bold))
            .foregroundStyle(TunedInDesign.primaryText)

          if !invitations.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
              Text("Invited by friends")
                .font(.headline)
                .foregroundStyle(TunedInDesign.primaryText)

              ForEach(invitations) { invitation in
                EventInvitationCard(
                  invitation: invitation,
                  isResponding: respondingInvitationID == invitation.id,
                  onOpen: { onOpenEvent(invitation.event) },
                  onAccept: { Task { await respond(to: invitation, with: .accepted) } },
                  onDecline: { Task { await respond(to: invitation, with: .declined) } }
                )
              }
            }
          }

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
    isLoading = events.isEmpty && invitations.isEmpty
    defer { isLoading = false }
    do {
      events = try await repository.plans(viewerID: viewerID)
      if repository.capabilities.contains(.invitations) {
        invitations = try await repository.pendingInvitations(viewerID: viewerID)
      } else {
        invitations = []
      }
      errorMessage = nil
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  @MainActor
  private func respond(to invitation: EventInvitation, with response: EventInvitationResponse) async {
    respondingInvitationID = invitation.id
    defer { respondingInvitationID = nil }
    do {
      try await repository.respondToInvitation(
        invitationID: invitation.id,
        viewerID: viewerID,
        response: response,
        audience: .friends
      )
      await load()
    } catch {
      errorMessage = error.localizedDescription
    }
  }
}

private struct EventInvitationCard: View {
  let invitation: EventInvitation
  let isResponding: Bool
  let onOpen: () -> Void
  let onAccept: () -> Void
  let onDecline: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(spacing: 10) {
        ProfileAvatarView(profile: invitation.sender, size: 42)
        VStack(alignment: .leading, spacing: 3) {
          Text("\(invitation.sender.displayName) invited you")
            .font(.subheadline.weight(.bold))
            .foregroundStyle(TunedInDesign.primaryText)
          Text(invitation.createdAt, style: .relative)
            .font(.caption)
            .foregroundStyle(TunedInDesign.mutedText)
        }
      }

      Button(action: onOpen) {
        CommunityEventRow(event: invitation.event, showsSource: false)
      }
      .buttonStyle(TunedInPosterButtonStyle())

      HStack(spacing: 10) {
        Button("Not this time", action: onDecline)
          .buttonStyle(.bordered)
        Button("I’m going", action: onAccept)
          .buttonStyle(.borderedProminent)
          .tint(TunedInDesign.accent)
      }
      .disabled(isResponding)
    }
    .padding(14)
    .background(TunedInDesign.cardBackground, in: RoundedRectangle(cornerRadius: TunedInDesign.cornerRadius))
    .overlay {
      RoundedRectangle(cornerRadius: TunedInDesign.cornerRadius)
        .strokeBorder(TunedInDesign.cardBorder.opacity(0.55))
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
