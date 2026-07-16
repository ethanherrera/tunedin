import PhotosUI
import SwiftUI

// This cohesive event journey keeps its phase-specific private views together.
// swiftlint:disable file_length

struct CommunityEventDetailView: View {
  let eventID: UUID
  let viewerID: UUID
  let repository: any EventRepository
  let concertRepository: (any ConcertRepository)?
  let initialDiaryID: UUID?
  let onDismiss: () -> Void

  init(
    eventID: UUID,
    viewerID: UUID,
    repository: any EventRepository,
    concertRepository: (any ConcertRepository)?,
    initialDiaryID: UUID? = nil,
    onDismiss: @escaping () -> Void
  ) {
    self.eventID = eventID
    self.viewerID = viewerID
    self.repository = repository
    self.concertRepository = concertRepository
    self.initialDiaryID = initialDiaryID
    self.onDismiss = onDismiss
  }

  @State private var detail: CommunityEventDetail?
  @State private var isLoading = true
  @State private var errorMessage: String?
  @State private var isPresentingInvites = false
  @State private var isPresentingReport = false
  @State private var isPresentingAttendanceDirectory = false

  var body: some View {
    ZStack {
      TunedInDesign.pageBackground.ignoresSafeArea()

      if isLoading, detail == nil {
        VStack(spacing: 14) {
          TunedInSkeletonBlock(cornerRadius: 24).frame(height: 220)
          TunedInSkeletonBlock(cornerRadius: 24).frame(height: 180)
          Spacer()
        }
        .padding(20)
      } else if let errorMessage, detail == nil {
        EventFailureView(message: errorMessage) { Task { await load() } }
          .padding(20)
      } else if let detail {
        ScrollView {
          VStack(alignment: .leading, spacing: 18) {
            CommunityEventHero(
              detail: detail,
              repository: repository,
              allowsAttendance: repository.capabilities.contains(.attendance),
              onViewAllAttendance: { isPresentingAttendanceDirectory = true },
              onSetAttendance: { status, audience in
                Task { await setAttendance(status, audience: audience) }
              },
              onConfirmCancelledPerformance: { audience in
                Task { await confirmCancelledPerformance(audience: audience) }
              }
            )

            if repository.capabilities.contains(.diaries), detail.summary.phase() == .memories {
              EventMemoriesPage(
                detail: detail,
                viewerID: viewerID,
                repository: repository,
                concertRepository: concertRepository,
                initialDiaryID: initialDiaryID,
                onSaved: { Task { await load() } }
              )
            }

            if repository.capabilities.contains(.attendance) {
              EventPeoplePage(
                detail: detail,
                viewerID: viewerID,
                onViewAll: { isPresentingAttendanceDirectory = true }
              )
            }

            EventOverviewPage(
              detail: detail,
              viewerID: viewerID,
              repository: repository,
              allowsConversation: repository.capabilities.contains(.conversation),
              onReport: { isPresentingReport = true },
              onPostAdded: { Task { await load() } }
            )

            if repository.capabilities.contains(.diaries), detail.summary.phase() != .memories {
              EventMemoriesPage(
                detail: detail,
                viewerID: viewerID,
                repository: repository,
                concertRepository: concertRepository,
                initialDiaryID: initialDiaryID,
                onSaved: { Task { await load() } }
              )
            }
          }
          .padding(.horizontal, 20)
          .padding(.top, 18)
          .padding(.bottom, 24)
        }
        .refreshable { await load() }
      }

      EventScrollTopMask()
        .frame(maxHeight: .infinity, alignment: .top)
    }
    .toolbar(.hidden, for: .navigationBar)
    .safeAreaInset(edge: .bottom, spacing: 0) {
      TunedInPersistentControlRegion {
        eventBottomBar
          .padding(.horizontal, TunedInDesign.bottomControlHorizontalInset)
          .padding(.top, 6)
          .padding(.bottom, TunedInDesign.bottomControlInset)
      }
    }
    .task { await load() }
    .sheet(isPresented: $isPresentingInvites) {
      EventInviteView(
        eventID: eventID,
        viewerID: viewerID,
        repository: repository
      )
      .presentationDetents([.medium, .large])
      .presentationDragIndicator(.visible)
    }
    .sheet(isPresented: $isPresentingReport) {
      EventReportView(
        eventID: eventID,
        viewerID: viewerID,
        repository: repository,
        onDismiss: { isPresentingReport = false }
      )
      .presentationDetents([.medium, .large])
      .presentationDragIndicator(.visible)
    }
    .fullScreenCover(isPresented: $isPresentingAttendanceDirectory) {
      if let detail {
        EventAttendanceDirectoryView(
          event: detail.summary,
          viewerID: viewerID,
          repository: repository,
          onDismiss: { isPresentingAttendanceDirectory = false }
        )
      }
    }
  }

  private var eventBottomBar: some View {
    TunedInGlassTraversalLayout {
      TunedInGlassIconButton(
        systemImage: "chevron.backward",
        accessibilityLabel: "Back to previous screen",
        action: onDismiss
      )
    } center: {
      TunedInGlassBottomBar {
        Text(detail?.summary.title ?? "Concert")
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(TunedInDesign.primaryText)
          .lineLimit(1)
          .frame(minWidth: 132, minHeight: 48)
          .padding(.horizontal, 16)
      }
    } trailing: {
      if canInvite {
        TunedInGlassIconButton(
          systemImage: "paperplane",
          accessibilityLabel: "Invite friends"
        ) {
          isPresentingInvites = true
        }
      } else {
        EmptyView()
      }
    }
  }

  private var canInvite: Bool {
    guard repository.capabilities.contains(.invitations), let detail else { return false }
    let phase = detail.summary.phase()
    return phase == .upcoming || phase == .postponed
  }

  @MainActor
  private func load() async {
    isLoading = detail == nil
    defer { isLoading = false }
    do {
      detail = try await repository.eventDetail(id: eventID, viewerID: viewerID)
      errorMessage = nil
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  @MainActor
  private func setAttendance(_ status: EventAttendanceStatus?, audience: EventAudience) async {
    do {
      detail = try await repository.setAttendance(
        eventID: eventID,
        viewerID: viewerID,
        status: status,
        audience: audience
      )
      errorMessage = nil
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  @MainActor
  private func confirmCancelledPerformance(audience: EventAudience) async {
    do {
      detail = try await repository.confirmCancelledPerformance(
        eventID: eventID,
        viewerID: viewerID,
        audience: audience
      )
      errorMessage = nil
    } catch {
      errorMessage = error.localizedDescription
    }
  }
}

private struct CommunityEventHero: View {
  let detail: CommunityEventDetail
  let repository: any EventRepository
  let allowsAttendance: Bool
  let onViewAllAttendance: () -> Void
  let onSetAttendance: (EventAttendanceStatus?, EventAudience) -> Void
  let onConfirmCancelledPerformance: (EventAudience) -> Void

  @State private var audience = EventAudience.friends

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      if detail.summary.cover != nil {
        CommunityEventCoverImage(event: detail.summary, repository: repository)
          .frame(maxWidth: .infinity)
          .frame(height: 220)
          .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
          .overlay(alignment: .bottomTrailing) {
            if let credit = coverCredit {
              Text(credit)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(.black.opacity(0.58), in: Capsule())
                .padding(10)
            }
          }
      }

      HStack(alignment: .firstTextBaseline, spacing: 12) {
        Text(CommunityEventDateText.fullDate(detail.summary.eventDate))
          .font(.caption.weight(.bold))
          .textCase(.uppercase)
          .foregroundStyle(TunedInDesign.mutedText)
        if let startsAt = detail.summary.startsAt {
          Text(
            CommunityEventDateText.time(
              startsAt,
              timeZoneIdentifier: detail.summary.timeZoneIdentifier
            )
          )
          .font(.caption.weight(.semibold))
          .foregroundStyle(TunedInDesign.mutedText)
        }
        Spacer()
        phaseBadge
      }

      VStack(alignment: .leading, spacing: 5) {
        Text(detail.summary.title)
          .font(.system(size: 34, weight: .bold, design: .default))
          .foregroundStyle(TunedInDesign.primaryText)
        Text("\(detail.summary.venueName) · \(detail.summary.areaName)")
          .font(.body)
          .foregroundStyle(TunedInDesign.mutedText)
      }

      if !detail.summary.friendPreviews.isEmpty {
        HStack(spacing: 10) {
          EventAvatarStack(profiles: detail.summary.friendPreviews.map(\.profile))
          Text(friendLine)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(TunedInDesign.primaryText)
          Spacer(minLength: 4)
          Button("View all", action: onViewAllAttendance)
            .font(.subheadline.weight(.bold))
            .foregroundStyle(TunedInDesign.accent)
        }
      }

      if allowsAttendance, detail.summary.phase() == .cancelled {
        cancelledAttendanceControl
      } else if allowsAttendance {
        HStack(spacing: 12) {
          if detail.summary.phase() == .memories {
            Menu {
              Button("I went", systemImage: "checkmark.circle") {
                onSetAttendance(.went, audience)
              }
              Button("I didn’t go", systemImage: "xmark.circle") {
                onSetAttendance(.didNotGo, audience)
              }
              if detail.summary.currentUserAttendance != nil {
                Divider()
                Button("Remove from my history", systemImage: "trash", role: .destructive) {
                  onSetAttendance(nil, audience)
                }
              }
            } label: {
              attendanceLabel
            }
          } else {
            Button {
              onSetAttendance(nextAttendance, audience)
            } label: {
              attendanceLabel
            }
            .buttonStyle(TunedInPosterButtonStyle())
          }

          Menu {
            ForEach(EventAudience.allCases, id: \.self) { option in
              Button {
                audience = option
                if let current = detail.summary.currentUserAttendance {
                  onSetAttendance(current, option)
                }
              } label: {
                if audience == option {
                  Label(option.title, systemImage: "checkmark")
                } else {
                  Text(option.title)
                }
              }
            }
          } label: {
            Image(systemName: audienceIcon)
              .font(.body.weight(.bold))
              .foregroundStyle(TunedInDesign.primaryText)
              .frame(width: 48, height: 48)
              .background(TunedInDesign.raisedSurface, in: Circle())
          }
          .accessibilityLabel("Attendance visibility: \(audience.title)")
        }
      }

      HStack(spacing: 8) {
        Image(systemName: "person.3.fill")
        Text("\(detail.attendances.count) visible")
        Spacer(minLength: 0)
        Text(detail.summary.sourceLabel)
      }
      .font(.caption2.weight(.semibold))
      .foregroundStyle(TunedInDesign.mutedText)

      Divider().overlay(TunedInDesign.cardBorder)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.top, 4)
    .task(id: detail.summary.currentUserAudience) {
      audience = detail.summary.currentUserAudience ?? .friends
    }
  }

  private var coverCredit: String? {
    guard let cover = detail.summary.cover else { return nil }
    if let attribution = cover.attribution { return attribution }
    if let providerName = cover.providerName { return "Image: \(providerName)" }
    return cover.source == .community ? "Community photo" : nil
  }

  @ViewBuilder
  private var cancelledAttendanceControl: some View {
    if Date.now < detail.summary.memoryUnlockAt {
      Label(
        "Attendance is paused unless the performance actually happens.",
        systemImage: "calendar.badge.exclamationmark"
      )
      .font(.caption.weight(.semibold))
      .foregroundStyle(TunedInDesign.mutedText)
    } else if detail.summary.currentUserAttendance == .went {
      Label("You confirmed this performance happened", systemImage: "checkmark.seal.fill")
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(TunedInDesign.primaryText)
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(TunedInDesign.raisedSurface, in: RoundedRectangle(cornerRadius: 18))
    } else {
      Button {
        onConfirmCancelledPerformance(audience)
      } label: {
        Label("The performance happened — I went", systemImage: "checkmark.circle.fill")
          .font(.headline)
          .foregroundStyle(TunedInDesign.actionForeground)
          .frame(maxWidth: .infinity)
          .padding(.vertical, 13)
          .background(TunedInDesign.accent, in: Capsule())
      }
      .buttonStyle(TunedInPosterButtonStyle())
    }
  }

  private var attendanceLabel: some View {
    Label(attendanceTitle, systemImage: attendanceIcon)
      .font(.headline)
      .foregroundStyle(TunedInDesign.actionForeground)
      .frame(maxWidth: .infinity)
      .padding(.vertical, 13)
      .background(TunedInDesign.accent, in: Capsule())
  }

  private var attendanceTitle: String {
    if detail.summary.phase() == .memories {
      switch detail.summary.currentUserAttendance {
      case .going: return "Confirm attendance"
      case .went: return "Went"
      case .didNotGo: return "Didn’t go"
      case nil: return "Add attendance"
      }
    }
    return detail.summary.currentUserAttendance == nil ? "I’m going" : "Going"
  }

  private var attendanceIcon: String {
    detail.summary.currentUserAttendance == nil ? "plus" : "checkmark"
  }

  private var nextAttendance: EventAttendanceStatus? {
    guard detail.summary.currentUserAttendance == nil else { return nil }
    return .going
  }

  private var audienceIcon: String {
    switch audience {
    case .privateOnly: "lock.fill"
    case .friends: "person.2.fill"
    case .community: "globe.americas.fill"
    }
  }

  @ViewBuilder
  private var phaseBadge: some View {
    switch detail.summary.phase() {
    case .upcoming:
      EmptyView()
    case .postponed:
      Label("Postponed", systemImage: "clock.badge.exclamationmark")
        .foregroundStyle(TunedInDesign.accent)
    case .cancelled:
      Label("Cancelled", systemImage: "xmark.circle.fill")
        .foregroundStyle(TunedInDesign.accent)
    case .memories:
      Label("Posts", systemImage: "square.and.pencil")
        .foregroundStyle(TunedInDesign.accent)
    }
  }

  private var friendLine: String {
    let total = detail.summary.friendPreviews.count
    let verb = detail.summary.phase() == .memories ? "went" : "are going"
    return "\(total) friend\(total == 1 ? "" : "s") \(verb)"
  }
}

private struct EventOverviewPage: View {
  let detail: CommunityEventDetail
  let viewerID: UUID
  let repository: any EventRepository
  let allowsConversation: Bool
  let onReport: () -> Void
  let onPostAdded: () -> Void

  @State private var comment = ""
  @State private var audience = EventAudience.friends
  @State private var replyTo: EventPost?
  @State private var isPosting = false
  @State private var errorMessage: String?
  @State private var isShowingDetails = false

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      if allowsConversation {
        VStack(alignment: .leading, spacing: 12) {
          Text("Before the show")
            .font(.headline)
            .foregroundStyle(TunedInDesign.primaryText)

          if detail.summary.phase() == .memories {
            Text("This discussion is read-only after the show.")
              .font(.caption)
              .foregroundStyle(TunedInDesign.mutedText)
          }

          if detail.summary.phase() != .memories {
            if let replyTo {
              HStack(spacing: 8) {
                Image(systemName: "arrowshape.turn.up.left.fill")
                Text("Replying to")
                SocialProfileButton(profile: replyTo.author) {
                  Text(replyTo.author.displayName)
                    .fontWeight(.bold)
                    .lineLimit(1)
                }
                Spacer()
                Button("Cancel") { self.replyTo = nil }
              }
              .font(.caption.weight(.semibold))
              .foregroundStyle(TunedInDesign.mutedText)
            }
            HStack(spacing: 8) {
              TextField(
                replyTo == nil ? "What are you excited for?" : "Write a reply…",
                text: $comment,
                axis: .vertical
              )
              .lineLimit(1 ... 4)
              .padding(12)
              .background(TunedInDesign.raisedSurface, in: RoundedRectangle(cornerRadius: 14))

              Menu {
                ForEach([EventAudience.friends, .community], id: \.self) { option in
                  Button(option.title) {
                    audience = option
                    rememberPostAudience(option)
                  }
                }
              } label: {
                Image(systemName: audience == .friends ? "person.2.fill" : "globe.americas.fill")
                  .foregroundStyle(TunedInDesign.primaryText)
                  .frame(width: 42, height: 42)
              }

              Button { Task { await post() } } label: {
                Image(systemName: "arrow.up.circle.fill")
                  .font(.title2)
                  .foregroundStyle(comment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? TunedInDesign.mutedText : TunedInDesign.accent)
              }
              .disabled(isPosting || comment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
          }

          if let errorMessage {
            Text(errorMessage).font(.caption).foregroundStyle(TunedInDesign.accent)
          }

          if detail.posts.isEmpty {
            Text(detail.summary.phase() == .memories
              ? "No one posted before the show."
              : "Be the first to say what you’re excited for.")
              .font(.subheadline)
              .foregroundStyle(TunedInDesign.mutedText)
              .padding(.vertical, 12)
          } else {
            ForEach(detail.posts.sorted(by: { $0.createdAt < $1.createdAt })) { post in
              EventPostRow(
                post: post,
                onReply: detail.summary.phase() != .memories && post.parentPostID == nil && !post.isDeleted
                  ? { replyTo = post }
                  : nil
              )
            }
          }
        }
      }

      DisclosureGroup(isExpanded: $isShowingDetails) {
        VStack(alignment: .leading, spacing: 12) {
          EventMetadataRow(label: "Date", value: CommunityEventDateText.fullDate(detail.summary.eventDate))
          if let startsAt = detail.summary.startsAt {
            EventMetadataRow(
              label: "Starts",
              value: CommunityEventDateText.time(
                startsAt,
                timeZoneIdentifier: detail.summary.timeZoneIdentifier
              )
            )
          }
          EventMetadataRow(label: "Venue", value: detail.summary.venueName)
          EventMetadataRow(label: "Location", value: detail.summary.areaName)
          EventMetadataRow(label: "Source", value: detail.summary.sourceLabel)

          Button(action: onReport) {
            Label("Suggest a correction", systemImage: "exclamationmark.bubble")
              .font(.subheadline.weight(.semibold))
              .foregroundStyle(TunedInDesign.primaryText)
          }
          .buttonStyle(.plain)
        }
        .padding(.top, 12)
      } label: {
        Label("Concert details", systemImage: "info.circle")
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(TunedInDesign.primaryText)
      }
      .tint(TunedInDesign.mutedText)
      .padding(.vertical, 4)
    }
    .task {
      if let remembered = EventAudience(rawValue: UserDefaults.standard.string(
        forKey: "community-event-post-audience.\(viewerID.uuidString)"
      ) ?? "") {
        audience = remembered
      }
    }
  }

  @MainActor
  private func post() async {
    isPosting = true
    defer { isPosting = false }
    do {
      _ = try await repository.addPost(
        eventID: detail.id,
        authorID: viewerID,
        parentPostID: replyTo?.id,
        body: comment,
        audience: audience
      )
      rememberPostAudience(audience)
      comment = ""
      replyTo = nil
      errorMessage = nil
      onPostAdded()
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  private func rememberPostAudience(_ audience: EventAudience) {
    UserDefaults.standard.set(
      audience.rawValue,
      forKey: "community-event-post-audience.\(viewerID.uuidString)"
    )
  }
}

private struct EventPeoplePage: View {
  let detail: CommunityEventDetail
  let viewerID: UUID
  let onViewAll: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(alignment: .firstTextBaseline) {
        Text(detail.summary.phase() == .memories ? "Who went" : "Who’s going")
          .font(.headline)
          .foregroundStyle(TunedInDesign.primaryText)
        Spacer()
        if !detail.attendances.isEmpty {
          Button("View all", action: onViewAll)
            .font(.subheadline.weight(.bold))
            .foregroundStyle(TunedInDesign.accent)
        }
      }

      if detail.attendances.isEmpty {
        Text("No visible plans yet. Private attendance stays private.")
          .font(.subheadline)
          .foregroundStyle(TunedInDesign.mutedText)
          .padding(.vertical, 8)
      } else {
        ScrollView(.horizontal, showsIndicators: false) {
          HStack(alignment: .top, spacing: 14) {
            ForEach(sortedAttendances.prefix(8)) { attendance in
              SocialProfileButton(profile: attendance.profile) {
                VStack(spacing: 6) {
                  ProfileAvatarView(profile: attendance.profile, size: 54)
                  Text(attendance.profile.id == viewerID ? "You" : attendance.profile.displayName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(TunedInDesign.primaryText)
                    .lineLimit(1)
                  Text(attendance.profile.relationship == .friends ? "Friend" : "Community")
                    .font(.caption2)
                    .foregroundStyle(TunedInDesign.mutedText)
                }
                .frame(width: 72)
              }
            }
          }
          .padding(.horizontal, 1)
        }
      }
      Divider().overlay(TunedInDesign.cardBorder)
    }
  }

  private var sortedAttendances: [EventAttendance] {
    detail.attendances.sorted { lhs, rhs in
      let lhsRank = lhs.profile.id == viewerID ? 0 : (lhs.profile.relationship == .friends ? 1 : 2)
      let rhsRank = rhs.profile.id == viewerID ? 0 : (rhs.profile.relationship == .friends ? 1 : 2)
      if lhsRank != rhsRank { return lhsRank < rhsRank }
      return lhs.profile.displayName < rhs.profile.displayName
    }
  }
}

private struct EventMemoriesPage: View {
  let detail: CommunityEventDetail
  let viewerID: UUID
  let repository: any EventRepository
  let concertRepository: (any ConcertRepository)?
  let initialDiaryID: UUID?
  let onSaved: () -> Void

  @State private var isPresentingDiary = false
  @State private var isPresentingAllPosts = false
  @State private var selectedDiary: EventDiaryPreview?
  @State private var didOpenInitialDiary = false

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      if !memoriesAreAvailable {
        HStack(spacing: 12) {
          Image(systemName: "lock.fill")
            .foregroundStyle(TunedInDesign.mutedText)
          VStack(alignment: .leading, spacing: 3) {
            Text("Posts unlock after the concert")
              .font(.subheadline.weight(.semibold))
              .foregroundStyle(TunedInDesign.primaryText)
            Text("Add ratings, photos, videos, and a review after the concert.")
              .font(.caption)
              .foregroundStyle(TunedInDesign.mutedText)
          }
        }
        .padding(.vertical, 8)
      } else {
        HStack(alignment: .firstTextBaseline) {
          VStack(alignment: .leading, spacing: 4) {
            Text("Posts")
              .font(.title2.weight(.bold))
              .foregroundStyle(TunedInDesign.primaryText)
            if let score = detail.summary.averageDiaryScore {
              HStack(spacing: 6) {
                CommunityEventScoreBadge(score: score, size: .compact)
                Text(
                  "average from \(detail.summary.diaryCount) visible "
                    + (detail.summary.diaryCount == 1 ? "post" : "posts")
                )
                .font(.caption.weight(.semibold))
                .foregroundStyle(TunedInDesign.mutedText)
              }
            }
          }
          Spacer()
          if detail.summary.canCreateDiary() {
            Button(myDiary == nil ? "Create post" : "Edit post") {
              isPresentingDiary = true
            }
            .font(.subheadline.weight(.bold))
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .tint(TunedInDesign.accent)
          }
        }

        if detail.diaryPreviews.isEmpty {
          Text("No posts yet. Going or Went still works without posting.")
            .font(.subheadline)
            .foregroundStyle(TunedInDesign.mutedText)
            .padding(.vertical, 12)
        } else {
          if let concertRepository {
            LazyVGrid(
              columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 3),
              spacing: 2
            ) {
              ForEach(previewDiaries) { diary in
                EventPostGridTile(
                  post: diary,
                  viewerID: viewerID,
                  concertRepository: concertRepository,
                  onOpen: { selectedDiary = diary }
                )
              }
            }
            .padding(.horizontal, -20)
          } else {
            ForEach(previewDiaries) { diary in
              EventDiaryPreviewCard(diary: diary)
            }
          }

          if shouldShowAllPosts {
            Button { isPresentingAllPosts = true } label: {
              HStack {
                Text("View all \(detail.summary.diaryCount) posts")
                Spacer()
                Image(systemName: "chevron.right")
              }
              .font(.subheadline.weight(.bold))
              .foregroundStyle(TunedInDesign.primaryText)
              .padding(.vertical, 11)
              .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
          }
        }
      }
    }
    .fullScreenCover(isPresented: $isPresentingDiary) {
      EventDiaryComposerView(
        event: detail.summary,
        viewerID: viewerID,
        repository: repository,
        concertRepository: concertRepository,
        existing: detail.diaryPreviews.first(where: { $0.author.id == viewerID }),
        onSaved: {
          isPresentingDiary = false
          onSaved()
        },
        onDismiss: { isPresentingDiary = false }
      )
    }
    .fullScreenCover(item: $selectedDiary) { diary in
      if let concertRepository {
        EventDiaryDetailView(
          event: detail.summary,
          diary: diary,
          viewerID: viewerID,
          concertRepository: concertRepository,
          onChanged: onSaved,
          onDismiss: { selectedDiary = nil }
        )
      }
    }
    .fullScreenCover(isPresented: $isPresentingAllPosts) {
      EventPostGalleryView(
        event: detail.summary,
        viewerID: viewerID,
        repository: repository,
        concertRepository: concertRepository,
        onChanged: onSaved,
        onDismiss: { isPresentingAllPosts = false }
      )
    }
    .task(id: initialDiaryID) {
      guard !didOpenInitialDiary,
            let initialDiaryID,
            let diary = detail.diaryPreviews.first(where: { $0.id == initialDiaryID })
      else { return }
      didOpenInitialDiary = true
      selectedDiary = diary
    }
  }

  private var memoriesAreAvailable: Bool {
    detail.summary.phase() == .memories
      || (detail.summary.lifecycle == .cancelled && Date.now >= detail.summary.memoryUnlockAt)
  }

  private var sortedDiaries: [EventDiaryPreview] {
    detail.diaryPreviews.sorted { lhs, rhs in
      let lhsRank = lhs.author.id == viewerID ? 0 : (lhs.author.relationship == .friends ? 1 : 2)
      let rhsRank = rhs.author.id == viewerID ? 0 : (rhs.author.relationship == .friends ? 1 : 2)
      if lhsRank != rhsRank { return lhsRank < rhsRank }
      return lhs.publishedAt > rhs.publishedAt
    }
  }

  private var myDiary: EventDiaryPreview? {
    sortedDiaries.first(where: { $0.author.id == viewerID })
  }

  private var previewDiaries: [EventDiaryPreview] {
    Array(sortedDiaries.prefix(6))
  }

  private var shouldShowAllPosts: Bool {
    detail.summary.diaryCount > previewDiaries.count
  }
}

private struct EventDiaryComposerView: View {
  let event: CommunityEventSummary
  let viewerID: UUID
  let repository: any EventRepository
  let concertRepository: (any ConcertRepository)?
  let existing: EventDiaryPreview?
  let onSaved: () -> Void
  let onDismiss: () -> Void

  @State private var includesScore: Bool
  @State private var score: Double
  @State private var includesPerformanceScore: Bool
  @State private var performanceScore: Double
  @State private var note: String
  @State private var audience: EventAudience
  @State private var photoSelection: [PhotosPickerItem] = []
  @State private var isSaving = false
  @State private var errorMessage: String?

  init(
    event: CommunityEventSummary,
    viewerID: UUID,
    repository: any EventRepository,
    concertRepository: (any ConcertRepository)?,
    existing: EventDiaryPreview?,
    onSaved: @escaping () -> Void,
    onDismiss: @escaping () -> Void
  ) {
    self.event = event
    self.viewerID = viewerID
    self.repository = repository
    self.concertRepository = concertRepository
    self.existing = existing
    self.onSaved = onSaved
    self.onDismiss = onDismiss
    _includesScore = State(initialValue: existing?.score != nil)
    _score = State(initialValue: existing?.score ?? 8)
    _includesPerformanceScore = State(initialValue: existing?.performanceScore != nil)
    _performanceScore = State(initialValue: existing?.performanceScore ?? 8)
    _note = State(initialValue: existing?.note ?? "")
    _audience = State(initialValue: existing?.audience ?? .friends)
  }

  var body: some View {
    let photoPickerTitle = if photoSelection.isEmpty {
      (existing?.photoCount ?? 0) > 0 ? "Add more photos" : "Choose photos"
    } else {
      "\(photoSelection.count) selected"
    }
    ZStack {
      TunedInDesign.pageBackground.ignoresSafeArea()

      ScrollView {
        VStack(alignment: .leading, spacing: 26) {
          EventDiaryComposerHeader(
            event: event,
            existing: existing,
            concertRepository: concertRepository,
            photoSelection: $photoSelection,
            isSaving: isSaving
          )

          VStack(alignment: .leading, spacing: 0) {
            Text("Ratings")
              .font(.headline)
              .foregroundStyle(TunedInDesign.primaryText)
              .padding(.bottom, 10)

            DiaryScoreRow(
              title: "Overall",
              systemImage: "star.fill",
              isIncluded: $includesScore,
              value: $score
            )

            Divider()

            DiaryScoreRow(
              title: "Performance",
              systemImage: "music.mic",
              isIncluded: $includesPerformanceScore,
              value: $performanceScore
            )
          }

          VStack(alignment: .leading, spacing: 8) {
            Text("Review")
              .font(.headline)
              .foregroundStyle(TunedInDesign.primaryText)
            ZStack(alignment: .topLeading) {
              if note.isEmpty {
                Text("What do you want to remember?")
                  .font(.body)
                  .foregroundStyle(TunedInDesign.mutedText)
                  .padding(.horizontal, 14)
                  .padding(.vertical, 18)
                  .allowsHitTesting(false)
              }
              TextEditor(text: $note)
                .frame(minHeight: 110)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 4)
            }
            .overlay(alignment: .bottom) {
              Divider().overlay(TunedInDesign.cardBorder)
            }
            Text("\(note.count)/4000")
              .font(.caption.monospacedDigit())
              .foregroundStyle(note.count > 4_000 ? TunedInDesign.accent : TunedInDesign.mutedText)
              .frame(maxWidth: .infinity, alignment: .trailing)
          }

          VStack(alignment: .leading, spacing: 16) {
            if (existing?.photoCount ?? 0) == 0 {
              if concertRepository != nil {
                PhotosPicker(
                  selection: $photoSelection,
                  maxSelectionCount: 10,
                  matching: .images
                ) {
                  Label(
                    photoPickerTitle,
                    systemImage: "photo.badge.plus"
                  )
                  .font(.subheadline.weight(.bold))
                  .foregroundStyle(TunedInDesign.actionForeground)
                  .padding(.horizontal, 16)
                  .frame(height: 44)
                  .background(TunedInDesign.accent, in: Capsule())
                }
                .disabled(isSaving)
              } else {
                Text("Photo uploads are unavailable in this preview.")
                  .font(.caption)
                  .foregroundStyle(TunedInDesign.mutedText)
              }
            }

            Divider()

            HStack(spacing: 12) {
              Label("Audience", systemImage: audience.icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(TunedInDesign.primaryText)
              Spacer()
              Menu {
                ForEach(EventAudience.allCases, id: \.self) { option in
                  Button {
                    audience = option
                  } label: {
                    Label(option.title, systemImage: option.icon)
                  }
                }
              } label: {
                HStack(spacing: 6) {
                  Text(audience.title)
                  Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2.weight(.bold))
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(TunedInDesign.accent)
              }
            }
          }

          if let errorMessage {
            Text(errorMessage).font(.caption).foregroundStyle(TunedInDesign.accent)
          }
        }
        .padding(20)
        .padding(.bottom, 96)
      }

      EventScrollTopMask()
        .frame(maxHeight: .infinity, alignment: .top)
    }
    .safeAreaInset(edge: .bottom, spacing: 0) {
      TunedInPersistentControlRegion {
        EventDiaryActionBar(
          isSaving: isSaving,
          canSave: canSaveDiary,
          onDismiss: onDismiss,
          onSave: { Task { await save() } }
        )
          .padding(.horizontal, TunedInDesign.bottomControlHorizontalInset)
          .padding(.top, 8)
          .padding(.bottom, TunedInDesign.bottomControlInset)
      }
    }
    .tunedInKeyboardManaged()
  }

  @MainActor
  private func save() async {
    isSaving = true
    defer { isSaving = false }
    do {
      var hasReadyPhoto = (existing?.photoCount ?? 0) > 0
      if !photoSelection.isEmpty {
        guard let concertRepository else {
          throw CommunityEventError.invalidEvent("Photo uploads are unavailable right now.")
        }
        let diaryID: UUID
        if let existingID = existing?.id {
          diaryID = existingID
        } else {
          diaryID = try await repository.preparePhotoDiary(
            eventID: event.id,
            authorID: viewerID,
            audience: audience
          )
        }
        var uploadedCount = 0
        for item in photoSelection {
          guard let source = try await item.loadTransferable(type: Data.self) else {
            throw AppFailure.unexpected
          }
          let data = try await ConcertAlbumImageProcessor.process(source)
          let reservation = try await concertRepository.reserveAlbumPhoto(
            concertID: diaryID,
            photoID: UUID()
          )
          _ = try await concertRepository.uploadReservedAlbumPhoto(
            data,
            reservation: reservation
          )
          uploadedCount += 1
        }
        hasReadyPhoto = hasReadyPhoto || uploadedCount > 0
      }
      _ = try await repository.saveDiary(
        eventID: event.id,
        authorID: viewerID,
        input: EventDiaryInput(
          score: includesScore ? score : nil,
          performanceScore: includesPerformanceScore ? performanceScore : nil,
          note: note,
          audience: audience,
          hasReadyPhoto: hasReadyPhoto
        )
      )
      photoSelection = []
      errorMessage = nil
      onSaved()
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  private var hasDiaryContent: Bool {
    includesScore
      || includesPerformanceScore
      || CatalogInput.optionalNormalizedText(note) != nil
      || !photoSelection.isEmpty
      || (existing?.photoCount ?? 0) > 0
  }

  private var canSaveDiary: Bool {
    !isSaving && note.count <= 4_000 && hasDiaryContent
  }
}

private struct EventDiaryActionBar: View {
  let isSaving: Bool
  let canSave: Bool
  let onDismiss: () -> Void
  let onSave: () -> Void

  var body: some View {
    TunedInGlassTraversalLayout {
      TunedInGlassIconButton(
        systemImage: "chevron.backward",
        accessibilityLabel: "Close post editor",
        action: onDismiss
      )
      .disabled(isSaving)
    } center: {
      TunedInGlassTextButton(
        isSaving ? "Saving" : "Save post",
        systemImage: isSaving ? "ellipsis" : "checkmark",
        accessibilityHint: canSave
          ? "Saves this post"
          : "Add a score, review, or photo before saving",
        action: onSave
      )
      .disabled(!canSave)
      .opacity(canSave ? 1 : 0.45)
    } trailing: {
      EmptyView()
    }
  }
}

private struct EventDiaryComposerHeader: View {
  let event: CommunityEventSummary
  let existing: EventDiaryPreview?
  let concertRepository: (any ConcertRepository)?
  @Binding var photoSelection: [PhotosPickerItem]
  let isSaving: Bool

  var body: some View {
    let photoPickerTitle = photoSelection.isEmpty ? "Add" : "\(photoSelection.count) selected"

    VStack(alignment: .leading, spacing: 20) {
      VStack(alignment: .leading, spacing: 5) {
        Text(existing == nil ? "Create post" : "Edit post")
          .font(.largeTitle.weight(.bold))
          .foregroundStyle(TunedInDesign.primaryText)
        Label("Tagged concert · \(event.title)", systemImage: "music.note")
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(TunedInDesign.accent)
        Text("\(event.venueName) · Add photos, ratings, and your review. You control who can see it.")
          .font(.subheadline)
          .foregroundStyle(TunedInDesign.mutedText)
      }

      if let existing, let concertRepository, existing.photoCount > 0 {
        ZStack(alignment: .topTrailing) {
          DiaryMediaPreview(
            diaryID: existing.id,
            reportedPhotoCount: existing.photoCount,
            concertRepository: concertRepository,
            height: 170,
            maximumVisiblePhotos: 2
          )

          PhotosPicker(
            selection: $photoSelection,
            maxSelectionCount: 10,
            matching: .images
          ) {
            Label(
              photoPickerTitle,
              systemImage: "photo.badge.plus"
            )
            .font(.caption.weight(.bold))
            .foregroundStyle(TunedInDesign.primaryText)
            .padding(.horizontal, 12)
            .frame(height: 36)
            .background(.ultraThinMaterial, in: Capsule())
          }
          .disabled(isSaving)
          .padding(12)
        }
        .padding(.horizontal, -20)
      }
    }
  }
}

private struct DiaryScoreRow: View {
  let title: String
  let systemImage: String
  @Binding var isIncluded: Bool
  @Binding var value: Double

  var body: some View {
    HStack(spacing: 8) {
      Image(systemName: systemImage)
        .font(.subheadline.weight(.bold))
        .foregroundStyle(TunedInDesign.accent)
        .frame(width: 32, height: 32)
        .background(TunedInDesign.accentTint, in: Circle())

      Text(title)
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(TunedInDesign.primaryText)
        .lineLimit(1)
        .minimumScaleFactor(0.85)

      Spacer(minLength: 8)

      if isIncluded {
        Button {
          value = max(0.5, value - 0.5)
        } label: {
          Image(systemName: "minus")
            .frame(width: 28, height: 28)
        }
        .disabled(value <= 0.5)

        CommunityEventScoreBadge(score: value, size: .compact)
          .frame(width: 42)

        Button {
          value = min(10, value + 0.5)
        } label: {
          Image(systemName: "plus")
            .frame(width: 28, height: 28)
        }
        .disabled(value >= 10)

        Button {
          isIncluded = false
        } label: {
          Image(systemName: "xmark")
            .font(.caption.weight(.bold))
            .frame(width: 28, height: 28)
        }
        .accessibilityLabel("Remove \(title.lowercased()) score")
      } else {
        Button("Add") {
          isIncluded = true
        }
        .font(.subheadline.weight(.bold))
        .foregroundStyle(TunedInDesign.accent)
      }
    }
    .buttonStyle(.plain)
  }
}

private struct EventReportView: View {
  let eventID: UUID
  let viewerID: UUID
  let repository: any EventRepository
  let onDismiss: () -> Void

  @State private var reason = EventReportReason.wrongDate
  @State private var note = ""
  @State private var isSubmitting = false
  @State private var errorMessage: String?

  var body: some View {
    NavigationStack {
      Form {
        Section("What should we review?") {
          Picker("Reason", selection: $reason) {
            ForEach(EventReportReason.allCases, id: \.self) { option in
              Text(option.title).tag(option)
            }
          }
          TextField("Optional details", text: $note, axis: .vertical)
            .lineLimit(2 ... 6)
          Text("\(note.count)/500")
            .font(.caption.monospacedDigit())
            .foregroundStyle(note.count > 500 ? TunedInDesign.accent : TunedInDesign.mutedText)
        }

        Section {
          Text(
            "A report starts a review. It never removes anyone’s Going, Went, invitations, "
              + "photos, or posts; those stay attached or can be reattached safely."
          )
          .font(.caption)
          .foregroundStyle(TunedInDesign.mutedText)
        }

        if let errorMessage {
          Text(errorMessage).foregroundStyle(TunedInDesign.accent)
        }
      }
      .navigationTitle("Suggest a correction")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel", action: onDismiss)
        }
        ToolbarItem(placement: .confirmationAction) {
          Button(isSubmitting ? "Sending…" : "Send") {
            Task { await submit() }
          }
          .disabled(isSubmitting || note.count > 500)
        }
      }
    }
  }

  @MainActor
  private func submit() async {
    isSubmitting = true
    defer { isSubmitting = false }
    do {
      try await repository.reportEvent(
        eventID: eventID,
        reporterID: viewerID,
        reason: reason,
        note: note
      )
      onDismiss()
    } catch {
      errorMessage = error.localizedDescription
    }
  }
}

private struct EventInviteView: View {
  let eventID: UUID
  let viewerID: UUID
  let repository: any EventRepository

  @Environment(\.dismiss) private var dismiss
  @State private var candidates: [EventInviteCandidate] = []
  @State private var selection: Set<UUID> = []
  @State private var isLoading = true
  @State private var isSending = false
  @State private var errorMessage: String?

  var body: some View {
    NavigationStack {
      ZStack {
        TunedInDesign.pageBackground.ignoresSafeArea()
        ScrollView {
          VStack(alignment: .leading, spacing: 14) {
            EventScreenHeader(
              eyebrow: "Make a plan together",
              title: "Invite friends",
              subtitle: "Friends already going stay visible, but won’t receive a duplicate invite."
            )

            if isLoading {
              ProgressView("Finding friends…")
            } else if candidates.isEmpty {
              EventEmptyView(
                systemImage: "person.2",
                title: "No friends to invite",
                message: "Add friends first, then bring them into concert plans."
              )
            } else {
              ForEach(candidates) { candidate in
                HStack(spacing: 12) {
                  SocialProfileButton(profile: candidate.profile) {
                    HStack(spacing: 12) {
                      ProfileAvatarView(profile: candidate.profile, size: 44)
                      VStack(alignment: .leading, spacing: 3) {
                        Text(candidate.profile.displayName)
                          .font(.body.weight(.semibold))
                          .foregroundStyle(TunedInDesign.primaryText)
                        Text(candidateStatus(candidate))
                          .font(.caption)
                          .foregroundStyle(TunedInDesign.mutedText)
                      }
                    }
                  }
                  Spacer()
                  Button { toggle(candidate) } label: {
                    Image(
                      systemName: selection.contains(candidate.id) ? "checkmark.circle.fill" : "circle"
                    )
                    .font(.title3)
                    .foregroundStyle(
                      selection.contains(candidate.id) ? TunedInDesign.accent : TunedInDesign.mutedText
                    )
                    .frame(width: 44, height: 44)
                  }
                  .buttonStyle(.plain)
                  .disabled(candidate.attendanceStatus != nil || candidate.isAlreadyInvited)
                  .accessibilityLabel(
                    selection.contains(candidate.id)
                      ? "Remove \(candidate.profile.displayName) from invites"
                      : "Invite \(candidate.profile.displayName)"
                  )
                }
                .padding(12)
                .background(TunedInDesign.cardBackground, in: RoundedRectangle(cornerRadius: 18))
              }
            }

            if let errorMessage {
              Text(errorMessage).font(.caption).foregroundStyle(TunedInDesign.accent)
            }

            Button { Task { await send() } } label: {
              Text(isSending ? "Sending…" : "Send \(selection.count) invite\(selection.count == 1 ? "" : "s")")
                .font(.headline)
                .foregroundStyle(TunedInDesign.actionForeground)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(TunedInDesign.accent, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(selection.isEmpty || isSending)
          }
          .padding(20)
        }
      }
      .toolbar(.hidden, for: .navigationBar)
    }
    .task { await load() }
  }

  private func toggle(_ candidate: EventInviteCandidate) {
    if selection.contains(candidate.id) {
      selection.remove(candidate.id)
    } else {
      selection.insert(candidate.id)
    }
  }

  @MainActor
  private func load() async {
    do {
      candidates = try await repository.inviteCandidates(eventID: eventID, viewerID: viewerID)
      errorMessage = nil
    } catch {
      errorMessage = error.localizedDescription
    }
    isLoading = false
  }

  @MainActor
  private func send() async {
    isSending = true
    defer { isSending = false }
    do {
      try await repository.sendInvitations(
        eventID: eventID,
        senderID: viewerID,
        recipientIDs: Array(selection)
      )
      dismiss()
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  private func candidateStatus(_ candidate: EventInviteCandidate) -> String {
    if let attendanceStatus = candidate.attendanceStatus { return attendanceStatus.title }
    if candidate.isAlreadyInvited { return "Invited" }
    return "@\(candidate.profile.username)"
  }
}
