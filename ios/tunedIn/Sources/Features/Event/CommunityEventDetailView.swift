import PhotosUI
import SwiftUI

// This cohesive event journey keeps its phase-specific private views together.
// swiftlint:disable file_length

struct CommunityEventDetailView: View {
  private enum Page: String, CaseIterable {
    case event = "Event"
    case people = "People"
    case memories = "Memories"

    var icon: String {
      switch self {
      case .event: "music.note"
      case .people: "person.2"
      case .memories: "photo.on.rectangle.angled"
      }
    }
  }

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
    _selectedPage = State(initialValue: initialDiaryID == nil ? .event : .memories)
  }

  @State private var detail: CommunityEventDetail?
  @State private var selectedPage = Page.event
  @State private var isLoading = true
  @State private var errorMessage: String?
  @State private var isPresentingInvites = false
  @State private var isPresentingReport = false
  @Namespace private var selectionNamespace

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
              allowsAttendance: repository.capabilities.contains(.attendance),
              onSetAttendance: { status, audience in
                Task { await setAttendance(status, audience: audience) }
              },
              onConfirmCancelledPerformance: { audience in
                Task { await confirmCancelledPerformance(audience: audience) }
              }
            )

            switch selectedPage {
            case .event:
              EventOverviewPage(
                detail: detail,
                viewerID: viewerID,
                repository: repository,
                allowsConversation: repository.capabilities.contains(.conversation),
                onReport: { isPresentingReport = true },
                onPostAdded: { Task { await load() } }
              )
            case .people:
              EventPeoplePage(detail: detail, viewerID: viewerID)
            case .memories:
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
    }
    .toolbar(.hidden, for: .navigationBar)
    .safeAreaInset(edge: .bottom, spacing: 0) {
      TunedInPersistentControlRegion {
        detailBottomBar
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
  }

  private var detailBottomBar: some View {
    TunedInGlassTraversalLayout {
      TunedInGlassIconButton(
        systemImage: "chevron.backward",
        accessibilityLabel: "Back to previous screen",
        action: onDismiss
      )
    } center: {
      TunedInGlassBottomBar {
        HStack(spacing: 2) {
          ForEach(availablePages, id: \.self) { page in
            Button { selectedPage = page } label: {
              VStack(spacing: 2) {
                Image(systemName: page.icon).font(.caption.weight(.bold))
                Text(page.rawValue).font(.caption2.weight(.bold))
              }
              .foregroundStyle(
                selectedPage == page ? TunedInDesign.selectedControlForeground : TunedInDesign.primaryText
              )
              .frame(maxWidth: .infinity)
              .frame(height: 48)
              .background {
                if selectedPage == page {
                  TunedInSelectionLens()
                    .matchedGeometryEffect(id: "event-detail-page", in: selectionNamespace)
                }
              }
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(selectedPage == page ? .isSelected : [])
          }
        }
      }
      .frame(maxWidth: CGFloat(availablePages.count * 84))
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

  private var availablePages: [Page] {
    var pages = [Page.event]
    if repository.capabilities.contains(.attendance) {
      pages.append(.people)
    }
    if repository.capabilities.contains(.diaries) {
      pages.append(.memories)
    }
    return pages
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
      selectedPage = .memories
    } catch {
      errorMessage = error.localizedDescription
    }
  }
}

private struct CommunityEventHero: View {
  let detail: CommunityEventDetail
  let allowsAttendance: Bool
  let onSetAttendance: (EventAttendanceStatus?, EventAudience) -> Void
  let onConfirmCancelledPerformance: (EventAudience) -> Void

  @State private var audience = EventAudience.friends

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack(alignment: .firstTextBaseline, spacing: 12) {
        Text(CommunityEventDateText.fullDate(detail.summary.eventDate))
          .font(.caption.weight(.bold))
          .textCase(.uppercase)
          .foregroundStyle(TunedInDesign.primaryText)
        Spacer()
        phaseBadge
      }

      Spacer(minLength: 18)

      VStack(alignment: .leading, spacing: 6) {
        Text(detail.summary.title)
          .font(.system(.largeTitle, design: .rounded, weight: .bold))
          .foregroundStyle(TunedInDesign.primaryText)
        Text("\(detail.summary.venueName) · \(detail.summary.areaName)")
          .font(.body.weight(.medium))
          .foregroundStyle(TunedInDesign.mutedText)
      }

      if !detail.summary.friendPreviews.isEmpty {
        HStack(spacing: 10) {
          EventAvatarStack(profiles: detail.summary.friendPreviews.map(\.profile))
          Text(friendLine)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(TunedInDesign.primaryText)
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
        if let startsAt = detail.summary.startsAt {
          Label(
            CommunityEventDateText.time(
              startsAt,
              timeZoneIdentifier: detail.summary.timeZoneIdentifier
            ),
            systemImage: "clock"
          )
        }
        Spacer()
        Text(detail.summary.sourceLabel)
      }
      .font(.caption2.weight(.semibold))
      .foregroundStyle(TunedInDesign.mutedText)
    }
    .padding(20)
    .frame(maxWidth: .infinity, minHeight: 280, alignment: .bottomLeading)
    .background(
      LinearGradient(
        colors: [TunedInDesign.accent.opacity(0.4), TunedInDesign.accentTint, TunedInDesign.cardBackground],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
      ),
      in: RoundedRectangle(cornerRadius: TunedInDesign.largeCornerRadius, style: .continuous)
    )
    .overlay {
      RoundedRectangle(cornerRadius: TunedInDesign.largeCornerRadius, style: .continuous)
        .strokeBorder(TunedInDesign.cardBorder.opacity(0.55))
    }
    .task(id: detail.summary.currentUserAudience) {
      audience = detail.summary.currentUserAudience ?? .friends
    }
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
      Label("Memories", systemImage: "sparkles")
        .foregroundStyle(TunedInDesign.accent)
    }
  }

  private var friendLine: String {
    let names = detail.summary.friendPreviews.prefix(2).map { $0.profile.displayName }
    let total = detail.summary.friendPreviews.count
    let verb = detail.summary.phase() == .memories ? "went" : "are going"
    if total == 1, let name = names.first {
      return detail.summary.phase() == .memories ? name + " went" : name + " is going"
    }
    let remainder = total - names.count
    return names.joined(separator: " and ")
      + (remainder > 0 ? " + \(remainder) more \(verb)" : " \(verb)")
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
        Label("Details", systemImage: "info.circle")
          .font(.headline)
          .foregroundStyle(TunedInDesign.primaryText)
      }
      .tint(TunedInDesign.mutedText)
      .padding(.vertical, 2)

      if allowsConversation {
        VStack(alignment: .leading, spacing: 12) {
          Text("Before the show")
            .font(.headline)
            .foregroundStyle(TunedInDesign.primaryText)

          if detail.summary.phase() == .memories {
            Text("This thread is read-only now. Post-show stories live in each person’s diary.")
              .font(.caption)
              .foregroundStyle(TunedInDesign.mutedText)
          }

          if detail.summary.phase() != .memories {
            if let replyTo {
              HStack(spacing: 8) {
                Image(systemName: "arrowshape.turn.up.left.fill")
                Text("Replying to \(replyTo.author.displayName)")
                  .lineLimit(1)
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

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      Text(detail.summary.phase() == .memories ? "People who went" : "People going")
        .font(.headline)
        .foregroundStyle(TunedInDesign.primaryText)

      if detail.attendances.isEmpty {
        EventEmptyView(
          systemImage: "person.2",
          title: "No visible plans yet",
          message: "Private attendance stays private. Friends and community plans appear here."
        )
      } else {
        if !circleAttendances.isEmpty {
          attendeeSection(title: "You & friends", attendances: circleAttendances)
        }
        if !communityAttendances.isEmpty {
          attendeeSection(title: "Community", attendances: communityAttendances)
        }
      }
    }
  }

  private var circleAttendances: [EventAttendance] {
    detail.attendances.filter {
      $0.profile.id == viewerID || $0.profile.relationship == .friends
    }
  }

  private var communityAttendances: [EventAttendance] {
    detail.attendances.filter {
      $0.profile.id != viewerID && $0.profile.relationship != .friends
    }
  }

  private func attendeeSection(title: String, attendances: [EventAttendance]) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(title)
        .font(.subheadline.weight(.bold))
        .foregroundStyle(TunedInDesign.mutedText)
        .padding(.bottom, 4)

      ForEach(attendances) { attendance in
        HStack(spacing: 12) {
          ProfileAvatarView(profile: attendance.profile, size: 46)
          VStack(alignment: .leading, spacing: 3) {
            Text(attendance.profile.id == viewerID ? "You" : attendance.profile.displayName)
              .font(.body.weight(.semibold))
              .foregroundStyle(TunedInDesign.primaryText)
            Text("@\(attendance.profile.username) · \(attendance.status.title)")
              .font(.caption)
              .foregroundStyle(TunedInDesign.mutedText)
          }
          Spacer()
          Image(systemName: attendance.audience.icon)
            .foregroundStyle(TunedInDesign.mutedText)
        }
        .padding(.vertical, 10)
        Divider().overlay(TunedInDesign.cardBorder)
      }
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
  @State private var selectedDiary: EventDiaryPreview?
  @State private var didOpenInitialDiary = false

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      if !memoriesAreAvailable {
        EventEmptyView(
          systemImage: "lock.fill",
          title: "Memories unlock after the show",
          message: "For now, make plans and talk with friends. Ratings, diaries, photos, "
            + "and video belong to the post-show moment."
        )
      } else {
        HStack {
          VStack(alignment: .leading, spacing: 4) {
            Text("Concert memories")
              .font(.headline)
              .foregroundStyle(TunedInDesign.primaryText)
            Text("Each person owns their diary and its sharing settings.")
              .font(.caption)
              .foregroundStyle(TunedInDesign.mutedText)
            if let score = detail.summary.averageDiaryScore {
              Label(
                "Visible average \(score.formatted(.number.precision(.fractionLength(1))))"
                  + " · \(detail.summary.diaryCount) "
                  + (detail.summary.diaryCount == 1 ? "diary" : "diaries"),
                systemImage: "star.fill"
              )
              .font(.caption.weight(.semibold))
              .foregroundStyle(TunedInDesign.accent)
            }
          }
          Spacer()
          if detail.summary.canCreateDiary() {
            Button(detail.diaryPreviews.contains(where: { $0.author.id == viewerID }) ? "Edit mine" : "Add mine") {
              isPresentingDiary = true
            }
              .buttonStyle(.borderedProminent)
              .tint(TunedInDesign.accent)
          }
        }

        if detail.diaryPreviews.isEmpty {
          EventEmptyView(
            systemImage: "book.closed",
            title: "No shared diaries yet",
            message: "Going or Went still exists without a diary. Writing one is always optional."
          )
        } else {
          ForEach(sortedDiaries) { diary in
            if concertRepository == nil {
              EventDiaryPreviewCard(diary: diary)
            } else {
              Button { selectedDiary = diary } label: {
                EventDiaryPreviewCard(diary: diary)
              }
              .buttonStyle(TunedInPosterButtonStyle())
            }
          }
        }
      }
    }
    .fullScreenCover(isPresented: $isPresentingDiary) {
      EventDiaryComposerView(
        eventID: detail.id,
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
}

private struct EventDiaryComposerView: View {
  let eventID: UUID
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
    eventID: UUID,
    viewerID: UUID,
    repository: any EventRepository,
    concertRepository: (any ConcertRepository)?,
    existing: EventDiaryPreview?,
    onSaved: @escaping () -> Void,
    onDismiss: @escaping () -> Void
  ) {
    self.eventID = eventID
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
        VStack(alignment: .leading, spacing: 18) {
          EventScreenHeader(
            eyebrow: "Your concert, your perspective",
            title: existing == nil ? "Add a diary" : "Edit your diary",
            subtitle: "This belongs to you even if the shared event changes later."
          )

          TunedInFormCard {
            Toggle("Add a score", isOn: $includesScore)
              .tint(TunedInDesign.accent)
            if includesScore {
              HStack {
                Text("Your score")
                  .font(.headline)
                Spacer()
                Text(score.formatted(.number.precision(.fractionLength(1))))
                  .font(.title2.weight(.bold))
                  .foregroundStyle(TunedInDesign.accent)
              }
              Slider(value: $score, in: 0.5 ... 10, step: 0.5)
                .tint(TunedInDesign.accent)
            }

            Divider()

            Toggle("Rate the performance", isOn: $includesPerformanceScore)
              .tint(TunedInDesign.accent)
            if includesPerformanceScore {
              HStack {
                Text("Performance")
                  .font(.headline)
                Spacer()
                Text(performanceScore.formatted(.number.precision(.fractionLength(1))))
                  .font(.title2.weight(.bold))
                  .foregroundStyle(TunedInDesign.accent)
              }
              Slider(value: $performanceScore, in: 0.5 ... 10, step: 0.5)
                .tint(TunedInDesign.accent)
            }
          }

          TunedInFormCard {
            Text("What do you want to remember?")
              .font(.headline)
              .foregroundStyle(TunedInDesign.primaryText)
            TextEditor(text: $note)
              .frame(minHeight: 160)
              .scrollContentBackground(.hidden)
              .padding(10)
              .background(TunedInDesign.raisedSurface, in: RoundedRectangle(cornerRadius: 14))
            Text("\(note.count)/4000")
              .font(.caption.monospacedDigit())
              .foregroundStyle(note.count > 4_000 ? TunedInDesign.accent : TunedInDesign.mutedText)
              .frame(maxWidth: .infinity, alignment: .trailing)
          }

          TunedInFormCard {
            Text("Photos")
              .font(.headline)
              .foregroundStyle(TunedInDesign.primaryText)
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
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(TunedInDesign.primaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(TunedInDesign.raisedSurface, in: RoundedRectangle(cornerRadius: 14))
              }
              .disabled(isSaving)
            } else {
              Text("Photo uploads are unavailable in this preview.")
                .font(.caption)
                .foregroundStyle(TunedInDesign.mutedText)
            }
            Text("Photos inherit this diary’s audience. You can share a photo-only memory.")
              .font(.caption)
              .foregroundStyle(TunedInDesign.mutedText)
          }

          TunedInFormCard {
            Text("Who can see this diary?")
              .font(.headline)
              .foregroundStyle(TunedInDesign.primaryText)
            Picker("Diary audience", selection: $audience) {
              ForEach(EventAudience.allCases, id: \.self) { option in
                Text(option.title).tag(option)
              }
            }
            .pickerStyle(.segmented)
            Label(
              "After saving, open this diary to see its album and talk with friends. Video comes later.",
              systemImage: "photo.on.rectangle.angled"
            )
            .font(.caption)
            .foregroundStyle(TunedInDesign.mutedText)
          }

          if let errorMessage {
            Text(errorMessage).font(.caption).foregroundStyle(TunedInDesign.accent)
          }

          Button { Task { await save() } } label: {
            Text(isSaving ? "Saving…" : "Save diary")
              .font(.headline)
              .foregroundStyle(TunedInDesign.actionForeground)
              .frame(maxWidth: .infinity)
              .padding(.vertical, 15)
              .background(TunedInDesign.accent, in: Capsule())
          }
          .buttonStyle(.plain)
          .disabled(isSaving || note.count > 4_000 || !hasDiaryContent)
        }
        .padding(20)
        .padding(.bottom, 24)
      }
    }
    .safeAreaInset(edge: .bottom, spacing: 0) {
      TunedInPersistentControlRegion {
        TunedInSubscreenBackBar(title: "Diary", action: onDismiss)
          .padding(.horizontal, TunedInDesign.bottomControlHorizontalInset)
          .padding(.top, 8)
          .padding(.bottom, TunedInDesign.bottomControlInset)
      }
    }
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
            eventID: eventID,
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
        eventID: eventID,
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
              + "photos, or diary; those stay attached or can be reattached safely."
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
                Button { toggle(candidate) } label: {
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
                    Spacer()
                    Image(
                      systemName: selection.contains(candidate.id) ? "checkmark.circle.fill" : "circle"
                    )
                    .foregroundStyle(
                      selection.contains(candidate.id) ? TunedInDesign.accent : TunedInDesign.mutedText
                    )
                  }
                  .padding(12)
                  .background(TunedInDesign.cardBackground, in: RoundedRectangle(cornerRadius: 18))
                }
                .buttonStyle(.plain)
                .disabled(candidate.attendanceStatus != nil || candidate.isAlreadyInvited)
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
