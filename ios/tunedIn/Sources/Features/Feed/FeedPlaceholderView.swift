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
    HStack(alignment: .lastTextBaseline) {
      VStack(alignment: .leading, spacing: 4) {
        Text("tunedIn")
          .font(.caption.weight(.black))
          .foregroundStyle(TunedInDesign.accent)
          .textCase(.uppercase)
        Text("From your people")
          .font(.system(size: 31, weight: .bold, design: .serif))
          .foregroundStyle(TunedInDesign.primaryText)
      }

      Spacer()

      Button {
        Task { await model.refreshVisibleSlice() }
      } label: {
        Image(systemName: "arrow.clockwise")
          .font(.subheadline.weight(.bold))
          .foregroundStyle(TunedInDesign.primaryText)
          .frame(width: 42, height: 42)
          .background(TunedInDesign.raisedSurface, in: Circle())
      }
      .buttonStyle(.plain)
      .accessibilityLabel("Refresh activity")
    }
    .padding(.bottom, 18)
  }

  private func activityStream(model: FriendsActivityFeedModel) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(model.activities.count == 1 ? "One thing worth knowing" : "What’s landing lately")
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(TunedInDesign.mutedText)

      LazyVStack(spacing: 16) {
        ForEach(Array(model.activities.enumerated()), id: \.element.id) { index, activity in
          NavigationLink {
            ConcertDetailView(
              concertID: activity.concertID,
              viewerID: viewerID,
              viewerUsername: viewerUsername,
              concertRepository: concertRepository,
              socialRepository: socialRepository
            )
          } label: {
            ActivityMomentCard(activity: activity, isFeatured: index == 0)
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
    VStack(alignment: .leading, spacing: 22) {
      Spacer()
      TunedInTicketCard {
        Label("THE ROOM IS QUIET", systemImage: "waveform")
          .font(.caption.weight(.bold))
          .foregroundStyle(.white.opacity(0.82))
        Text("No new nights\nfrom your circle.")
          .font(.system(size: 29, weight: .bold, design: .serif))
          .foregroundStyle(.white)
        Text("When your friends share a moment, it will feel at home here.")
          .font(.subheadline)
          .foregroundStyle(.white.opacity(0.86))
      }
      Text("Keep your own nights close. The orange plus is always there when something stays with you.")
        .font(.subheadline)
        .foregroundStyle(TunedInDesign.mutedText)
        .padding(.horizontal, 4)
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
  let isFeatured: Bool

  var body: some View {
    ZStack(alignment: .bottomLeading) {
      ConcertArtworkImage(artistName: activity.primaryArtistName)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay {
          LinearGradient(
            colors: [.clear, .black.opacity(0.18), .black.opacity(0.82)],
            startPoint: .top,
            endPoint: .bottom
          )
        }

      VStack(alignment: .leading, spacing: 10) {
        HStack(spacing: 7) {
          Text(activity.actorDisplayName)
            .font(.subheadline.weight(.bold))
          Text(activity.activityTitle)
            .font(.subheadline)
            .foregroundStyle(.white.opacity(0.82))
          Spacer()
          Text(ConcertDisplay.relativeDate(activity.occurredAt))
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white.opacity(0.72))
        }

        VStack(alignment: .leading, spacing: 3) {
          Text(activity.primaryArtistName)
            .font(.system(size: 35, weight: .bold, design: .serif))
            .foregroundStyle(.white)
            .lineLimit(2)
          Text(activity.venueName)
            .font(.headline)
            .foregroundStyle(.white.opacity(0.92))
        }

        Label("Open the night", systemImage: "arrow.up.right")
          .font(.caption.weight(.bold))
          .foregroundStyle(.white)
          .padding(.horizontal, 11)
          .padding(.vertical, 8)
          .background(.white.opacity(0.18), in: Capsule())
      }
      .padding(22)
    }
    .frame(maxWidth: .infinity)
    .frame(height: isFeatured ? 430 : 300)
    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 28, style: .continuous)
        .strokeBorder(.white.opacity(0.22))
    }
    .shadow(color: TunedInDesign.accent.opacity(0.18), radius: 24, y: 12)
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
