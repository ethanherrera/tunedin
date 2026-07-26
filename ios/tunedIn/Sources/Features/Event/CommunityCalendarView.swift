import SwiftUI

struct CommunityCalendarView: View {
  private enum Scope: String, CaseIterable { case yours = "Your calendar", friends = "Friends" }
  enum PersonalState { case going, went, invited }

  let viewerID: UUID
  let currentUsername: String
  let personalEvents: [CommunityEventSummary]
  let invitations: [EventInvitation]
  let repository: any EventRepository
  let socialRepository: any SocialRepository
  let onOpenEvent: (CommunityEventSummary) -> Void
  let onRespondInvitation: (EventInvitation, EventInvitationResponse) -> Void

  @State private var scope: Scope = .yours
  @State private var selectedDay: Date?
  @State private var allFriends: [FriendCalendarEvent] = []
  @State private var selectedFriend: SocialProfile?
  @State private var selectedFriendEvents: [CommunityEventSummary] = []
  @State private var friends: [SocialProfile] = []
  @State private var isPickingFriend = false
  @State private var isShowingInvitations = false

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      Picker("Calendar", selection: $scope) {
        ForEach(Scope.allCases, id: \.self) { Text($0.rawValue).tag($0) }
      }
      .pickerStyle(.segmented)
      .onChange(of: scope) { _, _ in selectedDay = nil }

      if scope == .friends { friendsHeader }
      if scope == .yours, !invitations.isEmpty { invitationsStrip }

      CalendarMonths(
        entries: currentEntries,
        selectedDay: $selectedDay,
        style: scope == .friends && selectedFriend == nil ? .heat : .status
      )

      agenda
    }
    .task { await loadFriendsCalendar() }
    .sheet(isPresented: $isPickingFriend) { friendPicker }
    .fullScreenCover(isPresented: $isShowingInvitations) { invitationsScreen }
  }

  private var friendsHeader: some View {
    VStack(alignment: .leading, spacing: 9) {
      Button {
        isPickingFriend = true
      } label: {
        HStack(spacing: 9) {
          if let selectedFriend { ProfileAvatarView(profile: selectedFriend, size: 28) }
          Text(selectedFriend?.displayName ?? "All friends")
            .font(.headline)
          Image(systemName: "chevron.up.chevron.down")
            .font(.caption.weight(.bold))
          Spacer()
        }
        .foregroundStyle(TunedInDesign.primaryText)
        .padding(.horizontal, 13)
        .padding(.vertical, 10)
        .background(TunedInDesign.cardBackground, in: Capsule())
        .overlay { Capsule().strokeBorder(TunedInDesign.cardBorder) }
      }
      .buttonStyle(.plain)

      if selectedFriend == nil {
        HStack(spacing: 8) {
          Text("Friends activity")
          Circle().fill(.blue).frame(width: 8, height: 8)
          Circle().fill(.purple).frame(width: 11, height: 11)
          Circle().fill(.red).frame(width: 14, height: 14)
          Text("low to high")
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(TunedInDesign.mutedText)
      }
    }
  }

  private var invitationsStrip: some View {
    Button { isShowingInvitations = true } label: {
      HStack(spacing: 10) {
        Image(systemName: "envelope.badge.fill").foregroundStyle(TunedInDesign.accent)
        Text("\(invitations.count) concert invitation\(invitations.count == 1 ? "" : "s")")
          .font(.subheadline.weight(.semibold))
        Spacer()
        Text("Review").font(.subheadline.weight(.semibold))
        Image(systemName: "chevron.right").font(.caption.weight(.bold))
      }
      .foregroundStyle(TunedInDesign.primaryText)
      .padding(13)
      .background(TunedInDesign.cardBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
      .overlay { RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(TunedInDesign.cardBorder) }
    }
    .buttonStyle(.plain)
  }

  @ViewBuilder private var agenda: some View {
    let entries = selectedEntries
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Text(selectedDay == nil
          ? "Coming up"
          : selectedDay!.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
          .font(.title3.weight(.bold))
        Spacer()
        if selectedDay != nil {
          Button { withAnimation { selectedDay = nil } } label: {
            Text("Show All")
              .font(.caption.weight(.semibold))
          }
          .buttonStyle(.bordered)
        }
      }
      if entries.isEmpty {
        Text(selectedDay == nil ? "No upcoming concerts yet." : "No concerts on this day.")
          .font(.subheadline).foregroundStyle(TunedInDesign.mutedText)
      } else {
        ForEach(entries) { entry in
          Button { onOpenEvent(entry.event) } label: {
            AgendaRow(entry: entry)
          }
            .buttonStyle(TunedInPosterButtonStyle())
        }
      }
    }
  }

  private var currentEntries: [CalendarEntry] {
    if scope == .yours {
      return personalEvents.map { event in
        CalendarEntry(
          event: event,
          state: event.currentUserAttendance == .went ? .went : .going,
          friends: []
        )
      }
        + invitations.map { CalendarEntry(event: $0.event, state: .invited, friends: []) }
    }
    if selectedFriend != nil {
      return selectedFriendEvents.map {
        CalendarEntry(event: $0, state: $0.phase() == .memories ? .went : .going, friends: [])
      }
    }
    return allFriends.map { item in
      CalendarEntry(
        event: item.event,
        state: item.event.phase() == .memories ? .went : .going,
        friends: item.friends
      )
    }
  }

  private var selectedEntries: [CalendarEntry] {
    let calendar = Calendar.current
    if let selectedDay {
      return currentEntries.filter { calendar.isDate($0.event.startsAt, inSameDayAs: selectedDay) }
    }
    return currentEntries.filter { $0.event.startsAt >= .now && $0.state != .invited }
      .sorted { $0.event.startsAt < $1.event.startsAt }
  }

  private var friendPicker: some View {
    NavigationStack {
      CalendarFriendPicker(
        friends: friends,
        selectedFriend: selectedFriend,
        onDismiss: { isPickingFriend = false },
        onSelectAll: {
          selectedFriend = nil
          selectedFriendEvents = []
          isPickingFriend = false
        },
        onSelectFriend: { friend in
          selectedFriend = friend
          isPickingFriend = false
          Task { await loadSelectedFriend(friend) }
        }
      )
      .toolbar(.hidden, for: .navigationBar)
    }
  }

  private var invitationsScreen: some View {
    NavigationStack {
      List(invitations) { invitation in
        VStack(alignment: .leading, spacing: 10) {
          Text("\(invitation.sender.displayName) invited you").font(.headline)
          Button { onOpenEvent(invitation.event); isShowingInvitations = false } label: {
            CommunityEventRow(event: invitation.event, showsSource: false, eventRepository: repository)
          }
          HStack {
            Button("Not now") { onRespondInvitation(invitation, .declined) }.buttonStyle(.bordered)
            Button("I’m going") { onRespondInvitation(invitation, .accepted) }.buttonStyle(.borderedProminent)
          }
        }
      }
      .toolbar(.hidden, for: .navigationBar)
      .safeAreaInset(edge: .bottom, spacing: 0) {
        TunedInPersistentControlRegion {
          TunedInSubscreenBackBar(title: "Invitations") {
            isShowingInvitations = false
          }
          .padding(.horizontal, TunedInDesign.bottomControlHorizontalInset)
          .padding(.top, 8)
          .padding(.bottom, TunedInDesign.bottomControlInset)
        }
      }
      .tunedInEdgeSwipeBack { isShowingInvitations = false }
    }
  }

  @MainActor private func loadFriendsCalendar() async {
    async let calendar = repository.friendCalendar(viewerID: viewerID)
    async let social = socialRepository.friends(username: currentUsername, policy: .refresh)
    allFriends = (try? await calendar) ?? []
    friends = (try? await social) ?? []
  }

  @MainActor private func loadSelectedFriend(_ friend: SocialProfile) async {
    let history = try? await repository.profileHistory(profileID: friend.id, viewerID: viewerID)
    selectedFriendEvents = (history?.going ?? []) + (history?.went ?? [])
  }
}

private struct CalendarEntry: Identifiable {
  let event: CommunityEventSummary
  let state: CommunityCalendarView.PersonalState
  let friends: [EventFriendPreview]
  var id: UUID { event.id }
}

private struct CalendarFriendPicker: View {
  let friends: [SocialProfile]
  let selectedFriend: SocialProfile?
  let onDismiss: () -> Void
  let onSelectAll: () -> Void
  let onSelectFriend: (SocialProfile) -> Void

  @State private var query = ""

  var body: some View {
    ZStack {
      TunedInDesign.pageBackground.ignoresSafeArea()

      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          TunedInGlassSearchField(text: $query, prompt: "Search friends")

          LazyVStack(spacing: 10) {
            Button(action: onSelectAll) {
              CalendarAllFriendsRow(isSelected: selectedFriend == nil)
            }
            .buttonStyle(.plain)

            if filteredFriends.isEmpty {
              ContentUnavailableView(
                "No matching friends",
                systemImage: "magnifyingglass",
                description: Text("Try a different name or @username.")
              )
              .frame(maxWidth: .infinity)
              .padding(.top, 44)
            } else {
              ForEach(filteredFriends) { friend in
                Button { onSelectFriend(friend) } label: {
                  CalendarFriendPickerRow(
                    profile: friend,
                    isSelected: selectedFriend?.id == friend.id
                  )
                }
                .buttonStyle(.plain)
              }
            }
          }
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 32)
      }
    }
    .safeAreaInset(edge: .bottom, spacing: 0) {
      TunedInPersistentControlRegion {
        TunedInSubscreenBackBar(title: "Friends", action: onDismiss)
          .padding(.horizontal, TunedInDesign.bottomControlHorizontalInset)
          .padding(.top, 8)
          .padding(.bottom, TunedInDesign.bottomControlInset)
      }
    }
    .tunedInEdgeSwipeBack(action: onDismiss)
  }

  private var filteredFriends: [SocialProfile] {
    let normalizedQuery = ProfileInput.normalizedSearchQuery(query)
    guard !normalizedQuery.isEmpty else { return friends }

    return friends.filter { profile in
      profile.displayName.localizedCaseInsensitiveContains(normalizedQuery)
        || profile.username.localizedCaseInsensitiveContains(normalizedQuery)
    }
  }
}

private struct CalendarAllFriendsRow: View {
  let isSelected: Bool

  var body: some View {
    HStack(spacing: 13) {
      Image(systemName: "person.2.fill")
        .font(.title3.weight(.semibold))
        .foregroundStyle(TunedInDesign.actionForeground)
        .frame(width: 48, height: 48)
        .background(TunedInDesign.accent, in: Circle())
      VStack(alignment: .leading, spacing: 3) {
        Text("All friends")
          .font(.headline)
          .foregroundStyle(TunedInDesign.primaryText)
        Text("See everyone’s concert activity")
          .font(.subheadline)
          .foregroundStyle(TunedInDesign.mutedText)
      }
      Spacer(minLength: 0)
      if isSelected { Image(systemName: "checkmark.circle.fill").foregroundStyle(TunedInDesign.accent) }
    }
    .padding(13)
    .background(
      TunedInDesign.cardBackground,
      in: RoundedRectangle(cornerRadius: TunedInDesign.mediumCornerRadius, style: .continuous)
    )
  }
}

private struct CalendarFriendPickerRow: View {
  let profile: SocialProfile
  let isSelected: Bool

  var body: some View {
    HStack(spacing: 13) {
      ProfileAvatarView(profile: profile, size: 48)
      VStack(alignment: .leading, spacing: 3) {
        Text(profile.displayName)
          .font(.headline)
          .foregroundStyle(TunedInDesign.primaryText)
        Text("@\(profile.username)")
          .font(.subheadline)
          .foregroundStyle(TunedInDesign.mutedText)
      }
      Spacer(minLength: 0)
      if isSelected { Image(systemName: "checkmark.circle.fill").foregroundStyle(TunedInDesign.accent) }
    }
    .padding(13)
    .background(
      TunedInDesign.cardBackground,
      in: RoundedRectangle(cornerRadius: TunedInDesign.mediumCornerRadius, style: .continuous)
    )
    .accessibilityElement(children: .combine)
  }
}

private struct AgendaRow: View {
  let entry: CalendarEntry

  var body: some View {
    let time = CommunityEventDateText.time(for: entry.event)
    HStack(spacing: 12) {
      AgendaDateTile(date: entry.event.eventDate)
      VStack(alignment: .leading, spacing: 3) {
        Text(entry.event.title)
          .font(.subheadline.weight(.bold))
          .foregroundStyle(TunedInDesign.primaryText)
          .lineLimit(1)
        if entry.event.title != entry.event.headlinerName {
          Text(entry.event.headlinerName)
            .font(.caption.weight(.medium))
            .foregroundStyle(TunedInDesign.primaryText)
            .lineLimit(1)
        }
        Text("\(entry.event.venueName) · \(time)")
          .font(.caption).foregroundStyle(TunedInDesign.mutedText).lineLimit(1)
        if !entry.friends.isEmpty {
          AvatarStack(friends: entry.friends)
        } else {
          Text(entry.state == .invited ? "Invited" : (entry.state == .went ? "Went" : "Going"))
            .font(.caption.weight(.semibold))
            .foregroundStyle(TunedInDesign.accent)
        }
      }
      Spacer()
      Image(systemName: "chevron.right")
        .font(.caption.weight(.bold))
        .foregroundStyle(TunedInDesign.mutedText)
    }
    .padding(10).background(TunedInDesign.cardBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
  }
}

private struct AgendaDateTile: View {
  let date: Date

  var body: some View {
    VStack(spacing: 1) {
      Text(CommunityEventDateText.month(date))
        .font(.caption2.weight(.bold))
        .textCase(.uppercase)
        .foregroundStyle(TunedInDesign.accent)
      Text(CommunityEventDateText.day(date))
        .font(.title3.weight(.bold))
        .foregroundStyle(TunedInDesign.primaryText)
    }
    .frame(width: 52, height: 52)
    .background(TunedInDesign.raisedSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
  }
}

private struct AvatarStack: View {
  let friends: [EventFriendPreview]
  var body: some View {
    HStack(spacing: -7) {
      ForEach(friends.prefix(3)) {
        ProfileAvatarView(profile: $0.profile, size: 20)
          .overlay(Circle().stroke(TunedInDesign.cardBackground, lineWidth: 1.5))
      }
      if friends.count > 3 {
        Text("+\(friends.count - 3)")
          .font(.caption2.weight(.bold))
          .foregroundStyle(TunedInDesign.mutedText)
          .padding(.leading, 10)
      }
    }
  }
}

private struct CalendarMonths: View {
  enum Style { case heat, status }
  let entries: [CalendarEntry]
  @Binding var selectedDay: Date?
  let style: Style
  private let columns = Array(repeating: GridItem(.flexible(), spacing: 3), count: 7)
  private var calendar: Calendar { Calendar.current }
  private var currentMonth: Date {
    calendar.date(from: calendar.dateComponents([.year, .month], from: .now)) ?? .now
  }
  private var months: [Date] {
    (-6 ... 12).compactMap { calendar.date(byAdding: .month, value: $0, to: currentMonth) }
  }
  var body: some View {
    ScrollViewReader { proxy in
      ScrollView {
        LazyVStack(spacing: 20) {
          ForEach(months, id: \.self) { month in
            monthView(month).id(month)
          }
        }
        .padding(.vertical, 2)
      }
      .frame(height: 290)
      .scrollIndicators(.hidden)
      .onAppear { proxy.scrollTo(currentMonth, anchor: .top) }
    }
  }
  private func monthView(_ month: Date) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(month.formatted(.dateTime.month(.wide).year()))
        .font(.headline)
        .foregroundStyle(TunedInDesign.primaryText)
      LazyVGrid(columns: columns, spacing: 7) {
        ForEach(calendar.veryShortWeekdaySymbols, id: \.self) { symbol in
          Text(symbol)
            .font(.caption2.weight(.bold))
            .foregroundStyle(TunedInDesign.mutedText)
            .frame(maxWidth: .infinity)
        }
        ForEach(0 ..< leadingDays(month), id: \.self) { _ in Color.clear.frame(height: 36) }
        ForEach(1 ... dayCount(month), id: \.self) { day in dayButton(day, month: month) }
      }
    }
  }
  private func dayButton(_ day: Int, month: Date) -> some View {
    let date = calendar.date(bySetting: .day, value: day, of: month) ?? month
    let matches = entries.filter { calendar.isDate($0.event.eventDate, inSameDayAs: date) }
    let friendCount = Set(matches.flatMap(\.friends).map(\.profile.id)).count
    let selected = selectedDay.map { calendar.isDate($0, inSameDayAs: date) } ?? false
    return Button { withAnimation(.snappy) { selectedDay = selected ? nil : date } } label: {
      VStack(spacing: 3) {
        Text("\(day)").font(.caption.weight(matches.isEmpty ? .regular : .bold))
        let diameter = min(16, CGFloat(5 + friendCount * 3))
        Circle()
          .fill(dotColor(matches: matches, friendCount: friendCount))
          .frame(width: diameter, height: diameter)
      }
      .foregroundStyle(TunedInDesign.primaryText).frame(maxWidth: .infinity, minHeight: 38)
      .background(
        selected ? TunedInDesign.accentTint : Color.clear,
        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
      )
    }
    .buttonStyle(.plain)
    .accessibilityLabel("\(date.formatted(date: .complete, time: .omitted)), \(matches.count) concerts")
  }
  private func dotColor(matches: [CalendarEntry], friendCount: Int) -> Color {
    guard !matches.isEmpty else { return .clear }
    if style == .heat { return friendCount >= 4 ? .red : (friendCount >= 2 ? .purple : .blue) }
    if matches.contains(where: { $0.state == .invited }) && !matches.contains(where: { $0.state == .going }) {
      return .orange
    }
    return matches.contains(where: { $0.state == .went }) && !matches.contains(where: { $0.state == .going })
      ? .secondary
      : TunedInDesign.accent
  }
  private func leadingDays(_ month: Date) -> Int {
    max(0, calendar.component(.weekday, from: month) - calendar.firstWeekday)
  }

  private func dayCount(_ month: Date) -> Int {
    calendar.range(of: .day, in: .month, for: month)?.count ?? 30
  }
}
