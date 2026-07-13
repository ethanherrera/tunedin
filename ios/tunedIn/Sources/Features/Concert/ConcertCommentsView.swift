import SwiftUI

struct ConcertCommentsView: View {
  let concertID: UUID
  let viewerID: UUID
  let concertRepository: any ConcertRepository
  let pageHeader: AnyView

  @Environment(\.telemetry) private var telemetry

  @State private var comments: [ConcertComment] = []
  @State private var draft = ""
  @State private var editingCommentID: UUID?
  @State private var editDraft = ""
  @State private var isLoading = true
  @State private var isLoadingOlder = false
  @State private var canLoadOlder = false
  @State private var isSending = false
  @State private var loadErrorMessage: String?
  @State private var errorMessage: String?
  @State private var commentPendingDeletion: ConcertComment?

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      pageHeader

      if isLoading {
        loadingState
      } else if let loadErrorMessage, comments.isEmpty {
        loadFailure(message: loadErrorMessage)
      } else if comments.isEmpty {
        emptyState
      } else {
        commentList
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

  private var loadingState: some View {
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
  }

  private func loadFailure(message: String) -> some View {
    ContentUnavailableView {
      Label("Couldn’t open comments", systemImage: "exclamationmark.triangle")
    } description: {
      Text(message)
    } actions: {
      Button("Try again") {
        Task { await retryLoadComments() }
      }
    }
  }

  private var commentList: some View {
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
    loadErrorMessage = nil
    do {
      let loaded = try await concertRepository.comments(concertID: concertID, cursor: nil)
      comments = loaded
      canLoadOlder = loaded.count == 30
    } catch {
      loadErrorMessage = error.localizedDescription
    }
  }

  private func retryLoadComments() async {
    isLoading = true
    loadErrorMessage = nil
    await loadComments()
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
    let startedAt = ContinuousClock.now
    Task {
      do {
        let comment = try await concertRepository.createComment(concertID: concertID, body: text)
        comments.append(comment)
        draft = ""
        errorMessage = nil
        telemetry?.capture(
          .commentCreated,
          properties: [.durationMilliseconds: .integer(startedAt.duration(to: .now).commentTelemetryMilliseconds)]
        )
      } catch {
        let failure = AppFailure(error)
        if failure.shouldReportToTelemetry {
          telemetry?.captureOperation(
            .createComment,
            outcome: .failed,
            duration: startedAt.duration(to: .now),
            failure: failure
          )
        }
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

private extension Duration {
  var commentTelemetryMilliseconds: Int {
    let components = self.components
    return Int(components.seconds * 1_000 + components.attoseconds / 1_000_000_000_000_000)
  }
}
