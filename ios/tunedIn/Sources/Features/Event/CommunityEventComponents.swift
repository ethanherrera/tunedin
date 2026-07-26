import SwiftUI

struct ConcertPreviewCard: View {
  enum Style: Equatable {
    case plain
    case card
  }

  let event: CommunityEventSummary
  let showsSource: Bool
  let eventRepository: (any EventRepository)?
  let style: Style
  let statusText: String?
  let friends: [EventFriendPreview]?

  private static let cardHeight: CGFloat = 112
  private static let thumbnailWidth: CGFloat = 78
  private static let thumbnailHeight: CGFloat = 78

  init(
    event: CommunityEventSummary,
    showsSource: Bool,
    eventRepository: (any EventRepository)? = nil,
    style: Style = .plain,
    statusText: String? = nil,
    friends: [EventFriendPreview]? = nil
  ) {
    self.event = event
    self.showsSource = showsSource
    self.eventRepository = eventRepository
    self.style = style
    self.statusText = statusText
    self.friends = friends
  }

  var body: some View {
    HStack(spacing: 10) {
      thumbnail

      VStack(alignment: .leading, spacing: 3) {
        Text(event.headlinerName)
          .font(.headline)
          .foregroundStyle(TunedInDesign.primaryText)
          .lineLimit(1)
        if event.title != event.headlinerName {
          Text(event.title)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(TunedInDesign.primaryText)
            .lineLimit(1)
        }
        timeLine
        locationLine
        statusLine
        if showsSource {
          Text(event.sourceLabel)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(TunedInDesign.mutedText)
            .lineLimit(1)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      Image(systemName: "chevron.right")
        .font(.caption.weight(.bold))
        .foregroundStyle(TunedInDesign.mutedText)
    }
    .frame(maxWidth: .infinity)
    .frame(height: Self.cardHeight, alignment: .center)
    .padding(.horizontal, style == .card ? 8 : 0)
    .background {
      if style == .card {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
          .fill(TunedInDesign.cardBackground)
      }
    }
    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    .contentShape(Rectangle())
  }

  private var thumbnail: some View {
    ZStack(alignment: .topLeading) {
      if event.cover != nil {
        CommunityEventCoverImage(event: event, repository: eventRepository)
      } else {
        EventDateTile(date: event.eventDate)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .background(TunedInDesign.raisedSurface)
      }

      if event.cover != nil {
        EventDatePill(date: event.eventDate)
          .padding(7)
      }
    }
    .frame(width: Self.thumbnailWidth, height: Self.thumbnailHeight)
    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    .accessibilityHidden(true)
  }

  private var locationLine: some View {
    Text("\(event.venueName) · \(event.areaName)")
      .lineLimit(1)
      .truncationMode(.tail)
    .font(.subheadline)
    .foregroundStyle(TunedInDesign.mutedText)
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var timeLine: some View {
    Text(CommunityEventDateText.time(for: event))
      .font(.caption.weight(.semibold))
      .foregroundStyle(TunedInDesign.mutedText)
      .fixedSize(horizontal: true, vertical: false)
      .lineLimit(1)
  }

  @ViewBuilder
  private var statusLine: some View {
    let eventFriends = friends ?? event.friendPreviews
    if let statusText {
      Text(statusText)
        .font(.caption.weight(.semibold))
        .foregroundStyle(TunedInDesign.accent)
        .lineLimit(1)
    } else {
      HStack(spacing: 8) {
        switch event.phase() {
        case .cancelled:
          Label("Cancelled", systemImage: "xmark.circle.fill")
        case .postponed:
          Label("Postponed", systemImage: "clock.badge.exclamationmark")
        case .upcoming, .memories:
          if event.currentUserAttendance != nil {
            Label(event.phase() == .memories ? "Went" : "Going", systemImage: "checkmark.circle.fill")
          }
        }
        if !eventFriends.isEmpty {
          Label(
            "\(eventFriends.count) friend\(eventFriends.count == 1 ? "" : "s")",
            systemImage: "person.2.fill"
          )
        }
      }
      .font(.caption.weight(.semibold))
      .foregroundStyle(TunedInDesign.accent)
      .lineLimit(1)
    }
  }
}

struct CommunityActivityCard: View {
  let activity: EventActivity
  let eventRepository: any EventRepository
  let postRepository: any PostRepository
  let onOpenActivity: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(spacing: 10) {
        SocialProfileButton(profile: activity.actor) {
          ProfileAvatarView(profile: activity.actor, size: 42)
        }
        VStack(alignment: .leading, spacing: 2) {
          SocialProfileButton(profile: activity.actor) {
            Text(activity.actor.displayName)
              .font(.subheadline.weight(.bold))
              .foregroundStyle(TunedInDesign.primaryText)
          }
          Text(activity.message)
            .font(.caption)
            .foregroundStyle(TunedInDesign.mutedText)
            .lineLimit(2)
        }
        Spacer()
        Text(activity.occurredAt, style: .relative)
          .font(.caption2)
          .foregroundStyle(TunedInDesign.mutedText)
      }
      .padding(.horizontal, 18)
      .padding(.bottom, 12)

      Button(action: onOpenActivity) {
        activityContent
      }
      .buttonStyle(TunedInPosterButtonStyle())
      .accessibilityLabel("Open \(activity.event.title)")

      Divider()
        .overlay(TunedInDesign.cardBorder)
        .padding(.top, 18)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  @ViewBuilder
  private var activityContent: some View {
    if let post = activity.post {
      VStack(alignment: .leading, spacing: 0) {
        if post.photoCount > 0 {
          PostMediaPreview(
            postID: post.id,
            reportedPhotoCount: post.photoCount,
            postRepository: postRepository,
            height: 280
          )
        }

        VStack(alignment: .leading, spacing: 9) {
          HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
              Text(activity.event.title)
                .font(.headline)
                .foregroundStyle(TunedInDesign.primaryText)
              if activity.event.title != activity.event.headlinerName {
                Text(activity.event.headlinerName)
                  .font(.subheadline.weight(.medium))
                  .foregroundStyle(TunedInDesign.primaryText)
                  .lineLimit(1)
              }
              Text("\(activity.event.venueName) · \(activity.event.eventDate, style: .date)")
                .font(.caption)
                .foregroundStyle(TunedInDesign.mutedText)
            }
            Spacer()
            if let score = post.score {
              CommunityEventScoreBadge(score: score, size: .large)
            }
          }

          if let note = post.note {
            Text(note)
              .font(.subheadline)
              .foregroundStyle(TunedInDesign.primaryText)
              .lineLimit(3)
          }

          PostEngagementLine(post: post)
        }
        .padding(.horizontal, 18)
        .padding(.top, post.photoCount > 0 ? 12 : 2)
      }
    } else {
      if activity.event.cover != nil {
        ZStack(alignment: .bottomLeading) {
          CommunityEventCoverImage(event: activity.event, repository: eventRepository)
            .frame(maxWidth: .infinity)
            .frame(height: 210)

          LinearGradient(
            colors: [.clear, .black.opacity(0.84)],
            startPoint: .center,
            endPoint: .bottom
          )

          VStack(alignment: .leading, spacing: 5) {
            EventDatePill(date: activity.event.eventDate)
            Text(activity.event.title)
              .font(.title3.weight(.bold))
              .foregroundStyle(.white)
            if activity.event.title != activity.event.headlinerName {
              Text(activity.event.headlinerName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(1)
            }
            Text("\(activity.event.venueName) · \(activity.event.areaName)")
              .font(.subheadline)
              .foregroundStyle(.white.opacity(0.86))
            if !activity.event.friendPreviews.isEmpty {
              Label(
                "\(activity.event.friendPreviews.count) in your circle",
                systemImage: "person.2.fill"
              )
              .font(.caption.weight(.semibold))
              .foregroundStyle(.white.opacity(0.86))
            }
          }
          .padding(16)
        }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .padding(.horizontal, 18)
      } else {
        HStack(spacing: 14) {
          EventDateTile(date: activity.event.eventDate)
          VStack(alignment: .leading, spacing: 4) {
            Text(activity.event.title)
              .font(.headline)
              .foregroundStyle(TunedInDesign.primaryText)
            if activity.event.title != activity.event.headlinerName {
              Text(activity.event.headlinerName)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(TunedInDesign.primaryText)
                .lineLimit(1)
            }
            Text("\(activity.event.venueName) · \(activity.event.areaName)")
              .font(.subheadline)
              .foregroundStyle(TunedInDesign.mutedText)
            if !activity.event.friendPreviews.isEmpty {
              Label(
                "\(activity.event.friendPreviews.count) in your circle",
                systemImage: "person.2.fill"
              )
              .font(.caption.weight(.semibold))
              .foregroundStyle(TunedInDesign.mutedText)
            }
          }
          Spacer(minLength: 0)
          Image(systemName: "chevron.right")
            .font(.caption.weight(.bold))
            .foregroundStyle(TunedInDesign.mutedText)
        }
        .padding(.horizontal, 18)
      }
    }
  }
}

struct CommunityEventCoverImage: View {
  let event: CommunityEventSummary
  let repository: (any EventRepository)?

  @State private var signedURL: URL?
  @State private var didFail = false

  var body: some View {
    Group {
      if let cover = event.cover, let url = cover.remoteURL ?? signedURL {
        CachedRemoteImage(
          url: url,
          resource: .eventCover(eventID: event.id, version: cover.version)
        ) { phase in
          switch phase {
          case let .success(image):
            image.resizable().scaledToFill()
          case .empty:
            fallback.overlay { ProgressView().tint(.white) }
          case .failure:
            fallback
          @unknown default:
            fallback
          }
        }
      } else {
        fallback
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .clipped()
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("Cover for \(event.title)")
    .task(id: coverLoadID) {
      signedURL = nil
      didFail = false
      guard
        let cover = event.cover,
        cover.remoteURL == nil,
        let objectPath = cover.objectPath,
        let repository
      else { return }
      do {
        signedURL = try await repository.eventCoverURL(
          eventID: event.id,
          objectPath: objectPath,
          version: cover.version
        )
      } catch {
        didFail = true
      }
    }
  }

  private var coverLoadID: String {
    guard let cover = event.cover else { return "\(event.id)-fallback" }
    return "\(event.id)-\(cover.version)-\(cover.objectPath ?? cover.remoteURL?.absoluteString ?? "fallback")"
  }

  private var fallback: some View {
    ZStack {
      LinearGradient(
        colors: fallbackColors,
        startPoint: .topLeading,
        endPoint: .bottomTrailing
      )
      Circle()
        .fill(.white.opacity(0.12))
        .frame(width: 150, height: 150)
        .offset(x: 60, y: -50)
      Image(systemName: didFail ? "photo.badge.exclamationmark" : "waveform")
        .font(.system(size: 30, weight: .semibold))
        .foregroundStyle(.white.opacity(0.9))
    }
  }

  private var fallbackColors: [Color] {
    let options: [[Color]] = [
      [Color(red: 0.28, green: 0.16, blue: 0.75), Color(red: 0.89, green: 0.27, blue: 0.55)],
      [Color(red: 0.02, green: 0.38, blue: 0.49), Color(red: 0.18, green: 0.12, blue: 0.47)],
      [Color(red: 0.73, green: 0.25, blue: 0.10), Color(red: 0.24, green: 0.08, blue: 0.24)],
      [Color(red: 0.07, green: 0.42, blue: 0.25), Color(red: 0.02, green: 0.18, blue: 0.25)]
    ]
    let checksum = event.id.uuidString.utf8.reduce(0) { $0 + Int($1) }
    return options[checksum % options.count]
  }
}

private struct EventDatePill: View {
  let date: Date

  var body: some View {
    Text(date.formatted(.dateTime.month(.abbreviated).day()))
      .font(.caption2.weight(.heavy))
      .textCase(.uppercase)
      .foregroundStyle(.white)
      .padding(.horizontal, 8)
      .padding(.vertical, 5)
      .background(.black.opacity(0.58), in: Capsule())
  }
}

struct EventPostPreviewCard: View {
  let post: EventPostPreview
  let showsAuthor: Bool

  init(post: EventPostPreview, showsAuthor: Bool = true) {
    self.post = post
    self.showsAuthor = showsAuthor
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      if showsAuthor {
        HStack(spacing: 10) {
          SocialProfileButton(profile: post.author) {
            HStack(spacing: 10) {
              ProfileAvatarView(profile: post.author, size: 42)
              VStack(alignment: .leading, spacing: 2) {
                Text(post.author.displayName)
                  .font(.subheadline.weight(.bold))
                  .foregroundStyle(TunedInDesign.primaryText)
                Text("@\(post.author.username)")
                  .font(.caption)
                  .foregroundStyle(TunedInDesign.mutedText)
              }
            }
          }
          Spacer()
          score
        }
      } else if post.score != nil {
        HStack {
          Spacer()
          score
        }
      }
      if let note = post.note {
        Text(note)
          .font(.body)
          .foregroundStyle(TunedInDesign.primaryText)
          .lineLimit(4)
      }
      HStack(spacing: 14) {
        if let performanceScore = post.performanceScore {
          Label(
            performanceScore.formatted(.number.precision(.fractionLength(1))),
            systemImage: "music.mic"
          )
          .foregroundStyle(CommunityEventScoreBand(score: performanceScore).fill)
          .accessibilityLabel(
            "Performance \(performanceScore.formatted(.number.precision(.fractionLength(1)))), "
              + CommunityEventScoreBand(score: performanceScore).accessibilityDescription
          )
        }
        if post.photoCount > 0 {
          Label("\(post.photoCount)", systemImage: "photo")
        }
        if post.videoCount > 0 {
          Label("\(post.videoCount)", systemImage: "video")
        }
        if post.commentCount > 0 {
          Label("\(post.commentCount)", systemImage: "bubble.left")
        }
        Label(post.audience.title, systemImage: post.audience.icon)
      }
      .font(.caption.weight(.semibold))
      .foregroundStyle(TunedInDesign.mutedText)
    }
    .padding(16)
    .background(TunedInDesign.cardBackground, in: RoundedRectangle(cornerRadius: TunedInDesign.cornerRadius))
    .overlay {
      RoundedRectangle(cornerRadius: TunedInDesign.cornerRadius)
        .strokeBorder(TunedInDesign.cardBorder.opacity(0.55))
    }
  }

  @ViewBuilder
  private var score: some View {
    if let score = post.score {
      CommunityEventScoreBadge(score: score)
    }
  }
}

struct PostEngagementLine: View {
  let post: EventPostPreview

  var body: some View {
    HStack(spacing: 14) {
      if let performanceScore = post.performanceScore {
        Label(
          performanceScore.formatted(.number.precision(.fractionLength(1))),
          systemImage: "music.mic"
        )
        .foregroundStyle(CommunityEventScoreBand(score: performanceScore).fill)
        .accessibilityLabel(
          "Performance \(performanceScore.formatted(.number.precision(.fractionLength(1)))), "
            + CommunityEventScoreBand(score: performanceScore).accessibilityDescription
        )
      }
      if post.photoCount > 0 {
        Label("\(post.photoCount)", systemImage: "photo")
      }
      if post.videoCount > 0 {
        Label("\(post.videoCount)", systemImage: "video")
      }
      if post.commentCount > 0 {
        Label("\(post.commentCount)", systemImage: "bubble.left")
      }
      Spacer(minLength: 0)
      Image(systemName: post.audience.icon)
    }
    .font(.caption.weight(.semibold))
    .foregroundStyle(TunedInDesign.mutedText)
  }
}

struct PostMediaPreview: View {
  let postID: UUID
  let reportedPhotoCount: Int
  let postRepository: any PostRepository
  let height: CGFloat
  var maximumVisiblePhotos = 3

  @State private var photos: [PostMedia] = []
  @State private var didFail = false

  var body: some View {
    Group {
      if photos.isEmpty {
        TunedInImagePlaceholder(failed: didFail)
      } else {
        GeometryReader { proxy in
          let count = CGFloat(photos.count)
          let spacing = CGFloat(2)
          let width = (proxy.size.width - (spacing * max(0, count - 1))) / count

          HStack(spacing: spacing) {
            ForEach(photos) { photo in
              PostMediaImage(photo: photo, postRepository: postRepository)
                .frame(width: width, height: proxy.size.height)
            }
          }
        }
      }
    }
    .frame(maxWidth: .infinity)
    .frame(height: height)
    .clipped()
    .task(id: "\(postID)-\(reportedPhotoCount)-\(maximumVisiblePhotos)") {
      guard reportedPhotoCount > 0 else { return }
      do {
        photos = try await Array(postRepository.media(
          postID: postID,
          cursor: nil
        ).prefix(maximumVisiblePhotos))
        didFail = photos.isEmpty
      } catch {
        didFail = true
      }
    }
  }
}

struct PostMediaImage: View {
  let photo: PostMedia
  let postRepository: any PostRepository

  @State private var url: URL?
  @State private var failed = false

  var body: some View {
    Group {
      if let url {
        CachedRemoteImage(
          url: url,
          resource: .postMedia(mediaID: photo.id, version: photo.version)
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
        TunedInImagePlaceholder(failed: failed)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .clipped()
    .task(id: "\(photo.id)-\(photo.version)") {
      do {
        url = try await postRepository.mediaURL(
          mediaID: photo.id,
          objectPath: photo.objectPath,
          version: photo.version
        )
      } catch {
        failed = true
      }
    }
  }
}

struct EventScrollTopMask: View {
  var body: some View {
    LinearGradient(
      stops: [
        .init(color: TunedInDesign.pageBackground, location: 0),
        .init(color: TunedInDesign.pageBackground, location: 0.62),
        .init(color: TunedInDesign.pageBackground.opacity(0), location: 1)
      ],
      startPoint: .top,
      endPoint: .bottom
    )
    .frame(height: 64)
    .ignoresSafeArea(edges: .top)
    .allowsHitTesting(false)
    .accessibilityHidden(true)
  }
}

struct EventCommentRow: View {
  let comment: EventComment
  var onReply: (() -> Void)?

  init(comment: EventComment, onReply: (() -> Void)? = nil) {
    self.comment = comment
    self.onReply = onReply
  }

  var body: some View {
    HStack(alignment: .top, spacing: 10) {
      if comment.parentCommentID != nil {
        Image(systemName: "arrowshape.turn.up.left")
          .font(.caption)
          .foregroundStyle(TunedInDesign.mutedText)
          .frame(width: 16, height: 38)
      }
      SocialProfileButton(profile: comment.author) {
        ProfileAvatarView(profile: comment.author, size: 38)
      }
      VStack(alignment: .leading, spacing: 4) {
        HStack {
          SocialProfileButton(profile: comment.author) {
            Text(comment.author.displayName)
              .font(.subheadline.weight(.bold))
              .foregroundStyle(TunedInDesign.primaryText)
          }
          Image(systemName: comment.audience.icon)
            .font(.caption2)
            .foregroundStyle(TunedInDesign.mutedText)
          Spacer()
          Text(comment.createdAt, style: .relative)
            .font(.caption2)
            .foregroundStyle(TunedInDesign.mutedText)
        }
        Text(comment.body)
          .font(.subheadline)
          .foregroundStyle(comment.isDeleted ? TunedInDesign.mutedText : TunedInDesign.primaryText)
          .italic(comment.isDeleted)
        if let onReply {
          Button("Reply", action: onReply)
            .font(.caption.weight(.semibold))
            .foregroundStyle(TunedInDesign.accent)
            .buttonStyle(.plain)
        }
      }
    }
    .padding(.leading, comment.parentCommentID == nil ? 0 : 22)
    .padding(.vertical, 8)
  }
}

struct EventDateTile: View {
  let date: Date

  var body: some View {
    VStack(spacing: 1) {
      Text(CommunityEventDateText.month(date))
        .font(.caption2.weight(.bold))
        .textCase(.uppercase)
        .foregroundStyle(TunedInDesign.accent)
      Text(CommunityEventDateText.day(date))
        .font(.title2.weight(.bold))
        .foregroundStyle(TunedInDesign.primaryText)
      Text(CommunityEventDateText.weekday(date))
        .font(.caption2.weight(.semibold))
        .foregroundStyle(TunedInDesign.mutedText)
    }
    .frame(width: 52, height: 62)
  }
}

enum CommunityEventDateText {
  static func fullDate(_ date: Date) -> String {
    formatter(dateStyle: .full).string(from: date)
  }

  static func compactDate(_ date: Date) -> String {
    formatter(dateStyle: .medium).string(from: date)
  }

  static func time(for event: CommunityEventSummary) -> String {
    if event.sourceLabel == "MusicBrainz" {
      guard let sourceTime = event.sourceLocalStartTime,
            let date = localTimeFormatter.date(from: sourceTime)
      else { return "Time not listed" }
      return localTimeDisplayFormatter.string(from: date)
    }
    let formatter = DateFormatter()
    formatter.locale = .current
    formatter.timeZone = TimeZone(identifier: event.timeZoneIdentifier) ?? .current
    formatter.dateFormat = "h:mm a z"
    return formatter.string(from: event.startsAt)
  }

  static func month(_ date: Date) -> String {
    formatter(format: "MMM").string(from: date)
  }

  static func day(_ date: Date) -> String {
    formatter(format: "d").string(from: date)
  }

  static func weekday(_ date: Date) -> String {
    formatter(format: "EEE").string(from: date)
  }

  private static func formatter(
    dateStyle: DateFormatter.Style,
    timeStyle: DateFormatter.Style = .none,
    timeZone: TimeZone = .current
  ) -> DateFormatter {
    let formatter = DateFormatter()
    formatter.locale = .current
    formatter.timeZone = timeZone
    formatter.dateStyle = dateStyle
    formatter.timeStyle = timeStyle
    return formatter
  }

  private static func formatter(format: String) -> DateFormatter {
    let formatter = DateFormatter()
    formatter.locale = .current
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = format
    return formatter
  }

  private static let localTimeFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = .current
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "HH:mm:ss"
    return formatter
  }()

  private static let localTimeDisplayFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = .current
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "h:mm a"
    return formatter
  }()
}

struct EventAvatarStack: View {
  let profiles: [SocialProfile]

  var body: some View {
    HStack(spacing: -9) {
      ForEach(profiles.prefix(3)) { profile in
        SocialProfileButton(profile: profile) {
          ProfileAvatarView(profile: profile, size: 34)
            .overlay(Circle().stroke(TunedInDesign.cardBackground, lineWidth: 2))
        }
      }
    }
  }
}

struct EventMetadataRow: View {
  let label: String
  let value: String

  var body: some View {
    HStack(alignment: .top) {
      Text(label)
        .font(.subheadline)
        .foregroundStyle(TunedInDesign.mutedText)
        .frame(width: 72, alignment: .leading)
      Text(value)
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(TunedInDesign.primaryText)
      Spacer(minLength: 0)
    }
  }
}

struct EventScreenHeader: View {
  let eyebrow: String
  let title: String
  let subtitle: String

  var body: some View {
    VStack(alignment: .leading, spacing: 7) {
      Text(eyebrow)
        .font(.caption2.weight(.bold))
        .foregroundStyle(TunedInDesign.accent)
        .textCase(.uppercase)
        .tracking(1.2)
      Text(title)
        .font(.largeTitle.weight(.bold))
        .foregroundStyle(TunedInDesign.primaryText)
      Text(subtitle)
        .font(.subheadline)
        .foregroundStyle(TunedInDesign.mutedText)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

struct EventEmptyView: View {
  let systemImage: String
  let title: String
  let message: String

  var body: some View {
    VStack(spacing: 12) {
      Image(systemName: systemImage)
        .font(.title2.weight(.semibold))
        .foregroundStyle(TunedInDesign.accent)
        .frame(width: 56, height: 56)
        .background(TunedInDesign.accentTint, in: Circle())
      Text(title)
        .font(.headline)
        .foregroundStyle(TunedInDesign.primaryText)
      Text(message)
        .font(.subheadline)
        .foregroundStyle(TunedInDesign.mutedText)
        .multilineTextAlignment(.center)
    }
    .frame(maxWidth: .infinity)
    .padding(24)
    .background(TunedInDesign.cardBackground, in: RoundedRectangle(cornerRadius: TunedInDesign.cornerRadius))
  }
}

struct EventFailureView: View {
  let message: String
  let retry: () -> Void

  var body: some View {
    VStack(spacing: 12) {
      Label("Couldn’t load concerts", systemImage: "exclamationmark.triangle")
        .font(.headline)
        .foregroundStyle(TunedInDesign.primaryText)
      Text(message)
        .font(.subheadline)
        .foregroundStyle(TunedInDesign.mutedText)
        .multilineTextAlignment(.center)
      Button("Try again", action: retry)
        .buttonStyle(.borderedProminent)
        .tint(TunedInDesign.accent)
    }
    .frame(maxWidth: .infinity)
    .padding(24)
  }
}

extension EventAttendanceStatus {
  var title: String {
    switch self {
    case .going: "Going"
    case .went: "Went"
    case .didNotGo: "Didn’t go"
    }
  }
}

extension EventAudience {
  var icon: String {
    switch self {
    case .privateOnly: "lock.fill"
    case .friends: "person.2.fill"
    case .community: "globe.americas.fill"
    }
  }
}

extension CatalogEntityKind: Identifiable {
  var id: String {
    rawValue
  }
}
