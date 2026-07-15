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
        VStack(alignment: .leading, spacing: 0) {
          feedHeader
          HStack(spacing: 10) {
            TunedInSkeletonBlock(cornerRadius: 5)
              .frame(width: 72, height: 14)
            TunedInSkeletonBlock(cornerRadius: 2)
              .frame(height: 1)
          }
          .padding(.bottom, 4)

          ForEach(0 ..< 4, id: \.self) { index in
            HStack(alignment: .top, spacing: 11) {
              TunedInSkeletonBlock(cornerRadius: 21).frame(width: 42, height: 42)
              VStack(alignment: .leading, spacing: 10) {
                TunedInSkeletonBlock(cornerRadius: 5)
                  .frame(width: index.isMultiple(of: 2) ? 190 : 230, height: 16)
                TunedInSkeletonBlock(cornerRadius: 16)
                  .frame(height: index.isMultiple(of: 2) ? 132 : 88)
              }
            }
            .padding(.vertical, 14)

            if index < 3 {
              Divider()
                .overlay(TunedInDesign.cardBorder.opacity(0.45))
                .padding(.leading, 53)
            }
          }
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, TunedInDesign.scrollContentBottomInset)
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
          .padding(.bottom, TunedInDesign.scrollContentBottomInset)
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
                .foregroundStyle(TunedInDesign.accent)
                .padding(.bottom, 12)
            }
            if model.activities.isEmpty {
              emptyState
                .frame(minHeight: 540)
            } else {
              ActivityStreamView(
                model: model,
                viewerID: viewerID,
                viewerUsername: viewerUsername,
                concertRepository: concertRepository,
                socialRepository: socialRepository
              )
            }
          }
          .padding(.horizontal, 20)
          .padding(.top, 18)
          .padding(.bottom, TunedInDesign.scrollContentBottomInset)
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
    VStack(alignment: .leading, spacing: 7) {
      Text("Your circle")
        .font(.caption2.weight(.bold))
        .foregroundStyle(TunedInDesign.accent)
        .textCase(.uppercase)
        .tracking(1.2)
      Text("Activity")
        .font(.largeTitle.weight(.bold))
        .foregroundStyle(TunedInDesign.primaryText)
      Text("Concerts and moments shared by your friends.")
        .font(.subheadline)
        .foregroundStyle(TunedInDesign.mutedText)
    }
    .padding(.bottom, 24)
  }

  private var emptyState: some View {
    VStack(spacing: 18) {
      Spacer()

      Image(systemName: "person.2.fill")
        .font(.system(.largeTitle, design: .rounded, weight: .medium))
        .foregroundStyle(TunedInDesign.accent)
        .frame(width: 72, height: 72)
        .background(TunedInDesign.raisedSurface, in: Circle())

      VStack(spacing: 6) {
        Text("Your circle is quiet")
          .font(.title3.weight(.bold))
          .foregroundStyle(TunedInDesign.primaryText)
        Text("Friends’ concerts, photos, and moments will appear here.")
          .font(.subheadline)
          .foregroundStyle(TunedInDesign.mutedText)
          .multilineTextAlignment(.center)
      }

      Text("Use the plus button to log a concert.")
        .font(.caption)
        .foregroundStyle(TunedInDesign.mutedText)

      Spacer()
    }
    .padding(.horizontal, 24)
  }

  private func failureState(message: String) -> some View {
    VStack(spacing: 18) {
      Spacer()

      Image(systemName: "wifi.exclamationmark")
        .font(.system(.largeTitle, design: .rounded, weight: .medium))
        .foregroundStyle(TunedInDesign.accent)
        .frame(width: 72, height: 72)
        .background(TunedInDesign.raisedSurface, in: Circle())

      VStack(spacing: 6) {
        Text("Couldn’t refresh activity")
          .font(.title3.weight(.bold))
          .foregroundStyle(TunedInDesign.primaryText)
        Text(message)
          .font(.subheadline)
          .foregroundStyle(TunedInDesign.mutedText)
          .multilineTextAlignment(.center)
      }

      Button("Try again") { Task { await model.loadInitial() } }
        .buttonStyle(.borderedProminent)
        .tint(TunedInDesign.accent)

      Spacer()
    }
    .padding(.horizontal, 24)
  }
}

private struct ActivityStreamView: View {
  let model: FriendsActivityFeedModel
  let viewerID: UUID
  let viewerUsername: String
  let concertRepository: any ConcertRepository
  let socialRepository: any SocialRepository

  var body: some View {
    VStack(alignment: .leading, spacing: 22) {
      LazyVStack(alignment: .leading, spacing: 26) {
        ForEach(activityGroups) { group in
          VStack(alignment: .leading, spacing: 0) {
            dayHeader(group)

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
              .contentShape(Rectangle())
              .accessibilityLabel(activity.accessibilitySummary)

              if activity.id != group.activities.last?.id {
                Divider()
                  .overlay(TunedInDesign.cardBorder.opacity(0.45))
                  .padding(.leading, 53)
              }
            }
          }
        }
      }

      loadMoreButton

      Label("Only activity from people you can still see.", systemImage: "eye")
        .font(.caption)
        .foregroundStyle(TunedInDesign.mutedText)
        .padding(.top, 2)
    }
  }

  private func dayHeader(_ group: ActivityDayGroup) -> some View {
    HStack(spacing: 10) {
      Text(group.title)
        .font(.subheadline.weight(.bold))
        .foregroundStyle(TunedInDesign.primaryText)

      Rectangle()
        .fill(TunedInDesign.cardBorder.opacity(0.55))
        .frame(height: 1)

      Text(group.activities.count.formatted())
        .font(.caption2.weight(.bold))
        .monospacedDigit()
        .foregroundStyle(TunedInDesign.mutedText)
        .accessibilityLabel(
          group.activities.count == 1 ? "One activity" : "\(group.activities.count) activities"
        )
    }
    .padding(.bottom, 2)
  }

  @ViewBuilder
  private var loadMoreButton: some View {
    if model.canLoadMore {
      Button {
        Task { await model.loadMore() }
      } label: {
        HStack(spacing: 8) {
          if model.isLoadingMore {
            ProgressView()
          } else {
            Image(systemName: "clock.arrow.circlepath")
          }
          Text(model.isLoadingMore ? "Finding earlier moments…" : "Show earlier moments")
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(TunedInDesign.primaryText)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 13)
        .background(TunedInDesign.raisedSurface, in: Capsule())
      }
      .buttonStyle(.plain)
      .disabled(model.isLoadingMore)
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
}

private struct FeedRemoteChangesButton: View {
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 9) {
        Image(systemName: "arrow.down")
          .fontWeight(.bold)
        Text("New activity")
          .fontWeight(.semibold)
        Spacer()
        Text("Refresh")
          .font(.caption.weight(.semibold))
      }
      .font(.subheadline)
      .foregroundStyle(TunedInDesign.primaryText)
      .padding(.horizontal, 15)
      .padding(.vertical, 12)
      .background(
        TunedInDesign.raisedSurface,
        in: Capsule()
      )
    }
    .buttonStyle(.plain)
    .accessibilityHint("Loads the latest activity from the server")
  }
}

private extension Duration {
  var telemetryMilliseconds: Int {
    let components = components
    return Int(components.seconds * 1000 + components.attoseconds / 1_000_000_000_000_000)
  }
}

private struct ActivityMomentCard: View {
  let activity: FriendActivity
  let repository: any ConcertRepository
  let socialRepository: any SocialRepository

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(alignment: .top, spacing: 11) {
        FeedActorAvatar(activity: activity, socialRepository: socialRepository)

        VStack(alignment: .leading, spacing: 4) {
          ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
              Text(activity.actorDisplayName)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(TunedInDesign.primaryText)
              Spacer(minLength: 6)
              relativeDate
            }

            VStack(alignment: .leading, spacing: 2) {
              Text(activity.actorDisplayName)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(TunedInDesign.primaryText)
              relativeDate
            }
          }

          Label(activity.feedActionTitle, systemImage: activity.eventIcon)
            .font(.caption)
            .foregroundStyle(TunedInDesign.mutedText)
            .fixedSize(horizontal: false, vertical: true)
        }
      }

      eventDetail
        .padding(.leading, 53)
    }
    .padding(.vertical, 14)
    .contentShape(Rectangle())
    .accessibilityElement(children: .combine)
  }

  private var relativeDate: some View {
    Text(ConcertDisplay.relativeDate(activity.occurredAt))
      .font(.caption)
      .foregroundStyle(TunedInDesign.mutedText)
      .fixedSize(horizontal: true, vertical: false)
  }

  @ViewBuilder
  private var eventDetail: some View {
    switch activity.eventKind {
    case .albumPhotoAdded:
      VStack(alignment: .leading, spacing: 11) {
        if let photoID = activity.photoID, let objectPath = activity.photoObjectPath {
          ActivityPhotoPreview(
            activity: activity,
            photoID: photoID,
            objectPath: objectPath,
            repository: repository
          )
          .frame(height: 190)
          .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        concertIdentity
      }

    case .setlistUpdated:
      setlistDetail

    case .concertUpdated where activity.changedFields.contains("setlist"):
      setlistDetail

    case .concertUpdated, .visibilityChanged:
      VStack(alignment: .leading, spacing: 7) {
        concertIdentity
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
      HStack(alignment: .top, spacing: 11) {
        Image(systemName: "quote.bubble.fill")
          .font(.body.weight(.semibold))
          .foregroundStyle(TunedInDesign.accent)
          .frame(width: 32, height: 32)
          .background(TunedInDesign.raisedSurface, in: Circle())
        concertIdentity
      }

    default:
      ZStack(alignment: .bottomLeading) {
        ConcertArtworkImage(artistName: activity.primaryArtistName)
          .frame(maxWidth: .infinity)
          .frame(height: 156)
          .clipped()

        LinearGradient(
          colors: [.clear, .black.opacity(0.76)],
          startPoint: .center,
          endPoint: .bottom
        )

        VStack(alignment: .leading, spacing: 4) {
          Text(activity.primaryArtistName)
            .font(.system(.title3, design: .serif, weight: .bold))
            .foregroundStyle(.white)
            .lineLimit(2)
          Text(activity.venueName)
            .font(.caption)
            .foregroundStyle(.white.opacity(0.86))
            .lineLimit(1)
          Text(ConcertDisplay.longDate(from: activity.concertDate))
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.white.opacity(0.74))
        }
        .padding(14)
      }
      .frame(maxWidth: .infinity)
      .frame(height: 156)
      .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
  }

  private var setlistDetail: some View {
    HStack(alignment: .top, spacing: 12) {
      Capsule()
        .fill(TunedInDesign.accent)
        .frame(width: 3)

      VStack(alignment: .leading, spacing: 9) {
        Text(activity.primaryArtistName)
          .font(.headline)
          .foregroundStyle(TunedInDesign.primaryText)
        ForEach(Array(activity.setlistPreview.prefix(3).enumerated()), id: \.offset) { index, song in
          HStack(alignment: .firstTextBaseline, spacing: 9) {
            Text("\(index + 1)")
              .font(.caption2.weight(.bold))
              .foregroundStyle(TunedInDesign.mutedText)
              .frame(width: 17, alignment: .leading)
            Text(song)
              .font(.subheadline)
              .foregroundStyle(TunedInDesign.primaryText)
              .lineLimit(2)
          }
        }
        if activity.setlistCount > activity.setlistPreview.count {
          Text("+ \(activity.setlistCount - activity.setlistPreview.count) more songs")
            .font(.caption.weight(.semibold))
            .foregroundStyle(TunedInDesign.mutedText)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  private var concertIdentity: some View {
    VStack(alignment: .leading, spacing: 3) {
      Text(activity.primaryArtistName)
        .font(.headline)
        .foregroundStyle(TunedInDesign.primaryText)
      Text(activity.venueName)
        .font(.caption)
        .foregroundStyle(TunedInDesign.mutedText)
        .lineLimit(2)
    }
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
        CachedRemoteImage(
          url: url,
          resource: .albumPhoto(photoID: photoID, version: activity.photoVersion)
        ) { phase in
          switch phase {
          case let .success(image):
            image.resizable().scaledToFill()
          case .failure:
            TunedInImagePlaceholder(failed: true)
          case .empty:
            TunedInImagePlaceholder()
          @unknown default:
            TunedInImagePlaceholder()
          }
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
