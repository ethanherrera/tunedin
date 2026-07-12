import SwiftUI

struct ConcertPeopleView: View {
  let detail: ConcertDetail
  let viewerRole: ConcertViewerRole
  let viewerUsername: String
  let socialRepository: any SocialRepository
  let concertRepository: any ConcertRepository
  let onChanged: () -> Void
  let pageHeader: AnyView

  @State private var friends: [SocialProfile] = []
  @State private var visibility: ConcertVisibility
  @State private var hasBeenShared: Bool
  @State private var isLoadingFriends = true
  @State private var isWorking = false
  @State private var errorMessage: String?
  @State private var transferCandidate: ConcertCollaborator?
  @State private var isShowingTransferConfirmation = false
  @State private var removalCandidate: ConcertCollaborator?
  @State private var pendingVisibilityNarrowing: ConcertVisibility?

  init(
    detail: ConcertDetail,
    viewerRole: ConcertViewerRole,
    viewerUsername: String,
    socialRepository: any SocialRepository,
    concertRepository: any ConcertRepository,
    onChanged: @escaping () -> Void,
    pageHeader: AnyView
  ) {
    self.detail = detail
    self.viewerRole = viewerRole
    self.viewerUsername = viewerUsername
    self.socialRepository = socialRepository
    self.concertRepository = concertRepository
    self.onChanged = onChanged
    self.pageHeader = pageHeader
    _visibility = State(initialValue: detail.concert.visibility)
    _hasBeenShared = State(initialValue: detail.concert.visibility != .private)
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
      }
      .padding(.horizontal, 20)
      .padding(.top, 12)
      .padding(.bottom, 32)
    }
    .task {
      await loadFriends()
    }
    .onChange(of: detail.concert.version) { _, _ in
      visibility = detail.concert.visibility
      hasBeenShared = hasBeenShared || detail.concert.visibility != .private
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
      hasBeenShared: hasBeenShared,
      canManagePeople: viewerRole.canManagePeople,
      isWorking: isWorking,
      selectVisibility: requestVisibilityChange,
      pendingVisibilityNarrowing: pendingVisibilityNarrowing,
      confirmVisibilityNarrowing: { option in
        updateVisibility(to: option)
        pendingVisibilityNarrowing = nil
      },
      cancelVisibilityNarrowing: { pendingVisibilityNarrowing = nil }
    )
  }

  @ViewBuilder
  private var addPeople: some View {
    if isLoadingFriends {
      HStack(spacing: 10) {
        ProgressView()
        Text("Finding your friends…")
          .font(.subheadline)
          .foregroundStyle(TunedInDesign.mutedText)
      }
      .padding(.vertical, 8)
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
      Menu {
        ForEach(availableFriends) { friend in
          Button {
            add(friend)
          } label: {
            Label(friend.displayName, systemImage: "person.badge.plus")
          }
        }
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
    if visibility == .friends, option == .collaborators {
      pendingVisibilityNarrowing = option
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
        hasBeenShared = hasBeenShared || updated.visibility != .private
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
  let hasBeenShared: Bool
  let canManagePeople: Bool
  let isWorking: Bool
  let selectVisibility: (ConcertVisibility) -> Void
  let pendingVisibilityNarrowing: ConcertVisibility?
  let confirmVisibilityNarrowing: (ConcertVisibility) -> Void
  let cancelVisibilityNarrowing: () -> Void

  var body: some View {
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

        if hasBeenShared {
          Text("Shared concerts stay shared.")
            .font(.caption.weight(.semibold))
            .foregroundStyle(TunedInDesign.mutedText)
        }

        if let pendingVisibilityNarrowing {
          visibilityNarrowingConfirmation(for: pendingVisibilityNarrowing)
        }
      }
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
    .disabled(isWorking || (option == .private && hasBeenShared))
    .opacity(option == .private && hasBeenShared ? 0.45 : 1)
  }

  private func visibilityNarrowingConfirmation(for option: ConcertVisibility) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      Divider()
        .overlay(TunedInDesign.cardBorder.opacity(0.5))

      Text("Remove Friends access?")
        .font(.subheadline.weight(.bold))
        .foregroundStyle(TunedInDesign.primaryText)

      Text(
        "Friends who are not tagged editors will lose access. Tagged editors keep their role."
      )
      .font(.caption)
      .foregroundStyle(TunedInDesign.mutedText)

      HStack(spacing: 8) {
        Button("Keep Friends") {
          cancelVisibilityNarrowing()
        }
        .buttonStyle(.plain)
        .font(.caption.weight(.bold))
        .foregroundStyle(TunedInDesign.primaryText)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(TunedInDesign.raisedSurface, in: Capsule())

        Button("Limit to \(option.displayTitle)") {
          confirmVisibilityNarrowing(option)
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
    ScrollView {
      VStack(alignment: .leading, spacing: 12) {
        pageHeader

        if isLoading {
          ProgressView("Opening comments…")
            .frame(maxWidth: .infinity)
            .padding(.vertical, 120)
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
      }
      .padding(.horizontal, 20)
      .padding(.top, 10)
      .padding(.bottom, 16)
    }
    .safeAreaInset(edge: .bottom, spacing: 0) {
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
    VStack(alignment: .leading, spacing: 18) {
      TunedInTicketCard {
        Label("NO COMMENTS YET", systemImage: "text.bubble")
          .font(.caption.weight(.bold))
          .foregroundStyle(.white.opacity(0.8))
        Text("Leave the first comment.")
          .font(.system(size: 28, weight: .bold, design: .serif))
          .foregroundStyle(.white)
      }
    }
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
    .background(TunedInDesign.pageBackground.opacity(0.98))
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

private struct CollaboratorMonogram: View {
  let member: ConcertCollaborator
  let size: CGFloat

  var body: some View {
    Text(String(member.displayName.prefix(1)).uppercased())
      .font(.system(size: size * 0.38, weight: .black, design: .rounded))
      .foregroundStyle(TunedInDesign.actionForeground)
      .frame(width: size, height: size)
      .background(TunedInDesign.accentTint, in: Circle())
  }
}

private struct CommentMonogram: View {
  let comment: ConcertComment

  var body: some View {
    Text(String(comment.displayName.prefix(1)).uppercased())
      .font(.caption.weight(.black))
      .foregroundStyle(TunedInDesign.actionForeground)
      .frame(width: 32, height: 32)
      .background(TunedInDesign.accentTint, in: Circle())
  }
}
