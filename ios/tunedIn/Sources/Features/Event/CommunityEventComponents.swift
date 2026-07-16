import SwiftUI

struct CommunityEventRow: View {
  let event: CommunityEventSummary
  let showsSource: Bool

  var body: some View {
    HStack(spacing: 14) {
      EventDateTile(date: event.eventDate)
      VStack(alignment: .leading, spacing: 5) {
        Text(event.title)
          .font(.headline)
          .foregroundStyle(TunedInDesign.primaryText)
          .lineLimit(2)
        Text("\(event.venueName) · \(event.areaName)")
          .font(.subheadline)
          .foregroundStyle(TunedInDesign.mutedText)
          .lineLimit(2)
        eventStatusLine
        if showsSource {
          Text(event.sourceLabel)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(TunedInDesign.mutedText)
            .lineLimit(1)
        }
      }
      Spacer(minLength: 0)
      Image(systemName: "chevron.right")
        .font(.caption.weight(.bold))
        .foregroundStyle(TunedInDesign.mutedText)
    }
    .padding(.vertical, 12)
    .contentShape(Rectangle())
  }

  private var eventStatusLine: some View {
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
      if !event.friendPreviews.isEmpty {
        Label(
          "\(event.friendPreviews.count) friend\(event.friendPreviews.count == 1 ? "" : "s")",
          systemImage: "person.2.fill"
        )
      }
    }
    .font(.caption.weight(.semibold))
    .foregroundStyle(TunedInDesign.accent)
  }
}

struct CommunityActivityCard: View {
  let activity: EventActivity
  let concertRepository: any ConcertRepository
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
    if let diary = activity.diary {
      VStack(alignment: .leading, spacing: 0) {
        if diary.photoCount > 0 {
          DiaryMediaPreview(
            diaryID: diary.id,
            reportedPhotoCount: diary.photoCount,
            concertRepository: concertRepository,
            height: 280
          )
        }

        VStack(alignment: .leading, spacing: 9) {
          HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
              Text(activity.event.title)
                .font(.headline)
                .foregroundStyle(TunedInDesign.primaryText)
              Text("\(activity.event.venueName) · \(activity.event.eventDate, style: .date)")
                .font(.caption)
                .foregroundStyle(TunedInDesign.mutedText)
            }
            Spacer()
            if let score = diary.score {
              CommunityEventScoreBadge(score: score, size: .large)
            }
          }

          if let note = diary.note {
            Text(note)
              .font(.subheadline)
              .foregroundStyle(TunedInDesign.primaryText)
              .lineLimit(3)
          }

          DiaryEngagementLine(diary: diary)
        }
        .padding(.horizontal, 18)
        .padding(.top, diary.photoCount > 0 ? 12 : 2)
      }
    } else {
      HStack(spacing: 14) {
        EventDateTile(date: activity.event.eventDate)
        VStack(alignment: .leading, spacing: 4) {
          Text(activity.event.title)
            .font(.headline)
            .foregroundStyle(TunedInDesign.primaryText)
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

struct EventDiaryPreviewCard: View {
  let diary: EventDiaryPreview
  let showsAuthor: Bool

  init(diary: EventDiaryPreview, showsAuthor: Bool = true) {
    self.diary = diary
    self.showsAuthor = showsAuthor
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      if showsAuthor {
        HStack(spacing: 10) {
          SocialProfileButton(profile: diary.author) {
            HStack(spacing: 10) {
              ProfileAvatarView(profile: diary.author, size: 42)
              VStack(alignment: .leading, spacing: 2) {
                Text(diary.author.displayName)
                  .font(.subheadline.weight(.bold))
                  .foregroundStyle(TunedInDesign.primaryText)
                Text("@\(diary.author.username)")
                  .font(.caption)
                  .foregroundStyle(TunedInDesign.mutedText)
              }
            }
          }
          Spacer()
          score
        }
      } else if diary.score != nil {
        HStack {
          Spacer()
          score
        }
      }
      if let note = diary.note {
        Text(note)
          .font(.body)
          .foregroundStyle(TunedInDesign.primaryText)
          .lineLimit(4)
      }
      HStack(spacing: 14) {
        if let performanceScore = diary.performanceScore {
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
        if diary.photoCount > 0 {
          Label("\(diary.photoCount)", systemImage: "photo")
        }
        if diary.videoCount > 0 {
          Label("\(diary.videoCount)", systemImage: "video")
        }
        if diary.commentCount > 0 {
          Label("\(diary.commentCount)", systemImage: "bubble.left")
        }
        Label(diary.audience.title, systemImage: diary.audience.icon)
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
    if let score = diary.score {
      CommunityEventScoreBadge(score: score)
    }
  }
}

struct DiaryEngagementLine: View {
  let diary: EventDiaryPreview

  var body: some View {
    HStack(spacing: 14) {
      if let performanceScore = diary.performanceScore {
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
      if diary.photoCount > 0 {
        Label("\(diary.photoCount)", systemImage: "photo")
      }
      if diary.videoCount > 0 {
        Label("\(diary.videoCount)", systemImage: "video")
      }
      if diary.commentCount > 0 {
        Label("\(diary.commentCount)", systemImage: "bubble.left")
      }
      Spacer(minLength: 0)
      Image(systemName: diary.audience.icon)
    }
    .font(.caption.weight(.semibold))
    .foregroundStyle(TunedInDesign.mutedText)
  }
}

struct DiaryMediaPreview: View {
  let diaryID: UUID
  let reportedPhotoCount: Int
  let concertRepository: any ConcertRepository
  let height: CGFloat
  var maximumVisiblePhotos = 3

  @State private var photos: [ConcertAlbumPhoto] = []
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
              DiaryPhotoImage(photo: photo, concertRepository: concertRepository)
                .frame(width: width, height: proxy.size.height)
            }
          }
        }
      }
    }
    .frame(maxWidth: .infinity)
    .frame(height: height)
    .clipped()
    .task(id: "\(diaryID)-\(reportedPhotoCount)-\(maximumVisiblePhotos)") {
      guard reportedPhotoCount > 0 else { return }
      do {
        photos = Array(try await concertRepository.albumPhotos(
          concertID: diaryID,
          cursor: nil,
          policy: .refresh
        ).prefix(maximumVisiblePhotos))
        didFail = photos.isEmpty
      } catch {
        didFail = true
      }
    }
  }
}

struct DiaryPhotoImage: View {
  let photo: ConcertAlbumPhoto
  let concertRepository: any ConcertRepository

  @State private var url: URL?
  @State private var failed = false

  var body: some View {
    Group {
      if let url {
        CachedRemoteImage(
          url: url,
          resource: .albumPhoto(photoID: photo.id, version: photo.version)
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
        url = try await concertRepository.albumPhotoURL(
          photoID: photo.id,
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

struct EventPostRow: View {
  let post: EventPost
  var onReply: (() -> Void)?

  init(post: EventPost, onReply: (() -> Void)? = nil) {
    self.post = post
    self.onReply = onReply
  }

  var body: some View {
    HStack(alignment: .top, spacing: 10) {
      if post.parentPostID != nil {
        Image(systemName: "arrowshape.turn.up.left")
          .font(.caption)
          .foregroundStyle(TunedInDesign.mutedText)
          .frame(width: 16, height: 38)
      }
      SocialProfileButton(profile: post.author) {
        ProfileAvatarView(profile: post.author, size: 38)
      }
      VStack(alignment: .leading, spacing: 4) {
        HStack {
          SocialProfileButton(profile: post.author) {
            Text(post.author.displayName)
              .font(.subheadline.weight(.bold))
              .foregroundStyle(TunedInDesign.primaryText)
          }
          Image(systemName: post.audience.icon)
            .font(.caption2)
            .foregroundStyle(TunedInDesign.mutedText)
          Spacer()
          Text(post.createdAt, style: .relative)
            .font(.caption2)
            .foregroundStyle(TunedInDesign.mutedText)
        }
        Text(post.body)
          .font(.subheadline)
          .foregroundStyle(post.isDeleted ? TunedInDesign.mutedText : TunedInDesign.primaryText)
          .italic(post.isDeleted)
        if let onReply {
          Button("Reply", action: onReply)
            .font(.caption.weight(.semibold))
            .foregroundStyle(TunedInDesign.accent)
            .buttonStyle(.plain)
        }
      }
    }
    .padding(.leading, post.parentPostID == nil ? 0 : 22)
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

  static func time(_ date: Date, timeZoneIdentifier: String) -> String {
    formatter(
      dateStyle: .none,
      timeStyle: .short,
      timeZone: TimeZone(identifier: timeZoneIdentifier) ?? .current
    ).string(from: date)
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
    timeZone: TimeZone = TimeZone(secondsFromGMT: 0) ?? .current
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
  var id: String { rawValue }
}
