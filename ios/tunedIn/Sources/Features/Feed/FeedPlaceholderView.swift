import Observation
import SwiftUI

struct FriendsActivityFeedView: View {
  let viewerID: UUID
  let viewerUsername: String
  let concertRepository: any ConcertRepository
  let socialRepository: any SocialRepository

  @Environment(\.telemetry) private var telemetry

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
        VStack(alignment: .leading, spacing: 14) {
          feedHeader
          ForEach(0 ..< 4, id: \.self) { _ in
            HStack(alignment: .top, spacing: 11) {
              TunedInSkeletonBlock(cornerRadius: 21).frame(width: 42, height: 42)
              VStack(alignment: .leading, spacing: 9) {
                TunedInSkeletonBlock(cornerRadius: 5).frame(height: 16)
                TunedInSkeletonBlock(cornerRadius: 12).frame(height: 86)
              }
            }
            .padding(15)
          }
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 100)
      } else if let errorMessage = model.errorMessage, model.activities.isEmpty {
        ScrollView {
          VStack(alignment: .leading, spacing: 0) {
            feedHeader
            remoteChangesButton
            failureState(message: errorMessage)
          }
          .frame(minHeight: 540, alignment: .top)
          .padding(.horizontal, 20)
          .padding(.top, 18)
          .padding(.bottom, 100)
        }
        .refreshable {
          await model.refreshVisibleSlice()
        }
      } else {
        ScrollView {
          VStack(alignment: .leading, spacing: 0) {
            feedHeader
            remoteChangesButton
            if let errorMessage = model.errorMessage {
              Label(errorMessage, systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.orange)
                .padding(.bottom, 12)
            }
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
      let startedAt = ContinuousClock.now
      await model.loadInitial()
      let failure = model.errorMessage == nil ? nil : AppFailure.unexpected
      telemetry?.capture(
        .screenLoadCompleted,
        properties: [
          .screen: .string(TelemetryScreen.feed.rawValue),
          .outcome: .string(failure == nil ? TelemetryOutcome.succeeded.rawValue : TelemetryOutcome.failed.rawValue),
          .durationMilliseconds: .integer(startedAt.duration(to: .now).telemetryMilliseconds),
          .failureCategory: failure.map { .string(TelemetryFailureCategory($0).rawValue) } ?? .string("none")
        ]
      )
    }
    .task {
      for await _ in concertRepository.observeFriendsActivity() {
        model.markRemoteChangesAvailable()
      }
    }
  }

  @ViewBuilder
  private var remoteChangesButton: some View {
    if model.hasRemoteChanges {
      FeedRemoteChangesButton {
        Task { await model.refreshVisibleSlice() }
      }
      .padding(.bottom, 14)
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
      Text(model.activities.count == 1 ? "One moment from your circle" : "From your circle")
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(TunedInDesign.mutedText)

      LazyVStack(alignment: .leading, spacing: 18) {
        ForEach(activityGroups) { group in
          VStack(alignment: .leading, spacing: 9) {
            Text(group.title.uppercased())
              .font(.caption2.weight(.black))
              .tracking(0.8)
              .foregroundStyle(TunedInDesign.mutedText)
              .padding(.horizontal, 4)

            ForEach(group.activities) { activity in
              NavigationLink {
                ConcertDetailView(
                  concertID: activity.concertID,
                  viewerID: viewerID,
                  viewerUsername: viewerUsername,
                  concertRepository: concertRepository,
                  socialRepository: socialRepository
                )
              } label: {
                ActivityMomentCard(
                  activity: activity,
                  repository: concertRepository,
                  socialRepository: socialRepository
                )
              }
              .buttonStyle(.plain)
              .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
              .accessibilityLabel(activity.accessibilitySummary)
            }
          }
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

  private var activityGroups: [ActivityDayGroup] {
    let calendar = Calendar.current
    let grouped = Dictionary(grouping: model.activities) { activity in
      calendar.startOfDay(for: activity.occurredAt)
    }
    return grouped.keys.sorted(by: >).map { day in
      ActivityDayGroup(
        day: day,
        title: activityDayTitle(day, calendar: calendar),
        activities: grouped[day, default: []]
      )
    }
  }

  private func activityDayTitle(_ day: Date, calendar: Calendar) -> String {
    if calendar.isDateInToday(day) {
      return "Today"
    }
    if calendar.isDateInYesterday(day) {
      return "Yesterday"
    }
    return day.formatted(.dateTime.month(.wide).day())
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

private struct FeedRemoteChangesButton: View {
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 9) {
        Image(systemName: "arrow.down.circle.fill")
        Text("New activity")
          .fontWeight(.bold)
        Spacer()
        Text("Refresh")
          .font(.caption.weight(.semibold))
      }
      .font(.subheadline)
      .foregroundStyle(TunedInDesign.primaryText)
      .padding(.horizontal, 14)
      .padding(.vertical, 11)
      .background(
        TunedInDesign.accentTint,
        in: RoundedRectangle(cornerRadius: 15, style: .continuous)
      )
    }
    .buttonStyle(.plain)
    .accessibilityHint("Loads the latest activity from the server")
  }
}

private extension Duration {
  var telemetryMilliseconds: Int {
    let components = self.components
    return Int(components.seconds * 1_000 + components.attoseconds / 1_000_000_000_000_000)
  }
}

private struct ActivityMomentCard: View {
  let activity: FriendActivity
  let repository: any ConcertRepository
  let socialRepository: any SocialRepository

  var body: some View {
    VStack(alignment: .leading, spacing: 13) {
      HStack(alignment: .top, spacing: 11) {
        FeedActorAvatar(activity: activity, socialRepository: socialRepository)

        (Text(activity.actorDisplayName).fontWeight(.bold)
          + Text(" \(activity.feedActionTitle.lowercased())"))
          .font(.body)
          .foregroundStyle(TunedInDesign.primaryText)
          .fixedSize(horizontal: false, vertical: true)

        Spacer()

        Text(ConcertDisplay.relativeDate(activity.occurredAt))
          .font(.caption.weight(.semibold))
          .foregroundStyle(TunedInDesign.mutedText)
      }

      eventDetail
    }
    .padding(15)
    .background(TunedInDesign.cardBackground, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 20, style: .continuous)
        .strokeBorder(TunedInDesign.cardBorder.opacity(0.72))
    }
    .shadow(color: .black.opacity(0.05), radius: 10, y: 4)
    .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    .accessibilityElement(children: .combine)
  }

  @ViewBuilder
  private var eventDetail: some View {
    switch activity.eventKind {
    case .albumPhotoAdded:
      VStack(alignment: .leading, spacing: 9) {
        eventBadge
        if let photoID = activity.photoID, let objectPath = activity.photoObjectPath {
          ActivityPhotoPreview(
            activity: activity,
            photoID: photoID,
            objectPath: objectPath,
            repository: repository
          )
          .frame(height: 176)
          .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
        }
        Text(activity.primaryArtistName)
          .font(.headline)
          .foregroundStyle(TunedInDesign.primaryText)
      }

    case .setlistUpdated:
      setlistDetail

    case .concertUpdated where activity.changedFields.contains("setlist"):
      setlistDetail

    case .concertUpdated, .visibilityChanged:
      VStack(alignment: .leading, spacing: 9) {
        eventBadge
        Text(activity.primaryArtistName)
          .font(.headline)
          .foregroundStyle(TunedInDesign.primaryText)
        if activity.changedFields.isEmpty {
          Text("Concert details changed")
            .font(.subheadline)
            .foregroundStyle(TunedInDesign.mutedText)
        } else {
          Text(activity.changedFields.map(\.feedFieldTitle).joined(separator: " · "))
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(TunedInDesign.mutedText)
        }
      }

    case .commentAdded, .commentUpdated, .commentDeleted:
      HStack(spacing: 12) {
        Image(systemName: "text.bubble.fill")
          .font(.title2)
          .foregroundStyle(TunedInDesign.accent)
          .frame(width: 48, height: 48)
          .background(TunedInDesign.accentTint.opacity(0.72), in: Circle())
        VStack(alignment: .leading, spacing: 3) {
          eventBadge
          Text(activity.primaryArtistName)
            .font(.headline)
            .foregroundStyle(TunedInDesign.primaryText)
        }
      }

    default:
      HStack(spacing: 12) {
        VStack(alignment: .leading, spacing: 7) {
          eventBadge
          Text(activity.primaryArtistName)
            .font(.system(size: 19, weight: .bold, design: .serif))
            .foregroundStyle(TunedInDesign.primaryText)
          Label(activity.venueName, systemImage: "mappin.and.ellipse")
            .font(.caption)
            .foregroundStyle(TunedInDesign.mutedText)
          Text(ConcertDisplay.longDate(from: activity.concertDate))
            .font(.caption.weight(.semibold))
            .foregroundStyle(TunedInDesign.mutedText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        ConcertArtworkImage(artistName: activity.primaryArtistName)
          .frame(width: 78, height: 78)
          .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
      }
    }
  }

  private var setlistDetail: some View {
    VStack(alignment: .leading, spacing: 9) {
      eventBadge
      Text(activity.primaryArtistName)
        .font(.headline)
        .foregroundStyle(TunedInDesign.primaryText)
      ForEach(Array(activity.setlistPreview.prefix(3).enumerated()), id: \.offset) { index, song in
        HStack(spacing: 9) {
          Text("\(index + 1)")
            .font(.caption.weight(.black))
            .foregroundStyle(TunedInDesign.accent)
            .frame(width: 17, alignment: .leading)
          Text(song)
            .font(.subheadline)
            .foregroundStyle(TunedInDesign.primaryText)
            .lineLimit(1)
        }
      }
      if activity.setlistCount > activity.setlistPreview.count {
        Text("+ \(activity.setlistCount - activity.setlistPreview.count) more songs")
          .font(.caption.weight(.semibold))
          .foregroundStyle(TunedInDesign.mutedText)
      }
    }
  }

  private var eventBadge: some View {
    Label(activity.eventLabel, systemImage: activity.eventIcon)
      .font(.caption2.weight(.black))
      .foregroundStyle(TunedInDesign.accent)
  }
}

private struct ActivityPhotoPreview: View {
  let activity: FriendActivity
  let photoID: UUID
  let objectPath: String
  let repository: any ConcertRepository
  @State private var url: URL?

  var body: some View {
    Group {
      if let url {
        AsyncImage(url: url) { image in
          image.resizable().scaledToFill()
        } placeholder: {
          TunedInImagePlaceholder()
        }
      } else {
        TunedInImagePlaceholder()
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .clipped()
    .task(id: "\(activity.id)-\(activity.photoVersion)") {
      url = try? await repository.albumPhotoURL(
        photoID: photoID,
        objectPath: objectPath,
        version: activity.photoVersion
      )
    }
  }
}

private struct FeedActorAvatar: View {
  let activity: FriendActivity
  let socialRepository: any SocialRepository

  @State private var profile: SocialProfile?
  @State private var didFail = false

  var body: some View {
    Group {
      if let profile {
        ProfileAvatarView(profile: profile, size: 42)
      } else if didFail {
        Text(String(activity.actorDisplayName.prefix(1)).uppercased())
          .font(.subheadline.weight(.black))
          .foregroundStyle(TunedInDesign.actionForeground)
          .frame(width: 42, height: 42)
          .background(TunedInDesign.accentTint, in: Circle())
      } else {
        TunedInSkeletonBlock(cornerRadius: 21)
          .frame(width: 42, height: 42)
      }
    }
    .task(id: activity.actorID) {
      do {
        profile = try await socialRepository.profile(username: activity.actorUsername)
        didFail = profile == nil
      } catch {
        didFail = true
      }
    }
  }
}

private struct ActivityDayGroup: Identifiable {
  let day: Date
  let title: String
  let activities: [FriendActivity]
  var id: Date {
    day
  }
}

private extension FriendActivity {
  var feedActionTitle: String {
    switch eventKind {
    case .concertCreated: "Saved a new concert"
    case .concertUpdated where changedFields.contains("setlist"): "Updated the setlist"
    case .concertUpdated: "Updated concert details"
    case .setlistUpdated: "Updated the setlist"
    case .commentAdded: "Added a moment"
    case .commentUpdated: "Edited a moment"
    case .commentDeleted: "Removed a moment"
    case .albumPhotoAdded: "Added a photo"
    case .collaboratorTagged: "Added an editor"
    case .collaboratorRemoved: "Removed an editor"
    case .visibilityChanged: "Changed who can see a concert"
    case .ownershipTransferred: "Transferred a concert"
    }
  }

  var eventLabel: String {
    switch eventKind {
    case .concertCreated: "NEW CONCERT"
    case .concertUpdated where changedFields.contains("setlist"): "SETLIST"
    case .concertUpdated: "CONCERT UPDATE"
    case .setlistUpdated: "SETLIST"
    case .commentAdded, .commentUpdated, .commentDeleted: "MOMENT"
    case .albumPhotoAdded: "PHOTO"
    case .collaboratorTagged, .collaboratorRemoved: "PEOPLE"
    case .visibilityChanged: "SHARING"
    case .ownershipTransferred: "OWNERSHIP"
    }
  }

  var eventIcon: String {
    switch eventKind {
    case .concertCreated: "music.note"
    case .concertUpdated where changedFields.contains("setlist"): "list.number"
    case .concertUpdated: "pencil"
    case .setlistUpdated: "list.number"
    case .commentAdded, .commentUpdated, .commentDeleted: "text.bubble"
    case .albumPhotoAdded: "photo"
    case .collaboratorTagged, .collaboratorRemoved: "person.2"
    case .visibilityChanged: "eye"
    case .ownershipTransferred: "person.crop.circle.badge.checkmark"
    }
  }

  var accessibilitySummary: String {
    "\(actorDisplayName) \(feedActionTitle.lowercased()) for \(primaryArtistName) at \(venueName)"
  }
}

private extension String {
  var feedFieldTitle: String {
    switch self {
    case "artists": "Lineup"
    case "venue_name": "Venue"
    case "concert_date": "Date"
    case "city": "City"
    case "tour": "Tour"
    case "starts_at", "venue_time_zone": "Time"
    case "setlist": "Setlist"
    case "visibility": "Sharing"
    default: replacingOccurrences(of: "_", with: " ").capitalized
    }
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
  var hasRemoteChanges = false
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
      let refreshed = try await repository.friendsActivity(cursor: nil, policy: .refresh)
      activities = refreshed
      canLoadMore = refreshed.count == 30
      hasRemoteChanges = false
      errorMessage = nil
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  func markRemoteChangesAvailable() {
    hasRemoteChanges = true
  }

  func loadMore() async {
    guard let lastActivity = activities.last, !isLoadingMore else { return }
    isLoadingMore = true
    do {
      let older = try await repository.friendsActivity(
        cursor: FriendsActivityCursor(occurredAt: lastActivity.occurredAt, eventID: lastActivity.id),
        policy: .networkOnly
      )
      let existingIDs = Set(activities.map(\.id))
      activities.append(contentsOf: older.filter { !existingIDs.contains($0.id) })
      canLoadMore = older.count == 30
      errorMessage = nil
    } catch {
      errorMessage = error.localizedDescription
    }
    isLoadingMore = false
  }
}
