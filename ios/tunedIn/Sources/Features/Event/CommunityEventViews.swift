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
  let viewerID: UUID
  let repository: any EventRepository
  let onOpenEvent: (CommunityEventSummary) -> Void

  @State private var events: [CommunityEventSummary] = []
  @State private var isLoading = true
  @State private var errorMessage: String?

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
