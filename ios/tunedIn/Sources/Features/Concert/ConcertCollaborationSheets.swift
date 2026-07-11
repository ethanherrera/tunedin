import SwiftUI

struct ConcertPeopleSheet: View {
  let detail: ConcertDetail
  let viewerRole: ConcertViewerRole
  let viewerUsername: String
  let socialRepository: any SocialRepository
  let concertRepository: any ConcertRepository
  let onChanged: () -> Void

  @Environment(\.dismiss) private var dismiss
  @State private var friends: [SocialProfile] = []
  @State private var isLoadingFriends = true
  @State private var isWorking = false
  @State private var errorMessage: String?
  @State private var transferCandidate: ConcertCollaborator?
  @State private var isShowingTransferConfirmation = false

  var body: some View {
    NavigationStack {
      ZStack {
        TunedInDesign.pageBackground
          .ignoresSafeArea()

        ScrollView {
          VStack(alignment: .leading, spacing: 18) {
            header
            membershipSummary

            if canAddPeople {
              addPeople
            } else if viewerRole.canManagePeople {
              privateBoundary
            }

            memberList

            if let errorMessage {
              TunedInFormCard {
                Label("Couldn’t change the circle", systemImage: "exclamationmark.triangle")
                  .font(.headline)
                  .foregroundStyle(TunedInDesign.primaryText)
                Text(errorMessage)
                  .font(.subheadline)
                  .foregroundStyle(TunedInDesign.mutedText)
              }
            }
          }
          .padding(.horizontal, 20)
          .padding(.top, 12)
          .padding(.bottom, 32)
        }
      }
      .navigationTitle("People")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button("Done") { dismiss() }
            .disabled(isWorking)
        }
      }
    }
    .task {
      await loadFriends()
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
      Text("\(candidate.displayName) becomes the owner immediately. You will remain an editor, but only they can delete the concert or transfer it again.")
    }
  }

  private var header: some View {
    VStack(alignment: .leading, spacing: 5) {
      Text("The people in this night")
        .font(.system(size: 29, weight: .bold, design: .serif))
        .foregroundStyle(TunedInDesign.primaryText)
      Text(viewerRole == .owner ? "Keep the edit circle intentional." : "Editors can help shape the details together.")
        .font(.subheadline)
        .foregroundStyle(TunedInDesign.mutedText)
    }
  }

  private var membershipSummary: some View {
    TunedInGlassSection {
      HStack(alignment: .top, spacing: 12) {
        Image(systemName: "person.2.fill")
          .font(.title3)
          .foregroundStyle(TunedInDesign.accent)
          .frame(width: 30)
        VStack(alignment: .leading, spacing: 4) {
          Text("Editors can change the night")
            .font(.headline)
            .foregroundStyle(TunedInDesign.primaryText)
          Text("Friends can look in when visibility is Friends, but they cannot change anything unless you add them here.")
            .font(.subheadline)
            .foregroundStyle(TunedInDesign.mutedText)
        }
      }
    }
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

  private var privateBoundary: some View {
    TunedInFormCard {
      Label("This night is still private", systemImage: "lock.fill")
        .font(.headline)
        .foregroundStyle(TunedInDesign.primaryText)
      Text("Choose Collaborators or Friends in Shape before inviting someone to edit it.")
        .font(.subheadline)
        .foregroundStyle(TunedInDesign.mutedText)
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
            remove(member)
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
    viewerRole.canManagePeople && detail.concert.visibility != .private
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
        dismiss()
      } catch {
        errorMessage = error.localizedDescription
      }
      isWorking = false
    }
  }
}

struct ConcertCommentsSheet: View {
  let concertID: UUID
  let viewerID: UUID
  let concertRepository: any ConcertRepository

  @Environment(\.dismiss) private var dismiss
  @State private var comments: [ConcertComment] = []
  @State private var draft = ""
  @State private var editingCommentID: UUID?
  @State private var editDraft = ""
  @State private var isLoading = true
  @State private var isSending = false
  @State private var errorMessage: String?
  @State private var commentPendingDeletion: ConcertComment?

  var body: some View {
    NavigationStack {
      ZStack {
        TunedInDesign.pageBackground
          .ignoresSafeArea()

        VStack(spacing: 0) {
          if isLoading {
            Spacer()
            ProgressView("Opening notes…")
            Spacer()
          } else if comments.isEmpty {
            emptyState
          } else {
            ScrollView {
              LazyVStack(alignment: .leading, spacing: 12) {
                ForEach(comments.sorted(by: { $0.createdAt < $1.createdAt })) { comment in
                  commentCard(comment)
                }
              }
              .padding(.horizontal, 20)
              .padding(.top, 12)
              .padding(.bottom, 16)
            }
          }
        }
      }
      .navigationTitle("Notes")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button("Done") { dismiss() }
        }
      }
      .safeAreaInset(edge: .bottom, spacing: 0) {
        composer
      }
    }
    .task { await loadComments() }
    .confirmationDialog(
      "Delete this note?",
      isPresented: isShowingDeleteConfirmation,
      titleVisibility: .visible,
      presenting: commentPendingDeletion
    ) { comment in
      Button("Delete note", role: .destructive) { delete(comment) }
    } message: { _ in
      Text("The history will keep a record that a note was removed, but its text will be gone.")
    }
  }

  private var emptyState: some View {
    VStack(alignment: .leading, spacing: 18) {
      Spacer()
      TunedInTicketCard {
        Label("NO NOTES YET", systemImage: "text.bubble")
          .font(.caption.weight(.bold))
          .foregroundStyle(.white.opacity(0.8))
        Text("Leave the first little thing that stayed with you.")
          .font(.system(size: 28, weight: .bold, design: .serif))
          .foregroundStyle(.white)
      }
      Spacer()
    }
    .padding(.horizontal, 20)
  }

  private var composer: some View {
    VStack(alignment: .leading, spacing: 8) {
      if let errorMessage {
        Text(errorMessage)
          .font(.caption)
          .foregroundStyle(.red)
      }
      HStack(alignment: .bottom, spacing: 10) {
        TextField("Leave a note…", text: $draft, axis: .vertical)
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
          TextField("Your note", text: $editDraft, axis: .vertical)
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
          Text(comment.isDeleted ? "This note was removed." : (comment.body ?? ""))
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
      comments = try await concertRepository.comments(concertID: concertID, cursor: nil)
    } catch {
      errorMessage = error.localizedDescription
    }
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
