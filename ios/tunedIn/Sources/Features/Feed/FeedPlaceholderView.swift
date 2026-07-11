import Observation
import SwiftUI

struct FriendsActivityFeedView: View {
  let viewerID: UUID
  let viewerUsername: String
  let concertRepository: any ConcertRepository
  let socialRepository: any SocialRepository

  @State private var model: FriendsActivityFeedModel

  init(
    viewerID: UUID,
    viewerUsername: String,
    concertRepository: any ConcertRepository,
    socialRepository: any SocialRepository
  ) {
    self.viewerID = viewerID
    self.viewerUsername = viewerUsername
    self.concertRepository = concertRepository
    self.socialRepository = socialRepository
    _model = State(initialValue: FriendsActivityFeedModel(repository: concertRepository))
  }

  var body: some View {
    @Bindable var model = model

    ZStack {
      TunedInDesign.pageBackground
        .ignoresSafeArea()

      if model.isLoading, model.activities.isEmpty {
        VStack(alignment: .leading, spacing: 0) {
          feedHeader
          Spacer()
          ProgressView("Finding the good noise…")
            .foregroundStyle(TunedInDesign.mutedText)
            .frame(maxWidth: .infinity)
          Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 100)
      } else if let errorMessage = model.errorMessage {
        VStack(alignment: .leading, spacing: 0) {
          feedHeader
          failureState(message: errorMessage)
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 100)
      } else {
        ScrollView {
          VStack(alignment: .leading, spacing: 0) {
            feedHeader
            if model.activities.isEmpty {
              emptyState
                .frame(minHeight: 540)
            } else {
              activityStream(model: model)
            }
          }
          .padding(.horizontal, 20)
          .padding(.top, 18)
          .padding(.bottom, 112)
        }
        .refreshable {
          await model.refreshVisibleSlice()
        }
      }
    }
    .toolbar(.hidden, for: .navigationBar)
    .task {
      await model.loadInitial()
    }
    .task {
      for await _ in concertRepository.observeFriendsActivity() {
        await model.refreshVisibleSlice()
      }
    }
  }

  private var feedHeader: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text("tunedIn")
        .font(.caption.weight(.black))
        .foregroundStyle(TunedInDesign.accent)
        .textCase(.uppercase)
      Text("Activity")
        .font(.system(size: 31, weight: .bold, design: .serif))
        .foregroundStyle(TunedInDesign.primaryText)
    }
    .padding(.bottom, 18)
  }

  private func activityStream(model: FriendsActivityFeedModel) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(model.activities.count == 1 ? "One thing worth knowing" : "What’s landing lately")
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(TunedInDesign.mutedText)

      LazyVStack(spacing: 10) {
        ForEach(model.activities) { activity in
          NavigationLink {
            ConcertDetailView(
              concertID: activity.concertID,
              viewerID: viewerID,
              viewerUsername: viewerUsername,
              concertRepository: concertRepository,
              socialRepository: socialRepository
            )
          } label: {
            ActivityMomentCard(activity: activity)
          }
          .buttonStyle(.plain)
        }
      }

      if model.canLoadMore {
        Button {
          Task { await model.loadMore() }
        } label: {
          HStack(spacing: 8) {
            if model.isLoadingMore {
              ProgressView()
            }
            Text(model.isLoadingMore ? "Finding earlier moments…" : "Show earlier moments")
          }
          .font(.subheadline.weight(.bold))
          .foregroundStyle(TunedInDesign.primaryText)
          .frame(maxWidth: .infinity)
          .padding(.vertical, 14)
          .background(TunedInDesign.raisedSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(model.isLoadingMore)
      }

      HStack(spacing: 10) {
        Image(systemName: "eye.fill")
          .foregroundStyle(TunedInDesign.accent)
        Text("Only activity from people you can still see.")
          .font(.caption)
          .foregroundStyle(TunedInDesign.mutedText)
      }
      .padding(.horizontal, 4)
    }
  }

  private var emptyState: some View {
    VStack(spacing: 16) {
      Spacer()
      ContentUnavailableView {
        Label("No activity yet", systemImage: "person.2")
      } description: {
        Text("Friends’ concerts will appear here.")
      }
      Text("Use the plus button to log a concert.")
        .font(.subheadline)
        .foregroundStyle(TunedInDesign.mutedText)
      Spacer()
    }
  }

  private func failureState(message: String) -> some View {
    VStack(spacing: 16) {
      Spacer()
      ContentUnavailableView {
        Label("Couldn’t refresh the room", systemImage: "exclamationmark.triangle")
      } description: {
        Text(message)
      } actions: {
        Button("Try again") { Task { await model.loadInitial() } }
      }
      Spacer()
    }
  }
}

private struct ActivityMomentCard: View {
  let activity: FriendActivity

  var body: some View {
    ZStack(alignment: .bottomLeading) {
      ConcertArtworkImage(artistName: activity.primaryArtistName)
        .frame(maxWidth: .infinity)
        .frame(height: 152)
        .overlay {
          LinearGradient(
            colors: [.black.opacity(0.3), .clear, .black.opacity(0.82)],
            startPoint: .top,
            endPoint: .bottom
          )
        }

      VStack(alignment: .leading, spacing: 0) {
        HStack(spacing: 7) {
          Text(activity.actorDisplayName)
            .font(.caption.weight(.bold))
          Text(activity.activityTitle)
            .font(.caption)
            .foregroundStyle(.white.opacity(0.82))
          Spacer()
          Text(ConcertDisplay.relativeDate(activity.occurredAt))
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white.opacity(0.72))
        }

        Spacer(minLength: 0)

        VStack(alignment: .leading, spacing: 3) {
          Text(activity.primaryArtistName)
            .font(.system(size: 24, weight: .bold, design: .serif))
            .foregroundStyle(.white)
            .lineLimit(1)
          Text([activity.venueName, ConcertDisplay.longDate(from: activity.concertDate)]
            .joined(separator: " · "))
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white.opacity(0.92))
            .lineLimit(1)
        }
      }
      .padding(16)
    }
    .frame(maxWidth: .infinity)
    .frame(height: 152)
    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 20, style: .continuous)
        .strokeBorder(.white.opacity(0.22))
    }
    .accessibilityElement(children: .combine)
  }
}

@MainActor
@Observable
private final class FriendsActivityFeedModel {
  let repository: any ConcertRepository
  var activities: [FriendActivity] = []
  var isLoading = false
  var isLoadingMore = false
  var canLoadMore = false
  var errorMessage: String?

  init(repository: any ConcertRepository) {
    self.repository = repository
  }

  func loadInitial() async {
    guard !isLoading else { return }
    isLoading = true
    errorMessage = nil
    do {
      activities = try await repository.friendsActivity(cursor: nil)
      canLoadMore = activities.count == 30
    } catch {
      errorMessage = error.localizedDescription
    }
    isLoading = false
  }

  func refreshVisibleSlice() async {
    do {
      let refreshed = try await repository.friendsActivity(cursor: nil)
      activities = refreshed
      canLoadMore = refreshed.count == 30
      errorMessage = nil
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  func loadMore() async {
    guard let lastActivity = activities.last, !isLoadingMore else { return }
    isLoadingMore = true
    do {
      let older = try await repository.friendsActivity(
        cursor: FriendsActivityCursor(occurredAt: lastActivity.occurredAt, eventID: lastActivity.id)
      )
      activities.append(contentsOf: older)
      canLoadMore = older.count == 30
      errorMessage = nil
    } catch {
      errorMessage = error.localizedDescription
    }
    isLoadingMore = false
  }
}
