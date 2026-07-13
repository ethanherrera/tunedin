import SwiftUI

struct ConcertPeopleView: View {
  let detail: ConcertDetail
  let viewerRole: ConcertViewerRole
  let viewerID: UUID?
  let viewerUsername: String
  let socialRepository: any SocialRepository
  let concertRepository: any ConcertRepository
  let onChanged: () -> Void
  let pageHeader: AnyView

  @State private var friends: [SocialProfile] = []
  @State private var visibility: ConcertVisibility
  @State private var isLoadingFriends = true
  @State private var isWorking = false
  @State private var errorMessage: String?
  @State private var isPresentingEditorPicker = false
  @State private var transferCandidate: ConcertCollaborator?
  @State private var isShowingTransferConfirmation = false
  @State private var removalCandidate: ConcertCollaborator?
  @State private var pendingAccessRestriction: ConcertVisibility?

  init(
    detail: ConcertDetail,
    viewerRole: ConcertViewerRole,
    viewerID: UUID? = nil,
    viewerUsername: String,
    socialRepository: any SocialRepository,
    concertRepository: any ConcertRepository,
    onChanged: @escaping () -> Void,
    pageHeader: AnyView
  ) {
    self.detail = detail
    self.viewerRole = viewerRole
    self.viewerID = viewerID
    self.viewerUsername = viewerUsername
    self.socialRepository = socialRepository
    self.concertRepository = concertRepository
    self.onChanged = onChanged
    self.pageHeader = pageHeader
    _visibility = State(initialValue: detail.concert.visibility)
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 18) {
        pageHeader
        header
        sharingControls

        if canAddPeople {
          addPeople
        }

        memberList

        if let errorMessage {
          ConcertPeopleErrorCard(message: errorMessage)
        }

        ConcertEditingHistoryView(events: detail.history)
      }
      .padding(.horizontal, 20)
      .padding(.top, 12)
      .padding(.bottom, 128)
    }
    .task {
      await loadFriends()
    }
    .onChange(of: detail.concert.version) { _, _ in
      visibility = detail.concert.visibility
    }
    .confirmationDialog(
      "Hand over this concert?",
      isPresented: $isShowingTransferConfirmation,
      titleVisibility: .visible,
      presenting: transferCandidate
    ) { candidate in
      Button("Make \(candidate.displayName) the owner", role: .destructive) {
        transfer(to: candidate)
      }
    } message: { candidate in
      Text(
        "\(candidate.displayName) becomes the owner immediately. "
          + "You remain an editor, but only they can delete or transfer the concert."
      )
    }
    .confirmationDialog(
      "Remove this editor?",
      isPresented: isShowingRemovalConfirmation,
      titleVisibility: .visible,
      presenting: removalCandidate
    ) { member in
      Button("Remove \(member.displayName)", role: .destructive) {
        remove(member)
        removalCandidate = nil
      }
      Button("Keep editor", role: .cancel) {
        removalCandidate = nil
      }
    } message: { member in
      Text(removalMessage(for: member))
    }
    .sheet(isPresented: $isPresentingEditorPicker) {
      ConcertEditorPickerView(friends: availableFriends) { friend in
        isPresentingEditorPicker = false
        add(friend)
      }
      .presentationDetents([.medium, .large])
      .presentationDragIndicator(.visible)
    }
  }

  private var header: some View {
    VStack(alignment: .leading, spacing: 5) {
      Text("The people in this night")
        .font(.system(size: 29, weight: .bold, design: .serif))
        .foregroundStyle(TunedInDesign.primaryText)
      Text(
        viewerRole.canManagePeople
          ? "Set sharing and choose who can help with this concert."
          : "See who helps with this concert."
      )
      .font(.subheadline)
      .foregroundStyle(TunedInDesign.mutedText)
    }
  }

  private var sharingControls: some View {
    ConcertSharingControls(
      visibility: visibility,
      canManagePeople: viewerRole.canManagePeople,
      canMakePrivate: viewerRole == .owner,
      isWorking: isWorking,
      selectVisibility: requestVisibilityChange,
      pendingAccessRestriction: pendingAccessRestriction,
      confirmAccessRestriction: { option in
        updateVisibility(to: option)
        pendingAccessRestriction = nil
      },
      cancelAccessRestriction: { pendingAccessRestriction = nil }
    )
  }

  @ViewBuilder
  private var addPeople: some View {
    if isLoadingFriends {
      VStack(spacing: 10) {
        ForEach(0 ..< 3, id: \.self) { _ in
          HStack(spacing: 12) {
            TunedInSkeletonBlock(cornerRadius: 23).frame(width: 46, height: 46)
            TunedInSkeletonBlock(cornerRadius: 6).frame(height: 16)
          }
        }
      }
      .accessibilityLabel("Loading friends")
    } else if availableFriends.isEmpty {
      TunedInFormCard {
        Text("No one else to add right now.")
          .font(.headline)
          .foregroundStyle(TunedInDesign.primaryText)
        Text("Only accepted friends can join a concert. Add a friend first, then return here.")
          .font(.subheadline)
          .foregroundStyle(TunedInDesign.mutedText)
      }
    } else {
      Button {
        isPresentingEditorPicker = true
      } label: {
        Label("Add a friend as an editor", systemImage: "person.badge.plus")
          .font(.headline)
          .foregroundStyle(TunedInDesign.actionForeground)
          .frame(maxWidth: .infinity)
          .padding(.vertical, 14)
          .background(TunedInDesign.accent, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
      }
      .buttonStyle(.plain)
      .disabled(isWorking)
    }
  }

  private var memberList: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("The circle")
        .font(.headline)
        .foregroundStyle(TunedInDesign.primaryText)

      if members.isEmpty {
        Text("This concert has no visible editor list yet.")
          .font(.subheadline)
          .foregroundStyle(TunedInDesign.mutedText)
      } else {
        ForEach(members) { member in
          memberRow(member)
        }
      }
    }
  }

  private func memberRow(_ member: ConcertCollaborator) -> some View {
    HStack(spacing: 12) {
      CollaboratorMonogram(member: member, size: 45)
      VStack(alignment: .leading, spacing: 2) {
        Text(member.displayName)
          .font(.headline)
          .foregroundStyle(TunedInDesign.primaryText)
        Text(member.isOwner ? "Owner" : "Editor")
          .font(.subheadline)
          .foregroundStyle(TunedInDesign.mutedText)
      }
      Spacer()
      if viewerRole == .owner, !member.isOwner {
        Menu {
          Button("Make owner") {
            transferCandidate = member
            isShowingTransferConfirmation = true
          }
          Button("Remove from concert", role: .destructive) {
            removalCandidate = member
          }
        } label: {
          Image(systemName: "ellipsis")
            .font(.headline.weight(.bold))
            .foregroundStyle(TunedInDesign.primaryText)
            .frame(width: 40, height: 40)
            .background(TunedInDesign.raisedSurface, in: Circle())
        }
        .disabled(isWorking)
      } else if member.isOwner {
        Text("OWNER")
          .font(.caption2.weight(.black))
          .foregroundStyle(TunedInDesign.accent)
      }
    }
    .padding(13)
    .background(TunedInDesign.cardBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .strokeBorder(TunedInDesign.cardBorder.opacity(0.72))
    }
  }

  private var members: [ConcertCollaborator] {
    detail.collaborators.sorted { lhs, rhs in
      if lhs.isOwner != rhs.isOwner {
        return lhs.isOwner
      }
      return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
    }
  }

  private var availableFriends: [SocialProfile] {
    friends.filter { friend in
      friend.id != detail.concert.ownerID && !members.contains(where: { $0.id == friend.id })
    }
  }

  private var canAddPeople: Bool {
    viewerRole.canManagePeople && visibility != .private
  }

  private func requestVisibilityChange(to option: ConcertVisibility) {
    guard option != visibility else { return }
    if option == .private || (visibility == .friends && option == .collaborators) {
      pendingAccessRestriction = option
    } else {
      updateVisibility(to: option)
    }
  }

  private func updateVisibility(to option: ConcertVisibility) {
    let draft = ConcertDraft(detail: detail)
    guard let input = draft.updateInput(
      concertID: detail.concert.id,
      expectedVersion: detail.concert.version,
      visibility: option
    ) else { return }

    isWorking = true
    Task {
      do {
        let updated = try await concertRepository.updateConcert(input)
        visibility = updated.visibility
        onChanged()
      } catch {
        errorMessage = error.localizedDescription
      }
      isWorking = false
    }
  }

  private func loadFriends() async {
    defer { isLoadingFriends = false }
    guard viewerRole.canManagePeople, !viewerUsername.isEmpty else { return }
    do {
      friends = try await socialRepository.friends(username: viewerUsername)
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  private func add(_ friend: SocialProfile) {
    perform {
      try await concertRepository.tagCollaborator(
        concertID: detail.concert.id,
        profileID: friend.id,
        expectedVersion: detail.concert.version
      )
    }
  }

  private func remove(_ member: ConcertCollaborator) {
    perform {
      try await concertRepository.removeCollaborator(
        concertID: detail.concert.id,
        profileID: member.id,
        expectedVersion: detail.concert.version
      )
    }
  }

  private func removalMessage(for member: ConcertCollaborator) -> String {
    if detail.concert.visibility == .friends {
      return "\(member.displayName) will immediately lose editor access without a copy. "
        + "As an accepted friend, they can still view and comment while this concert stays Friends-visible."
    }

    return "\(member.displayName) will immediately lose access without receiving a private copy."
  }

  private var isShowingRemovalConfirmation: Binding<Bool> {
    Binding(get: { removalCandidate != nil }, set: {
      if !$0 {
        removalCandidate = nil
      }
    })
  }

  private func transfer(to member: ConcertCollaborator) {
    perform {
      try await concertRepository.transferOwnership(
        concertID: detail.concert.id,
        newOwnerID: member.id,
        expectedVersion: detail.concert.version
      )
    }
  }

  private func perform(_ operation: @escaping @Sendable () async throws -> Concert) {
    isWorking = true
    Task {
      do {
        _ = try await operation()
        onChanged()
      } catch {
        errorMessage = error.localizedDescription
      }
      isWorking = false
    }
  }
}

private struct ConcertEditingHistoryView: View {
  let events: [ConcertTimelineEvent]

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Editing history")
        .font(.title3.weight(.bold))
        .foregroundStyle(TunedInDesign.primaryText)

      Text("Changes made by the people editing this concert.")
        .font(.subheadline)
        .foregroundStyle(TunedInDesign.mutedText)

      if events.isEmpty {
        Text("No edits recorded yet.")
          .font(.subheadline)
          .foregroundStyle(TunedInDesign.mutedText)
      } else {
        VStack(alignment: .leading, spacing: 14) {
          ForEach(events) { event in
            HStack(alignment: .top, spacing: 12) {
              Circle()
                .fill(TunedInDesign.accent)
                .frame(width: 8, height: 8)
                .padding(.top, 5)
              VStack(alignment: .leading, spacing: 3) {
                Text(event.title)
                  .font(.subheadline.weight(.semibold))
                  .foregroundStyle(TunedInDesign.primaryText)
                Text(ConcertDisplay.longDateTime(event.occurredAt))
                  .font(.caption)
                  .foregroundStyle(TunedInDesign.mutedText)
              }
            }
          }
        }
      }
    }
    .padding(16)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
      TunedInDesign.raisedSurface.opacity(0.6),
      in: RoundedRectangle(cornerRadius: 16, style: .continuous)
    )
    .accessibilityElement(children: .contain)
    .accessibilityLabel("Editing history")
  }
}

private struct ConcertPeopleErrorCard: View {
  let message: String

  var body: some View {
    TunedInFormCard {
      Label("Couldn’t change the circle", systemImage: "exclamationmark.triangle")
        .font(.headline)
        .foregroundStyle(TunedInDesign.primaryText)
      Text(message)
        .font(.subheadline)
        .foregroundStyle(TunedInDesign.mutedText)
    }
  }
}

private struct ConcertSharingControls: View {
  let visibility: ConcertVisibility
  let canManagePeople: Bool
  let canMakePrivate: Bool
  let isWorking: Bool
  let selectVisibility: (ConcertVisibility) -> Void
  let pendingAccessRestriction: ConcertVisibility?
  let confirmAccessRestriction: (ConcertVisibility) -> Void
  let cancelAccessRestriction: () -> Void
  @State private var isExpanded = false

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      sharingPill

      if isExpanded {
        sharingOptions
      }
    }
  }

  private var sharingPill: some View {
    Button {
      withAnimation(.snappy) { isExpanded.toggle() }
    } label: {
      HStack(spacing: 7) {
        Image(systemName: visibilityIcon)
        Text(visibility.displayTitle)
        if canManagePeople {
          Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
            .font(.caption.weight(.bold))
        }
      }
      .font(.caption.weight(.bold))
      .foregroundStyle(TunedInDesign.primaryText)
      .padding(.horizontal, 12)
      .padding(.vertical, 9)
      .background(TunedInDesign.raisedSurface, in: Capsule())
      .overlay {
        Capsule()
          .strokeBorder(TunedInDesign.cardBorder.opacity(0.72))
      }
    }
    .buttonStyle(.plain)
    .disabled(!canManagePeople)
    .accessibilityLabel("Sharing: \(visibility.displayTitle)")
    .accessibilityHint(canManagePeople ? "Shows sharing options" : "Only the owner can change sharing")
  }

  private var sharingOptions: some View {
    TunedInGlassSection {
      VStack(alignment: .leading, spacing: 10) {
        Text("Sharing")
          .font(.headline)
          .foregroundStyle(TunedInDesign.primaryText)

        if canManagePeople {
          HStack(spacing: 6) {
            ForEach(ConcertVisibility.allCases, id: \.rawValue) { option in
              visibilityToggle(option)
            }
          }
        }

        Text(visibilityDescription)
          .font(.subheadline)
          .foregroundStyle(TunedInDesign.mutedText)

        if !canMakePrivate, visibility != .private {
          Text("Only the owner can make this concert private.")
            .font(.caption.weight(.semibold))
            .foregroundStyle(TunedInDesign.mutedText)
        }

        if let pendingAccessRestriction {
          accessRestrictionConfirmation(for: pendingAccessRestriction)
        }
      }
    }
  }

  private var visibilityIcon: String {
    switch visibility {
    case .private: "lock.fill"
    case .collaborators: "person.2.fill"
    case .friends: "heart.fill"
    }
  }

  private func visibilityToggle(_ option: ConcertVisibility) -> some View {
    Button {
      selectVisibility(option)
    } label: {
      Text(option.displayTitle)
        .font(.caption.weight(.bold))
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .foregroundStyle(visibility == option ? TunedInDesign.actionForeground : TunedInDesign.primaryText)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(
          visibility == option ? TunedInDesign.accent : TunedInDesign.raisedSurface,
          in: Capsule()
        )
    }
    .buttonStyle(.plain)
    .disabled(isWorking || (option == .private && !canMakePrivate))
    .opacity(option == .private && !canMakePrivate ? 0.45 : 1)
  }

  private func accessRestrictionConfirmation(for option: ConcertVisibility) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      Divider()
        .overlay(TunedInDesign.cardBorder.opacity(0.5))

      Text(accessRestrictionTitle(for: option))
        .font(.subheadline.weight(.bold))
        .foregroundStyle(TunedInDesign.primaryText)

      Text(accessRestrictionDescription(for: option))
        .font(.caption)
        .foregroundStyle(TunedInDesign.mutedText)

      HStack(spacing: 8) {
        Button(cancelAccessRestrictionTitle(for: option)) {
          cancelAccessRestriction()
        }
        .buttonStyle(.plain)
        .font(.caption.weight(.bold))
        .foregroundStyle(TunedInDesign.primaryText)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(TunedInDesign.raisedSurface, in: Capsule())

        Button(confirmAccessRestrictionTitle(for: option)) {
          confirmAccessRestriction(option)
        }
        .buttonStyle(.plain)
        .font(.caption.weight(.bold))
        .foregroundStyle(.red)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(TunedInDesign.raisedSurface, in: Capsule())
      }
      .disabled(isWorking)
    }
  }

  private func accessRestrictionTitle(for option: ConcertVisibility) -> String {
    option == .private ? "Make this concert private?" : "Remove Friends access?"
  }

  private func accessRestrictionDescription(for option: ConcertVisibility) -> String {
    option == .private
      ? "Everyone you tagged will lose access immediately. You will be the only person who can see this concert."
      : "Friends who are not tagged editors will lose access. Tagged editors keep their role."
  }

  private func cancelAccessRestrictionTitle(for option: ConcertVisibility) -> String {
    option == .private ? "Keep sharing" : "Keep Friends"
  }

  private func confirmAccessRestrictionTitle(for option: ConcertVisibility) -> String {
    option == .private ? "Make Private" : "Limit to \(option.displayTitle)"
  }

  private var visibilityDescription: String {
    switch visibility {
    case .private:
      "Only you can see this concert. Pick Collaborators or Friends to share it."
    case .collaborators:
      "Only tagged editors can see and update this concert."
    case .friends:
      "Accepted friends can view and comment; tagged editors can update it."
    }
  }
}

private struct ConcertEditorPickerView: View {
  let friends: [SocialProfile]
  let onSelect: (SocialProfile) -> Void

  @Environment(\.dismiss) private var dismiss
  @State private var query = ""

  var body: some View {
    NavigationStack {
      ZStack {
        TunedInDesign.pageBackground
          .ignoresSafeArea()

        ScrollView {
          VStack(alignment: .leading, spacing: 12) {
            TunedInGlassSearchField(text: $query, prompt: "Search friends")

            if filteredFriends.isEmpty {
              ContentUnavailableView(
                query.isEmpty ? "No friends to add" : "No matching friends",
                systemImage: query.isEmpty ? "person.2" : "magnifyingglass",
                description: Text(
                  query.isEmpty
                    ? "Everyone eligible is already an editor."
                    : "Try a different name or @username."
                )
              )
              .frame(maxWidth: .infinity)
              .padding(.top, 56)
            } else {
              LazyVStack(spacing: 0) {
                ForEach(filteredFriends) { friend in
                  Button {
                    onSelect(friend)
                  } label: {
                    friendRow(friend)
                  }
                  .buttonStyle(.plain)
                  .accessibilityLabel("Add \(friend.displayName) as an editor")

                  if friend.id != filteredFriends.last?.id {
                    Divider()
                      .overlay(TunedInDesign.cardBorder.opacity(0.7))
                      .padding(.leading, 64)
                  }
                }
              }
              .padding(.top, 6)
            }
          }
          .padding(.horizontal, 20)
          .padding(.top, 12)
          .padding(.bottom, 32)
        }
      }
      .navigationTitle("Add an editor")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
        }
      }
    }
  }

  private var filteredFriends: [SocialProfile] {
    let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalizedQuery.isEmpty else { return friends }

    return friends.filter { friend in
      friend.displayName.localizedCaseInsensitiveContains(normalizedQuery)
        || friend.username.localizedCaseInsensitiveContains(normalizedQuery)
    }
  }

  private func friendRow(_ friend: SocialProfile) -> some View {
    HStack(spacing: 12) {
      ProfileAvatarView(profile: friend, size: 52)
      VStack(alignment: .leading, spacing: 2) {
        Text(friend.username)
          .font(.headline)
          .foregroundStyle(TunedInDesign.primaryText)
        Text(friend.displayName)
          .font(.subheadline)
          .foregroundStyle(TunedInDesign.mutedText)
      }
      Spacer(minLength: 0)
      Image(systemName: "plus.circle.fill")
        .font(.title3)
        .foregroundStyle(TunedInDesign.accent)
    }
    .padding(.vertical, 10)
    .contentShape(Rectangle())
  }
}

private extension ConcertVisibility {
  var displayTitle: String {
    switch self {
    case .private: "Private"
    case .collaborators: "Collaborators"
    case .friends: "Friends"
    }
  }
}

struct ConcertCommentsView: View {
  let concertID: UUID
  let viewerID: UUID
  let concertRepository: any ConcertRepository
  let pageHeader: AnyView

  @State private var comments: [ConcertComment] = []
  @State private var draft = ""
  @State private var editingCommentID: UUID?
  @State private var editDraft = ""
  @State private var isLoading = true
  @State private var isLoadingOlder = false
  @State private var canLoadOlder = false
  @State private var isSending = false
  @State private var errorMessage: String?
  @State private var commentPendingDeletion: ConcertComment?

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      pageHeader

      if isLoading {
        VStack(spacing: 12) {
          ForEach(0 ..< 3, id: \.self) { _ in
            HStack(alignment: .top, spacing: 11) {
              TunedInSkeletonBlock(cornerRadius: 20).frame(width: 40, height: 40)
              VStack(alignment: .leading, spacing: 8) {
                TunedInSkeletonBlock(cornerRadius: 5).frame(width: 124, height: 14)
                TunedInSkeletonBlock(cornerRadius: 9).frame(height: 48)
              }
            }
          }
        }
        .accessibilityLabel("Opening comments")
      } else if comments.isEmpty {
        emptyState
      } else {
        LazyVStack(alignment: .leading, spacing: 12) {
          if canLoadOlder {
            Button {
              Task { await loadOlderComments() }
            } label: {
              HStack(spacing: 8) {
                if isLoadingOlder {
                  ProgressView()
                }
                Text(isLoadingOlder ? "Loading earlier comments…" : "Show earlier comments")
              }
              .font(.subheadline.weight(.bold))
              .foregroundStyle(TunedInDesign.primaryText)
              .frame(maxWidth: .infinity)
              .padding(.vertical, 12)
              .background(TunedInDesign.raisedSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(isLoadingOlder)
          }
          ForEach(comments.sorted(by: { $0.createdAt < $1.createdAt })) { comment in
            commentCard(comment)
          }
        }
      }
      composer
    }
    .task { await loadComments() }
    .confirmationDialog(
      "Delete this comment?",
      isPresented: isShowingDeleteConfirmation,
      titleVisibility: .visible,
      presenting: commentPendingDeletion
    ) { comment in
      Button("Delete comment", role: .destructive) { delete(comment) }
    } message: { _ in
      Text("The history will keep a record that a comment was removed, but its text will be gone.")
    }
  }

  private var emptyState: some View {
    Text("No comments yet. Leave the first one.")
      .font(.subheadline)
      .foregroundStyle(TunedInDesign.mutedText)
      .padding(.horizontal, 4)
      .padding(.vertical, 12)
  }

  private var composer: some View {
    VStack(alignment: .leading, spacing: 8) {
      if let errorMessage {
        Text(errorMessage)
          .font(.caption)
          .foregroundStyle(.red)
      }
      HStack(alignment: .bottom, spacing: 10) {
        TextField("Leave a comment…", text: $draft, axis: .vertical)
          .lineLimit(1 ... 4)
          .textInputAutocapitalization(.sentences)
          .padding(.horizontal, 14)
          .padding(.vertical, 11)
          .background(TunedInDesign.raisedSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

        Button(action: send) {
          if isSending {
            ProgressView()
              .tint(TunedInDesign.actionForeground)
              .frame(width: 44, height: 44)
          } else {
            Image(systemName: "arrow.up")
              .font(.headline.weight(.black))
              .foregroundStyle(TunedInDesign.actionForeground)
              .frame(width: 44, height: 44)
          }
        }
        .buttonStyle(.plain)
        .background(TunedInDesign.accent, in: Circle())
        .disabled(isSending || ConcertInput.normalizedText(draft).isEmpty)
      }
    }
    .padding(.horizontal, 16)
    .padding(.top, 10)
    .padding(.bottom, 8)
  }

  private func commentCard(_ comment: ConcertComment) -> some View {
    HStack(alignment: .top, spacing: 11) {
      CommentMonogram(comment: comment)
      VStack(alignment: .leading, spacing: 5) {
        HStack(spacing: 7) {
          Text(comment.displayName)
            .font(.subheadline.weight(.bold))
            .foregroundStyle(TunedInDesign.primaryText)
          Text(ConcertDisplay.relativeDate(comment.createdAt))
            .font(.caption)
            .foregroundStyle(TunedInDesign.mutedText)
          Spacer()
          if comment.authorID == viewerID, !comment.isDeleted {
            Menu {
              Button("Edit") {
                editingCommentID = comment.id
                editDraft = comment.body ?? ""
              }
              Button("Delete", role: .destructive) {
                commentPendingDeletion = comment
              }
            } label: {
              Image(systemName: "ellipsis")
                .font(.caption.weight(.bold))
                .foregroundStyle(TunedInDesign.mutedText)
                .padding(5)
            }
          }
        }

        if editingCommentID == comment.id {
          TextField("Your comment", text: $editDraft, axis: .vertical)
            .lineLimit(1 ... 4)
            .padding(10)
            .background(TunedInDesign.raisedSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
          HStack {
            Button("Cancel") { editingCommentID = nil }
              .font(.caption.weight(.bold))
              .foregroundStyle(TunedInDesign.mutedText)
            Spacer()
            Button("Save") { update(comment) }
              .font(.caption.weight(.bold))
              .foregroundStyle(TunedInDesign.accent)
          }
        } else {
          Text(comment.isDeleted ? "This comment was removed." : (comment.body ?? ""))
            .font(.body)
            .italic(comment.isDeleted)
            .foregroundStyle(comment.isDeleted ? TunedInDesign.mutedText : TunedInDesign.primaryText)
        }
      }
    }
    .padding(14)
    .background(TunedInDesign.cardBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .strokeBorder(TunedInDesign.cardBorder.opacity(0.7))
    }
  }

  private var isShowingDeleteConfirmation: Binding<Bool> {
    Binding(get: { commentPendingDeletion != nil }, set: {
      if !$0 {
        commentPendingDeletion = nil
      }
    })
  }

  private func loadComments() async {
    defer { isLoading = false }
    do {
      let loaded = try await concertRepository.comments(concertID: concertID, cursor: nil)
      comments = loaded
      canLoadOlder = loaded.count == 30
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  private func loadOlderComments() async {
    guard let oldestComment = comments.min(by: isOlderComment), !isLoadingOlder else { return }
    isLoadingOlder = true

    do {
      let loaded = try await concertRepository.comments(
        concertID: concertID,
        cursor: ConcertCommentCursor(createdAt: oldestComment.createdAt, commentID: oldestComment.id)
      )
      comments.append(contentsOf: loaded)
      canLoadOlder = loaded.count == 30
      errorMessage = nil
    } catch {
      errorMessage = error.localizedDescription
    }

    isLoadingOlder = false
  }

  private func isOlderComment(_ lhs: ConcertComment, _ rhs: ConcertComment) -> Bool {
    if lhs.createdAt == rhs.createdAt {
      return lhs.id.uuidString < rhs.id.uuidString
    }
    return lhs.createdAt < rhs.createdAt
  }

  private func send() {
    let text = ConcertInput.normalizedText(draft)
    guard !text.isEmpty else { return }
    isSending = true
    Task {
      do {
        let comment = try await concertRepository.createComment(concertID: concertID, body: text)
        comments.append(comment)
        draft = ""
        errorMessage = nil
      } catch {
        errorMessage = error.localizedDescription
      }
      isSending = false
    }
  }

  private func update(_ comment: ConcertComment) {
    let text = ConcertInput.normalizedText(editDraft)
    guard !text.isEmpty else { return }
    Task {
      do {
        let updated = try await concertRepository.updateComment(commentID: comment.id, body: text)
        guard let index = comments.firstIndex(where: { $0.id == updated.id }) else { return }
        comments[index] = updated
        editingCommentID = nil
        errorMessage = nil
      } catch {
        errorMessage = error.localizedDescription
      }
    }
  }

  private func delete(_ comment: ConcertComment) {
    Task {
      do {
        try await concertRepository.deleteComment(commentID: comment.id)
        guard let index = comments.firstIndex(where: { $0.id == comment.id }) else { return }
        comments[index] = ConcertComment(
          id: comment.id,
          concertID: comment.concertID,
          authorID: comment.authorID,
          username: comment.username,
          displayName: comment.displayName,
          body: nil,
          createdAt: comment.createdAt,
          updatedAt: Date(),
          deletedAt: Date()
        )
        errorMessage = nil
      } catch {
        errorMessage = error.localizedDescription
      }
    }
  }
}
