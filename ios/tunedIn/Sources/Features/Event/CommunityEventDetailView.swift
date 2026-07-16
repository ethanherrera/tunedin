import SwiftUI

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
  let onDismiss: () -> Void

  @State private var detail: CommunityEventDetail?
  @State private var selectedPage = Page.event
  @State private var isLoading = true
  @State private var errorMessage: String?
  @State private var isPresentingInvites = false
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
              }
            )

            switch selectedPage {
            case .event:
              EventOverviewPage(
                detail: detail,
                viewerID: viewerID,
                repository: repository,
                allowsConversation: repository.capabilities.contains(.conversation),
                onPostAdded: { Task { await load() } }
              )
            case .people:
              EventPeoplePage(detail: detail)
            case .memories:
              EventMemoriesPage(
                detail: detail,
                viewerID: viewerID,
                repository: repository,
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
      if repository.capabilities.contains(.invitations) {
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
}

private struct CommunityEventHero: View {
  let detail: CommunityEventDetail
  let allowsAttendance: Bool
  let onSetAttendance: (EventAttendanceStatus?, EventAudience) -> Void

  @State private var audience = EventAudience.friends

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      HStack(alignment: .top, spacing: 16) {
        EventDateTile(date: detail.summary.eventDate)
        VStack(alignment: .leading, spacing: 6) {
          Text(detail.summary.title)
            .font(.system(.title, design: .rounded, weight: .bold))
            .foregroundStyle(TunedInDesign.primaryText)
          Text("\(detail.summary.venueName) · \(detail.summary.areaName)")
            .font(.subheadline.weight(.medium))
            .foregroundStyle(TunedInDesign.mutedText)
          phaseLabel
        }
      }

      Divider().overlay(TunedInDesign.cardBorder)

      if allowsAttendance,
         detail.summary.phase() != .cancelled || detail.summary.currentUserAttendance != nil {
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

      if !detail.summary.friendPreviews.isEmpty {
        HStack(spacing: 10) {
          EventAvatarStack(profiles: detail.summary.friendPreviews.map(\.profile))
          Text(friendLine)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(TunedInDesign.primaryText)
        }
      }
    }
    .padding(18)
    .background(
      LinearGradient(
        colors: [TunedInDesign.accentTint, TunedInDesign.cardBackground],
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
      case .went: return "I went"
      case .didNotGo: return "I didn’t go"
      case nil: return "Add to my history"
      }
    }
    return detail.summary.currentUserAttendance == nil ? "I’m going" : "Added to my plans"
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
  private var phaseLabel: some View {
    switch detail.summary.phase() {
    case .upcoming:
      Label(detail.summary.sourceLabel, systemImage: "person.3.fill")
        .foregroundStyle(TunedInDesign.accent)
    case .postponed:
      Label("Postponed", systemImage: "clock.badge.exclamationmark")
        .foregroundStyle(TunedInDesign.accent)
    case .cancelled:
      Label("Cancelled", systemImage: "xmark.circle.fill")
        .foregroundStyle(TunedInDesign.accent)
    case .memories:
      Label("Memories unlocked", systemImage: "sparkles")
        .foregroundStyle(TunedInDesign.accent)
    }
  }

  private var friendLine: String {
    let names = detail.summary.friendPreviews.prefix(2).map { $0.profile.displayName }
    let total = detail.summary.friendPreviews.count
    if total == 1, let name = names.first {
      return name + " is going"
    }
    let remainder = total - names.count
    return names.joined(separator: " and ")
      + (remainder > 0 ? " + \(remainder) more are going" : " are going")
  }
}

private struct EventOverviewPage: View {
  let detail: CommunityEventDetail
  let viewerID: UUID
  let repository: any EventRepository
  let allowsConversation: Bool
  let onPostAdded: () -> Void

  @State private var comment = ""
  @State private var audience = EventAudience.friends
  @State private var isPosting = false
  @State private var errorMessage: String?

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      TunedInFormCard {
        Label("Event details", systemImage: "calendar")
          .font(.headline)
          .foregroundStyle(TunedInDesign.primaryText)
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
      }

      if allowsConversation {
        VStack(alignment: .leading, spacing: 12) {
        Text(detail.summary.phase() == .memories ? "What people remember" : "Before the show")
          .font(.headline)
          .foregroundStyle(TunedInDesign.primaryText)

        if detail.summary.phase() != .memories {
          HStack(spacing: 8) {
            TextField("What are you excited for?", text: $comment, axis: .vertical)
              .lineLimit(1 ... 4)
              .padding(12)
              .background(TunedInDesign.raisedSurface, in: RoundedRectangle(cornerRadius: 14))

            Menu {
              ForEach([EventAudience.friends, .community], id: \.self) { option in
                Button(option.title) { audience = option }
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
          Text("No comments yet. Start the conversation with your friends.")
            .font(.subheadline)
            .foregroundStyle(TunedInDesign.mutedText)
            .padding(.vertical, 12)
        } else {
          ForEach(detail.posts.sorted(by: { $0.createdAt > $1.createdAt })) { post in
            EventPostRow(post: post)
          }
        }
        }
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
        body: comment,
        audience: audience
      )
      comment = ""
      errorMessage = nil
      onPostAdded()
    } catch {
      errorMessage = error.localizedDescription
    }
  }
}

private struct EventPeoplePage: View {
  let detail: CommunityEventDetail

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
        ForEach(detail.attendances) { attendance in
          HStack(spacing: 12) {
            ProfileAvatarView(profile: attendance.profile, size: 46)
            VStack(alignment: .leading, spacing: 3) {
              Text(attendance.profile.displayName)
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
          .padding(14)
          .background(TunedInDesign.cardBackground, in: RoundedRectangle(cornerRadius: 18))
        }
      }
    }
  }
}

private struct EventMemoriesPage: View {
  let detail: CommunityEventDetail
  let viewerID: UUID
  let repository: any EventRepository
  let onSaved: () -> Void

  @State private var isPresentingDiary = false

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      if detail.summary.phase() != .memories {
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
          ForEach(detail.diaryPreviews.sorted(by: { $0.publishedAt > $1.publishedAt })) { diary in
            EventDiaryPreviewCard(diary: diary)
          }
        }
      }
    }
    .fullScreenCover(isPresented: $isPresentingDiary) {
      EventDiaryComposerView(
        eventID: detail.id,
        viewerID: viewerID,
        repository: repository,
        existing: detail.diaryPreviews.first(where: { $0.author.id == viewerID }),
        onSaved: {
          isPresentingDiary = false
          onSaved()
        },
        onDismiss: { isPresentingDiary = false }
      )
    }
  }
}

private struct EventDiaryComposerView: View {
  let eventID: UUID
  let viewerID: UUID
  let repository: any EventRepository
  let existing: EventDiaryPreview?
  let onSaved: () -> Void
  let onDismiss: () -> Void

  @State private var includesScore: Bool
  @State private var score: Double
  @State private var note: String
  @State private var audience: EventAudience
  @State private var isSaving = false
  @State private var errorMessage: String?

  init(
    eventID: UUID,
    viewerID: UUID,
    repository: any EventRepository,
    existing: EventDiaryPreview?,
    onSaved: @escaping () -> Void,
    onDismiss: @escaping () -> Void
  ) {
    self.eventID = eventID
    self.viewerID = viewerID
    self.repository = repository
    self.existing = existing
    self.onSaved = onSaved
    self.onDismiss = onDismiss
    _includesScore = State(initialValue: existing?.score != nil)
    _score = State(initialValue: existing?.score ?? 8)
    _note = State(initialValue: existing?.note ?? "")
    _audience = State(initialValue: existing?.audience ?? .friends)
  }

  var body: some View {
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
              Slider(value: $score, in: 0 ... 10, step: 0.1)
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
              "Photos and video will attach to this diary when persistent media support lands.",
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
          .disabled(isSaving || note.count > 4_000)
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
      _ = try await repository.saveDiary(
        eventID: eventID,
        authorID: viewerID,
        input: EventDiaryInput(
          score: includesScore ? score : nil,
          note: note,
          audience: audience
        )
      )
      errorMessage = nil
      onSaved()
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
