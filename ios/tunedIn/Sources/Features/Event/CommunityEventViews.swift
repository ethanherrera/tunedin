import SwiftUI

enum CommunityProfileCollection: CaseIterable, Hashable {
  case posts
  case concerts

  var title: String {
    switch self {
    case .posts: "Posts"
    case .concerts: "Concerts"
    }
  }

  var systemImage: String {
    switch self {
    case .posts: "square.grid.3x3"
    case .concerts: "music.note.list"
    }
  }
}

struct CommunityProfileHistorySection: View {
  let history: CommunityProfileHistory
  let eventRepository: any EventRepository
  let postRepository: any PostRepository
  let onOpenEvent: (CommunityEventSummary, UUID?) -> Void

  @State private var selectedCollection = CommunityProfileCollection.posts
  @State private var expandedConcertCollection: ProfileConcertCollection?
  @Namespace private var selectionNamespace
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  init(
    history: CommunityProfileHistory,
    eventRepository: any EventRepository,
    postRepository: any PostRepository,
    onOpenEvent: @escaping (CommunityEventSummary, UUID?) -> Void
  ) {
    self.history = history
    self.eventRepository = eventRepository
    self.postRepository = postRepository
    self.onOpenEvent = onOpenEvent
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack(spacing: 0) {
        ForEach(CommunityProfileCollection.allCases, id: \.self) { collection in
          Button { selectedCollection = collection } label: {
            HStack(spacing: 7) {
              Image(systemName: collection.systemImage)
                .font(.caption.weight(.bold))
              Text(collection.title)
                .font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(TunedInDesign.primaryText)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .overlay(alignment: .bottom) {
              if selectedCollection == collection {
                Capsule()
                  .fill(TunedInDesign.accent)
                  .frame(height: 3)
                  .matchedGeometryEffect(id: "profile-collection", in: selectionNamespace)
              }
            }
          }
          .buttonStyle(.plain)
          .accessibilityLabel(collection.title)
          .accessibilityAddTraits(selectedCollection == collection ? .isSelected : [])
        }
      }

      Divider().overlay(TunedInDesign.cardBorder)

      switch selectedCollection {
      case .posts:
        if history.posts.isEmpty {
          emptyState("No posts yet.")
        } else {
          LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 3),
            spacing: 2
          ) {
            ForEach(history.posts) { entry in
              Button { onOpenEvent(entry.event, entry.post.id) } label: {
                ProfilePostGridTile(
                  entry: entry,
                  postRepository: postRepository
                )
              }
              .buttonStyle(TunedInPosterButtonStyle())
              .accessibilityLabel(
                "Open post about \(entry.event.title), "
                  + CommunityEventDateText.compactDate(entry.event.eventDate)
              )
              .accessibilityValue(
                entry.post.score.map {
                  "Score \($0.formatted(.number.precision(.fractionLength(1)))), "
                    + CommunityEventScoreBand(score: $0).accessibilityDescription
                } ?? "Not scored"
              )
            }
          }
          .padding(.horizontal, -20)
        }
      case .concerts:
        VStack(alignment: .leading, spacing: 24) {
          concertSection(
            title: "Upcoming",
            events: upcomingEvents,
            collection: .upcoming,
            emptyMessage: "No upcoming concerts shared."
          )
          concertSection(
            title: "Past",
            events: pastEvents,
            collection: .past,
            emptyMessage: "No past concerts shared."
          )
        }
      }
    }
    .animation(TunedInMotion.selection(reduceMotion: reduceMotion), value: selectedCollection)
    .fullScreenCover(item: $expandedConcertCollection) { collection in
      ProfileConcertDirectoryView(
        title: collection.title,
        events: collection == .upcoming ? upcomingEvents : pastEvents,
        eventRepository: eventRepository,
        onOpenEvent: { event in
          expandedConcertCollection = nil
          onOpenEvent(event, nil)
        },
        onDismiss: { expandedConcertCollection = nil }
      )
    }
  }

  private func concertSection(
    title: String,
    events: [CommunityEventSummary],
    collection: ProfileConcertCollection,
    emptyMessage: String
  ) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(spacing: 7) {
        Text(title)
          .font(.headline)
          .foregroundStyle(TunedInDesign.primaryText)
        Text("\(events.count)")
          .font(.caption2.weight(.bold))
          .foregroundStyle(TunedInDesign.mutedText)
          .padding(.horizontal, 6)
          .padding(.vertical, 3)
          .background(TunedInDesign.raisedSurface, in: Capsule())
      }

      if events.isEmpty {
        emptyState(emptyMessage)
      } else {
        ForEach(events.prefix(3)) { event in
          Button { onOpenEvent(event, nil) } label: {
            CommunityEventRow(
              event: event,
              showsSource: false,
              eventRepository: eventRepository
            )
          }
          .buttonStyle(TunedInPosterButtonStyle())
        }
        if events.count > 3 {
          Button { expandedConcertCollection = collection } label: {
            HStack {
              Text("View all \(events.count) \(collection == .upcoming ? "upcoming" : "past")")
                .font(.subheadline.weight(.bold))
              Spacer()
              Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
            }
            .foregroundStyle(TunedInDesign.accent)
            .padding(.vertical, 8)
          }
          .buttonStyle(.plain)
        }
      }
    }
  }

  private var upcomingEvents: [CommunityEventSummary] {
    history.going.sorted { $0.eventDate < $1.eventDate }
  }

  private var pastEvents: [CommunityEventSummary] {
    history.went.sorted { $0.eventDate > $1.eventDate }
  }

  private func emptyState(_ message: String) -> some View {
    Text(message)
      .font(.subheadline)
      .foregroundStyle(TunedInDesign.mutedText)
      .frame(maxWidth: .infinity, minHeight: 96, alignment: .center)
  }
}

private enum ProfileConcertCollection: String, Identifiable {
  case upcoming
  case past

  var id: String {
    rawValue
  }

  var title: String {
    self == .upcoming ? "Upcoming concerts" : "Past concerts"
  }
}

private struct ProfileConcertDirectoryView: View {
  let title: String
  let events: [CommunityEventSummary]
  let eventRepository: any EventRepository
  let onOpenEvent: (CommunityEventSummary) -> Void
  let onDismiss: () -> Void

  var body: some View {
    ZStack {
      TunedInDesign.pageBackground.ignoresSafeArea()
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 8) {
          Text(title)
            .font(.largeTitle.weight(.bold))
            .foregroundStyle(TunedInDesign.primaryText)
            .padding(.bottom, 8)
          ForEach(events) { event in
            Button { onOpenEvent(event) } label: {
              CommunityEventRow(
                event: event,
                showsSource: false,
                eventRepository: eventRepository
              )
            }
            .buttonStyle(TunedInPosterButtonStyle())
          }
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 24)
      }
    }
    .safeAreaInset(edge: .bottom, spacing: 0) {
      TunedInPersistentControlRegion {
        TunedInSubscreenBackBar(title: title, action: onDismiss)
          .padding(.horizontal, TunedInDesign.bottomControlHorizontalInset)
          .padding(.top, 8)
          .padding(.bottom, TunedInDesign.bottomControlInset)
      }
    }
  }
}

private struct ProfilePostGridTile: View {
  let entry: EventProfilePost
  let postRepository: any PostRepository

  var body: some View {
    GeometryReader { proxy in
      ZStack(alignment: .bottomLeading) {
        PostMediaPreview(
          postID: entry.post.id,
          reportedPhotoCount: entry.post.photoCount,
          postRepository: postRepository,
          height: proxy.size.width,
          maximumVisiblePhotos: 1
        )

        LinearGradient(
          colors: [.clear, .black.opacity(0.76)],
          startPoint: .center,
          endPoint: .bottom
        )

        VStack(alignment: .leading, spacing: 2) {
          if let score = entry.post.score {
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
  let postRepository: any PostRepository
  let onOpenActivity: (EventActivity) -> Void

  @State private var activities: [EventActivity] = []
  @State private var isLoading = true
  @State private var errorMessage: String?

  var body: some View {
    ZStack {
      TunedInDesign.pageBackground.ignoresSafeArea()

      ScrollView {
        VStack(alignment: .leading, spacing: 0) {
          Text("Home")
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
                CommunityActivityCard(
                  activity: activity,
                  eventRepository: repository,
                  postRepository: postRepository,
                  onOpenActivity: { onOpenActivity(activity) }
                )
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
  let viewerID: UUID
  let currentUsername: String
  let repository: any EventRepository
  let socialRepository: any SocialRepository
  let onOpenEvent: (CommunityEventSummary) -> Void

  @State private var events: [CommunityEventSummary] = []
  @State private var invitations: [EventInvitation] = []
  @State private var isLoading = true
  @State private var errorMessage: String?
  @State private var respondingInvitationID: UUID?

  var body: some View {
    ZStack {
      TunedInDesign.pageBackground.ignoresSafeArea()

      ScrollView {
        VStack(alignment: .leading, spacing: 18) {
          Text("Calendar")
            .font(.largeTitle.weight(.bold))
            .foregroundStyle(TunedInDesign.primaryText)

          if isLoading {
            ForEach(0 ..< 3, id: \.self) { _ in
              TunedInSkeletonBlock(cornerRadius: TunedInDesign.cornerRadius)
                .frame(height: 126)
            }
          } else if let errorMessage {
            EventFailureView(message: errorMessage) { Task { await load() } }
          } else {
            CommunityCalendarView(
              viewerID: viewerID,
              currentUsername: currentUsername,
              personalEvents: events,
              invitations: invitations,
              repository: repository,
              socialRepository: socialRepository,
              onOpenEvent: onOpenEvent,
              onRespondInvitation: { invitation, response in
                Task { await respond(to: invitation, with: response) }
              }
            )
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
