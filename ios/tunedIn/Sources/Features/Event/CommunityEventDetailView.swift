import PhotosUI
import SwiftUI
import UIKit

// This cohesive event journey keeps its phase-specific private views together.
// swiftlint:disable file_length

// swiftlint:disable:next type_body_length
struct CommunityEventDetailView: View {
  let eventID: UUID
  let viewerID: UUID
  let repository: any EventRepository
  let postRepository: any PostRepository
  let initialPostID: UUID?
  let onDismiss: () -> Void

  init(
    eventID: UUID,
    viewerID: UUID,
    repository: any EventRepository,
    postRepository: any PostRepository,
    initialPostID: UUID? = nil,
    onDismiss: @escaping () -> Void
  ) {
    self.eventID = eventID
    self.viewerID = viewerID
    self.repository = repository
    self.postRepository = postRepository
    self.initialPostID = initialPostID
    self.onDismiss = onDismiss
  }

  @State private var detail: CommunityEventDetail?
  @State private var invitation: EventInvitation?
  @State private var isLoading = true
  @State private var errorMessage: String?
  @State private var isPresentingInvites = false
  @State private var isPresentingReport = false
  @State private var isPresentingAttendanceDirectory = false
  @State private var isPresentingConversation = false
  @State private var isPresentingMore = false
  @State private var isPresentingAttendanceOptions = false
  @State private var isConfirmingNotGoing = false
  @State private var isCompactControls = false
  @State private var initialScrollOffset: CGFloat?
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    ZStack {
      TunedInDesign.pageBackground.ignoresSafeArea()

      if let detail, detail.summary.cover != nil {
        CommunityEventCoverImage(event: detail.summary, repository: repository)
          .scaleEffect(1.16)
          .blur(radius: 30)
          .opacity(0.13)
          .ignoresSafeArea()
          .allowsHitTesting(false)
      }

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
        eventScroll(for: detail)
      }

      if isCompactControls, let detail {
        Text(detail.summary.title)
          .font(.subheadline.weight(.bold))
          .foregroundStyle(TunedInDesign.primaryText)
          .lineLimit(1)
          .padding(.horizontal, 78)
          .padding(.top, 8)
          .transition(TunedInMotion.compactIdentityTransition(reduceMotion: reduceMotion))
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
          .allowsHitTesting(false)
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
    .fullScreenCover(isPresented: $isPresentingConversation) {
      if let detail {
        EventConversationView(
              detail: detail,
              viewerID: viewerID,
              repository: repository,
              onChanged: { Task { await load() } },
              onDismiss: { isPresentingConversation = false }
            )
      }
    }
    .confirmationDialog("Concert options", isPresented: $isPresentingMore, titleVisibility: .visible) {
      if canInvite {
        Button("Invite friends", systemImage: "person.badge.plus") { isPresentingInvites = true }
      }
      if invitation != nil {
        Button("Decline invite", systemImage: "xmark", role: .destructive) {
          Task { await respondToInvitation(.declined) }
        }
      }
      if shouldOfferNotGoing {
        Button("Change to not going", systemImage: "xmark.circle", role: .destructive) {
          isConfirmingNotGoing = true
        }
      }
      Button("Suggest a correction", systemImage: "exclamationmark.bubble") {
        isPresentingReport = true
      }
    }
    .confirmationDialog("Change to not going?", isPresented: $isConfirmingNotGoing) {
      Button("Change to not going", role: .destructive) {
        Task { await setAttendance(nil, audience: detail?.summary.currentUserAudience ?? .friends) }
      }
    } message: {
      Text("This removes your Going plan. You can add it again later.")
    }
    .confirmationDialog("Attendance", isPresented: $isPresentingAttendanceOptions) {
      attendanceOptions
    }
  }

  private func eventScroll(for detail: CommunityEventDetail) -> some View {
    ScrollView {
      eventContent(for: detail)
    }
    .simultaneousGesture(
      DragGesture(minimumDistance: 12)
        .onChanged { gesture in
          guard gesture.translation.height < -92, !isCompactControls else { return }
          withAnimation(TunedInMotion.selection(reduceMotion: reduceMotion)) {
            isCompactControls = true
          }
        }
    )
    .refreshable { await load() }
  }

  // swiftlint:disable:next function_body_length
  private func eventContent(for detail: CommunityEventDetail) -> some View {
    VStack(alignment: .leading, spacing: 18) {
      CommunityEventHero(
        detail: detail,
        repository: repository,
        invitation: invitation,
        isCompact: isCompactControls,
        onOpenConversation: { isPresentingConversation = true },
        onAttendance: { performAttendanceAction() },
        onAcceptInvitation: { Task { await respondToInvitation(.accepted) } },
        onMore: { isPresentingMore = true },
        onViewAllAttendance: { isPresentingAttendanceDirectory = true }
      )
      .background {
        EventScrollOffsetObserver { scrollOffset in
          updateCompactControls(for: scrollOffset)
        }
        .frame(width: 0, height: 0)
      }

      if repository.capabilities.contains(.posts), memoriesAreAvailable(detail.summary) {
        EventMemoriesPage(
          detail: detail,
          viewerID: viewerID,
          repository: repository,
          postRepository: postRepository,
          initialPostID: initialPostID,
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

      EventLineupPage(event: detail.summary)

      if detail.summary.phase() == .postponed {
        EventLifecycleNotice(
          title: "Postponed",
          message: "The date above is the last confirmed date. Your plans, invitations, and chat "
            + "stay available while we wait for an update."
        )
      } else if detail.summary.phase() == .cancelled {
        EventLifecycleNotice(
          title: "Cancelled",
          message: "Invites and attendance are paused. Chat remains open until memories unlock."
        )
      }
    }
    .padding(.horizontal, 20)
    .padding(.top, 18)
    .padding(.bottom, 24)
  }

  private func updateCompactControls(for scrollOffset: CGFloat) {
    guard let initialScrollOffset else {
      self.initialScrollOffset = scrollOffset
      return
    }

    let compact = scrollOffset > initialScrollOffset + 92
    guard compact != isCompactControls else { return }
    withAnimation(TunedInMotion.selection(reduceMotion: reduceMotion)) {
      isCompactControls = compact
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
        if isCompactControls {
          HStack(spacing: 2) {
            compactAction("Chat", image: "bubble.left.and.bubble.right") {
              isPresentingConversation = true
            }
            compactAction(attendanceButtonTitle, image: attendanceButtonImage) {
              performAttendanceAction()
            }
            compactAction("More", image: "ellipsis") {
              isPresentingMore = true
            }
          }
          .frame(minWidth: 178, minHeight: 48)
          .transition(TunedInMotion.controlSceneTransition(reduceMotion: reduceMotion))
        } else {
          Text(detail?.summary.title ?? "Concert")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(TunedInDesign.primaryText)
            .lineLimit(1)
            .frame(minWidth: 132, minHeight: 48)
            .padding(.horizontal, 16)
            .transition(TunedInMotion.controlSceneTransition(reduceMotion: reduceMotion))
        }
      }
    } trailing: {
      EmptyView()
    }
  }

  private var canInvite: Bool {
    guard repository.capabilities.contains(.invitations), let detail else { return false }
    let phase = detail.summary.phase()
    return phase == .upcoming || phase == .postponed
  }

  private var shouldOfferNotGoing: Bool {
    guard let detail else { return false }
    return detail.summary.phase() != .memories
      && detail.summary.lifecycle != .cancelled
      && detail.summary.currentUserAttendance == .going
  }

  private func memoriesAreAvailable(_ event: CommunityEventSummary) -> Bool {
    event.phase() == .memories || (event.lifecycle == .cancelled && Date.now >= event.memoryUnlockAt)
  }

  private var attendanceButtonTitle: String {
    guard let detail else { return "Going" }
    if invitation != nil { return "Accept" }
    if detail.summary.phase() == .memories {
      return detail.summary.currentUserAttendance == .went ? "Went" : "Attend"
    }
    return detail.summary.currentUserAttendance == .going ? "Going" : "I’m going"
  }

  private var attendanceButtonImage: String {
    invitation != nil ? "checkmark" : (detail?.summary.currentUserAttendance == nil ? "plus" : "checkmark")
  }

  private func compactAction(_ title: String, image: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Label(title, systemImage: image)
        .labelStyle(.iconOnly)
        .font(.caption.weight(.bold))
        .foregroundStyle(TunedInDesign.primaryText)
        .frame(width: 42, height: 42)
        .contentShape(Circle())
        .accessibilityLabel(title)
    }
    .buttonStyle(.plain)
  }

  @MainActor
  private func load() async {
    isLoading = detail == nil
    defer { isLoading = false }
    do {
      let loadedDetail = try await repository.eventDetail(id: eventID, viewerID: viewerID)
      detail = loadedDetail
      invitation = repository.capabilities.contains(.invitations)
        ? try? await repository.pendingInvitation(eventID: eventID, viewerID: viewerID)
        : nil
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

  private func performAttendanceAction() {
    guard let detail else { return }
    if invitation != nil {
      Task { await respondToInvitation(.accepted) }
    } else if detail.summary.phase() == .cancelled {
      guard Date.now >= detail.summary.memoryUnlockAt else { return }
      Task { await confirmCancelledPerformance(audience: detail.summary.currentUserAudience ?? .friends) }
    } else if detail.summary.phase() == .memories || detail.summary.currentUserAttendance == .going {
      isPresentingAttendanceOptions = true
    } else {
      Task { await setAttendance(.going, audience: .friends) }
    }
  }

  @MainActor
  private func respondToInvitation(_ response: EventInvitationResponse) async {
    guard let invitation else { return }
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

  @ViewBuilder
  private var attendanceOptions: some View {
    if let detail {
      if detail.summary.phase() == .memories {
        Button("I went", systemImage: "checkmark.circle") {
          Task { await setAttendance(.went, audience: detail.summary.currentUserAudience ?? .friends) }
        }
        Button("I didn’t go", systemImage: "xmark.circle") {
          Task { await setAttendance(.didNotGo, audience: detail.summary.currentUserAudience ?? .friends) }
        }
        if detail.summary.currentUserAttendance != nil {
          Button("Remove from my history", role: .destructive) {
            Task { await setAttendance(nil, audience: detail.summary.currentUserAudience ?? .friends) }
          }
        }
      } else {
        ForEach(EventAudience.allCases, id: \.self) { audience in
          Button("Going · \(audience.title)") {
            Task { await setAttendance(.going, audience: audience) }
          }
        }
      }
    }
  }
}

private struct EventScrollOffsetObserver: UIViewRepresentable {
  let onChange: (CGFloat) -> Void

  func makeUIView(context: Context) -> EventScrollOffsetObserverView {
    let view = EventScrollOffsetObserverView()
    view.onChange = onChange
    return view
  }

  func updateUIView(_ uiView: EventScrollOffsetObserverView, context: Context) {
    uiView.onChange = onChange
    uiView.beginObservingScrollOffsetIfNeeded()
  }
}

private final class EventScrollOffsetObserverView: UIView {
  var onChange: ((CGFloat) -> Void)?

  private var observation: NSKeyValueObservation?

  override func didMoveToWindow() {
    super.didMoveToWindow()
    DispatchQueue.main.async { [weak self] in
      self?.beginObservingScrollOffsetIfNeeded()
    }
  }

  func beginObservingScrollOffsetIfNeeded() {
    guard observation == nil, let scrollView = nearestScrollView() else { return }

    observation = scrollView.observe(\.contentOffset, options: [.initial, .new]) { [weak self] scrollView, _ in
      let offset = scrollView.contentOffset.y
      DispatchQueue.main.async {
        self?.onChange?(offset)
      }
    }
  }

  private func nearestScrollView() -> UIScrollView? {
    sequence(first: superview, next: { $0?.superview })
      .compactMap { $0 as? UIScrollView }
      .first
  }
}

private struct EventLineupPage: View {
  let event: CommunityEventSummary

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("Lineup")
        .font(.headline)
        .foregroundStyle(TunedInDesign.primaryText)
      ForEach(event.artists.sorted(by: { $0.position < $1.position })) { artist in
        HStack(spacing: 10) {
          Image(systemName: artist.isHeadliner ? "star.fill" : "music.mic")
            .foregroundStyle(artist.isHeadliner ? TunedInDesign.accent : TunedInDesign.mutedText)
            .frame(width: 18)
          Text(artist.displayName)
            .font(.body.weight(artist.isHeadliner ? .semibold : .regular))
            .foregroundStyle(TunedInDesign.primaryText)
          if artist.isHeadliner {
            Text("Headliner")
              .font(.caption.weight(.bold))
              .foregroundStyle(TunedInDesign.mutedText)
          }
        }
      }
      Divider().overlay(TunedInDesign.cardBorder)
    }
  }
}

private struct EventLifecycleNotice: View {
  let title: String
  let message: String

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(title)
        .font(.subheadline.weight(.bold))
        .foregroundStyle(TunedInDesign.primaryText)
      Text(message)
        .font(.caption)
        .foregroundStyle(TunedInDesign.mutedText)
    }
    .padding(14)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(TunedInDesign.raisedSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
  }
}

private struct CommunityEventHero: View {
  let detail: CommunityEventDetail
  let repository: any EventRepository
  let invitation: EventInvitation?
  let isCompact: Bool
  let onOpenConversation: () -> Void
  let onAttendance: () -> Void
  let onAcceptInvitation: () -> Void
  let onMore: () -> Void
  let onViewAllAttendance: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
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

      HStack(alignment: .firstTextBaseline, spacing: 12) {
        Text(CommunityEventDateText.fullDate(detail.summary.startsAt))
          .font(.caption.weight(.bold))
          .textCase(.uppercase)
          .foregroundStyle(TunedInDesign.mutedText)
        Text(
          CommunityEventDateText.time(
            detail.summary.startsAt,
            timeZoneIdentifier: detail.summary.timeZoneIdentifier
          )
        )
        .font(.caption.weight(.semibold))
        .foregroundStyle(TunedInDesign.mutedText)
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

      if !isCompact {
        HStack(spacing: 10) {
          Button(action: onOpenConversation) {
            Label("Chat", systemImage: "bubble.left.and.bubble.right")
              .frame(maxWidth: .infinity)
          }
          .buttonStyle(.bordered)
          .buttonBorderShape(.capsule)

          Button(action: invitation == nil ? onAttendance : onAcceptInvitation) {
            Label(
              invitation == nil ? attendanceActionTitle : "Accept invite",
              systemImage: invitation == nil ? attendanceIcon : "checkmark"
            )
              .frame(maxWidth: .infinity)
          }
          .buttonStyle(.borderedProminent)
          .buttonBorderShape(.capsule)
          .tint(TunedInDesign.accent)

          Button(action: onMore) {
            Image(systemName: "ellipsis")
              .frame(width: 36, height: 36)
          }
          .buttonStyle(.bordered)
          .buttonBorderShape(.circle)
        }
        .font(.subheadline.weight(.bold))
        .transition(.opacity)
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
  }

  private var coverCredit: String? {
    guard let cover = detail.summary.cover else { return nil }
    if let attribution = cover.attribution {
      return attribution
    }
    if let providerName = cover.providerName {
      return "Image: \(providerName)"
    }
    return cover.source == .community ? "Community photo" : nil
  }

  private var attendanceIcon: String {
    detail.summary.currentUserAttendance == nil ? "plus" : "checkmark"
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
      Label("Memories", systemImage: "square.grid.2x2")
        .foregroundStyle(TunedInDesign.accent)
    }
  }

  private var attendanceActionTitle: String {
    if detail.summary.phase() == .cancelled {
      return Date.now >= detail.summary.memoryUnlockAt ? "I went" : "Attendance paused"
    }
    if detail.summary.phase() == .memories {
      return detail.summary.currentUserAttendance == .went ? "Went" : "Attend"
    }
    return detail.summary.currentUserAttendance == .going ? "Going" : "I’m going"
  }
}

private struct EventConversationView: View {
  let detail: CommunityEventDetail
  let viewerID: UUID
  let repository: any EventRepository
  let onChanged: () -> Void
  let onDismiss: () -> Void

  @State private var comment = ""
  @State private var audience = EventAudience.friends
  @State private var replyTo: EventComment?
  @State private var isPosting = false
  @State private var errorMessage: String?

  var body: some View {
    ZStack {
      TunedInDesign.pageBackground.ignoresSafeArea()

      ScrollView {
        VStack(alignment: .leading, spacing: 18) {
        VStack(alignment: .leading, spacing: 12) {
          Text("Chat")
            .font(.largeTitle.weight(.bold))
            .foregroundStyle(TunedInDesign.primaryText)
          Text(detail.summary.title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(TunedInDesign.mutedText)

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

          if detail.comments.isEmpty {
            Text(detail.summary.phase() == .memories
              ? "No one posted before the show."
              : "Be the first to say what you’re excited for.")
              .font(.subheadline)
              .foregroundStyle(TunedInDesign.mutedText)
              .padding(.vertical, 12)
          } else {
            ForEach(detail.comments.sorted(by: { $0.createdAt < $1.createdAt })) { eventComment in
              EventCommentRow(
                comment: eventComment,
                onReply: detail.summary.phase() != .memories
                  && eventComment.parentCommentID == nil
                  && !eventComment.isDeleted
                  ? { replyTo = eventComment }
                  : nil
              )
            }
          }
        }
        .padding(20)
      }
      }

      EventScrollTopMask()
        .frame(maxHeight: .infinity, alignment: .top)
    }
    .safeAreaInset(edge: .bottom, spacing: 0) {
      TunedInPersistentControlRegion {
        TunedInSubscreenBackBar(title: "Chat", action: onDismiss)
          .padding(.horizontal, TunedInDesign.bottomControlHorizontalInset)
          .padding(.top, 6)
          .padding(.bottom, TunedInDesign.bottomControlInset)
      }
    }
    .task {
      if let remembered = EventAudience(rawValue: UserDefaults.standard.string(
        forKey: "community-event-comment-audience.\(viewerID.uuidString)"
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
      _ = try await repository.addComment(
        eventID: detail.id,
        authorID: viewerID,
        parentCommentID: replyTo?.id,
        body: comment,
        audience: audience
      )
      rememberPostAudience(audience)
      comment = ""
      replyTo = nil
      errorMessage = nil
      onChanged()
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  private func rememberPostAudience(_ audience: EventAudience) {
    UserDefaults.standard.set(
      audience.rawValue,
      forKey: "community-event-comment-audience.\(viewerID.uuidString)"
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
        Button(action: onViewAll) {
          HStack(spacing: 12) {
            EventAvatarStack(profiles: sortedAttendances.prefix(5).map(\.profile))
            VStack(alignment: .leading, spacing: 2) {
              Text(attendanceSummary)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(TunedInDesign.primaryText)
              Text("View everyone")
                .font(.caption)
                .foregroundStyle(TunedInDesign.mutedText)
            }
            Spacer()
            Image(systemName: "chevron.right")
              .font(.caption.weight(.bold))
              .foregroundStyle(TunedInDesign.mutedText)
          }
        }
        .buttonStyle(.plain)
      }
      Divider().overlay(TunedInDesign.cardBorder)
    }
  }

  private var sortedAttendances: [EventAttendance] {
    detail.attendances.sorted { lhs, rhs in
      let lhsRank = lhs.profile.id == viewerID ? 0 : (lhs.profile.relationship == .friends ? 1 : 2)
      let rhsRank = rhs.profile.id == viewerID ? 0 : (rhs.profile.relationship == .friends ? 1 : 2)
      if lhsRank != rhsRank {
        return lhsRank < rhsRank
      }
      return lhs.profile.displayName < rhs.profile.displayName
    }
  }

  private var attendanceSummary: String {
    let total = detail.attendances.count
    let suffix = detail.summary.phase() == .memories ? "went" : "going"
    return "\(total) \(total == 1 ? "person" : "people") \(suffix)"
  }
}

private struct EventMemoriesPage: View {
  let detail: CommunityEventDetail
  let viewerID: UUID
  let repository: any EventRepository
  let postRepository: any PostRepository
  let initialPostID: UUID?
  let onSaved: () -> Void

  @State private var isPresentingPost = false
  @State private var isPresentingAllPosts = false
  @State private var selectedPost: EventPostPreview?
  @State private var didOpenInitialPost = false

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      if !memoriesAreAvailable {
        HStack(spacing: 12) {
          Image(systemName: "lock.fill")
            .foregroundStyle(TunedInDesign.mutedText)
          VStack(alignment: .leading, spacing: 3) {
            Text("Memories unlock after the concert")
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
            Text("Memories")
              .font(.title2.weight(.bold))
              .foregroundStyle(TunedInDesign.primaryText)
            if let score = detail.summary.averagePostScore {
              HStack(spacing: 6) {
                CommunityEventScoreBadge(score: score, size: .compact)
                Text(
                  "average from \(detail.summary.postCount) visible "
                    + (detail.summary.postCount == 1 ? "memory" : "memories")
                )
                .font(.caption.weight(.semibold))
                .foregroundStyle(TunedInDesign.mutedText)
              }
            }
          }
          Spacer()
          if detail.summary.canCreatePost() {
            Button(myPost == nil ? "Add memory" : "Edit memory") {
              isPresentingPost = true
            }
            .font(.subheadline.weight(.bold))
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .tint(TunedInDesign.accent)
          }
        }

        if detail.postPreviews.isEmpty {
          Text("No memories yet. Going or Went still works without posting.")
            .font(.subheadline)
            .foregroundStyle(TunedInDesign.mutedText)
            .padding(.vertical, 12)
        } else {
          LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 3),
            spacing: 2
          ) {
            ForEach(previewPosts) { post in
              EventPostGridTile(
                post: post,
                viewerID: viewerID,
                postRepository: postRepository,
                onOpen: { selectedPost = post }
              )
            }
          }
          .padding(.horizontal, -20)

          if shouldShowAllPosts {
            Button { isPresentingAllPosts = true } label: {
              HStack {
                Text("View all \(detail.summary.postCount) memories")
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
    .fullScreenCover(isPresented: $isPresentingPost) {
      EventPostComposerView(
        event: detail.summary,
        viewerID: viewerID,
        repository: repository,
        postRepository: postRepository,
        existing: detail.postPreviews.first(where: { $0.author.id == viewerID }),
        onSaved: {
          isPresentingPost = false
          onSaved()
        },
        onDismiss: { isPresentingPost = false }
      )
    }
    .fullScreenCover(item: $selectedPost) { post in
      EventPostDetailView(
        event: detail.summary,
        post: post,
        viewerID: viewerID,
        postRepository: postRepository,
        onChanged: onSaved,
        onDismiss: { selectedPost = nil }
      )
    }
    .fullScreenCover(isPresented: $isPresentingAllPosts) {
      EventPostGalleryView(
        event: detail.summary,
        viewerID: viewerID,
        repository: repository,
        postRepository: postRepository,
        onChanged: onSaved,
        onDismiss: { isPresentingAllPosts = false }
      )
    }
    .task(id: initialPostID) {
      guard !didOpenInitialPost,
            let initialPostID,
            let post = detail.postPreviews.first(where: { $0.id == initialPostID })
      else { return }
      didOpenInitialPost = true
      selectedPost = post
    }
  }

  private var memoriesAreAvailable: Bool {
    detail.summary.phase() == .memories
      || (detail.summary.lifecycle == .cancelled && Date.now >= detail.summary.memoryUnlockAt)
  }

  private var sortedPosts: [EventPostPreview] {
    detail.postPreviews.sorted { lhs, rhs in
      let lhsRank = lhs.author.id == viewerID ? 0 : (lhs.author.relationship == .friends ? 1 : 2)
      let rhsRank = rhs.author.id == viewerID ? 0 : (rhs.author.relationship == .friends ? 1 : 2)
      if lhsRank != rhsRank {
        return lhsRank < rhsRank
      }
      return lhs.publishedAt > rhs.publishedAt
    }
  }

  private var myPost: EventPostPreview? {
    sortedPosts.first(where: { $0.author.id == viewerID })
  }

  private var previewPosts: [EventPostPreview] {
    Array(sortedPosts.prefix(6))
  }

  private var shouldShowAllPosts: Bool {
    detail.summary.postCount > previewPosts.count
  }
}

private struct EventPostComposerView: View {
  let event: CommunityEventSummary
  let viewerID: UUID
  let repository: any EventRepository
  let postRepository: any PostRepository
  let existing: EventPostPreview?
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
    postRepository: any PostRepository,
    existing: EventPostPreview?,
    onSaved: @escaping () -> Void,
    onDismiss: @escaping () -> Void
  ) {
    self.event = event
    self.viewerID = viewerID
    self.repository = repository
    self.postRepository = postRepository
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
          EventPostComposerHeader(
            event: event,
            existing: existing,
            postRepository: postRepository,
            photoSelection: $photoSelection,
            isSaving: isSaving
          )

          VStack(alignment: .leading, spacing: 0) {
            Text("Ratings")
              .font(.headline)
              .foregroundStyle(TunedInDesign.primaryText)
              .padding(.bottom, 10)

            PostScoreRow(
              title: "Overall",
              systemImage: "star.fill",
              isIncluded: $includesScore,
              value: $score
            )

            Divider()

            PostScoreRow(
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
              .foregroundStyle(note.count > 4000 ? TunedInDesign.accent : TunedInDesign.mutedText)
              .frame(maxWidth: .infinity, alignment: .trailing)
          }

          VStack(alignment: .leading, spacing: 16) {
            if (existing?.photoCount ?? 0) == 0 {
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
        EventPostActionBar(
          isSaving: isSaving,
          canSave: canSavePost,
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
        let postID: UUID = if let existingID = existing?.id {
          existingID
        } else {
          try await repository.preparePhotoPost(
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
          let data = try await PostImageProcessor.process(source)
          let reservation = try await postRepository.reserveMedia(
            postID: postID,
            mediaID: UUID()
          )
          _ = try await postRepository.uploadReservedMedia(
            data,
            reservation: reservation
          )
          uploadedCount += 1
        }
        hasReadyPhoto = hasReadyPhoto || uploadedCount > 0
      }
      _ = try await repository.savePost(
        eventID: event.id,
        authorID: viewerID,
        input: EventPostInput(
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

  private var hasPostContent: Bool {
    includesScore
      || includesPerformanceScore
      || CatalogInput.optionalNormalizedText(note) != nil
      || !photoSelection.isEmpty
      || (existing?.photoCount ?? 0) > 0
  }

  private var canSavePost: Bool {
    !isSaving && note.count <= 4000 && hasPostContent
  }
}

private struct EventPostActionBar: View {
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

private struct EventPostComposerHeader: View {
  let event: CommunityEventSummary
  let existing: EventPostPreview?
  let postRepository: any PostRepository
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

      if let existing, existing.photoCount > 0 {
        ZStack(alignment: .topTrailing) {
          PostMediaPreview(
            postID: existing.id,
            reportedPhotoCount: existing.photoCount,
            postRepository: postRepository,
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

private struct PostScoreRow: View {
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
    if let attendanceStatus = candidate.attendanceStatus {
      return attendanceStatus.title
    }
    if candidate.isAlreadyInvited {
      return "Invited"
    }
    return "@\(candidate.profile.username)"
  }
}
