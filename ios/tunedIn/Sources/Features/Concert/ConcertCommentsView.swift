import SwiftUI

struct ConcertCommentsView: View {
  let concertID: UUID
  let viewerID: UUID
  let viewerUsername: String
  let concertRepository: any ConcertRepository
  let model: ConcertCommentsModel
  @Binding var selectedDetent: PresentationDetent

  @Environment(\.telemetry) private var telemetry
  @FocusState private var isComposerFocused: Bool
  @State private var draft = ""
  @State private var editingCommentID: UUID?
  @State private var editDraft = ""
  @State private var errorMessage: String?
  @State private var commentPendingDeletion: ConcertComment?
  @State private var successFeedback = 0
  @State private var failureFeedback = 0

  var body: some View {
    VStack(spacing: 0) {
      momentsHeader

      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          if let errorMessage {
            Label(errorMessage, systemImage: "exclamationmark.triangle")
              .font(.caption)
              .foregroundStyle(.orange)
          }

          if model.isLoading {
            loadingState
          } else if let loadErrorMessage = model.loadErrorMessage, !hasComments {
            loadFailure(message: loadErrorMessage)
          } else if !hasComments {
            emptyState
          } else {
            commentList
          }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
      }

      composer
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 10)
        .background(.bar)
    }
    .background(TunedInDesign.pageBackground)
    .tunedInKeyboardManaged()
    .task { await model.loadComments(policy: .automatic) }
    .onChange(of: isComposerFocused) { _, isFocused in
      if isFocused {
        selectedDetent = .large
      }
    }
    .sensoryFeedback(.success, trigger: successFeedback)
    .sensoryFeedback(.error, trigger: failureFeedback)
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

  private var momentsHeader: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text("Moments")
        .font(.system(size: 30, weight: .bold, design: .rounded))
        .foregroundStyle(TunedInDesign.primaryText)
      Text("The details everyone remembers differently.")
        .font(.subheadline)
        .foregroundStyle(TunedInDesign.mutedText)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.horizontal, 20)
    .padding(.top, 8)
    .padding(.bottom, 12)
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
        Task { await model.retryLoadComments() }
      }
    }
  }

  private var commentList: some View {
    LazyVStack(alignment: .leading, spacing: 0) {
      if let loadErrorMessage = model.loadErrorMessage {
        Label(loadErrorMessage, systemImage: "exclamationmark.triangle")
          .font(.caption)
          .foregroundStyle(.orange)
      }

      if model.canLoadOlder {
        Button {
          Task { await model.loadOlderComments() }
        } label: {
          HStack(spacing: 8) {
            if model.isLoadingOlder {
              ProgressView()
            }
            Text(model.isLoadingOlder ? "Loading earlier comments…" : "Show earlier comments")
          }
          .font(.subheadline.weight(.bold))
          .foregroundStyle(TunedInDesign.primaryText)
          .frame(maxWidth: .infinity)
          .padding(.vertical, 12)
          .background(TunedInDesign.accentTint, in: Capsule())
          .padding(.bottom, 8)
        }
        .buttonStyle(.plain)
        .disabled(model.isLoadingOlder)
      }
      ForEach(model.comments.sorted(by: { $0.createdAt < $1.createdAt })) { comment in
        commentCard(comment)
      }
      ForEach(model.optimisticComments) { comment in
        OptimisticConcertCommentRow(
          comment: comment,
          viewerUsername: viewerUsername,
          onRetry: retry
        )
      }
    }
  }

  private var emptyState: some View {
    Label("No comments yet — start the conversation.", systemImage: "bubble.left")
      .font(.subheadline)
      .foregroundStyle(TunedInDesign.mutedText)
      .padding(.horizontal, 4)
      .padding(.vertical, 16)
  }

  private var composer: some View {
    HStack(alignment: .bottom, spacing: 10) {
      TextField("Leave a moment…", text: $draft, axis: .vertical)
        .lineLimit(1 ... 4)
        .textInputAutocapitalization(.sentences)
        .submitLabel(.send)
        .focused($isComposerFocused)
        .onSubmit(send)
        .padding(.leading, 14)
        .padding(.vertical, 10)

      Button(action: send) {
        Image(systemName: "arrow.up")
          .font(.headline.weight(.black))
          .foregroundStyle(TunedInDesign.actionForeground)
          .frame(width: 40, height: 40)
      }
      .buttonStyle(.plain)
      .background(TunedInDesign.accent, in: Circle())
      .disabled(ConcertInput.normalizedText(draft).isEmpty)
      .accessibilityLabel("Post moment")
    }
    .padding(5)
    .background(TunedInDesign.raisedSurface, in: RoundedRectangle(cornerRadius: 23, style: .continuous))
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
    .padding(.vertical, 14)
    .overlay(alignment: .bottom) {
      Divider()
        .overlay(TunedInDesign.cardBorder.opacity(0.5))
        .padding(.leading, 51)
    }
  }

  private var isShowingDeleteConfirmation: Binding<Bool> {
    Binding(get: { commentPendingDeletion != nil }, set: {
      if !$0 {
        commentPendingDeletion = nil
      }
    })
  }

  private var hasComments: Bool {
    !model.comments.isEmpty || !model.optimisticComments.isEmpty
  }

  private func send() {
    let text = ConcertInput.normalizedText(draft)
    guard !text.isEmpty else { return }
    let commentID = model.enqueueOptimisticComment(body: text)
    draft = ""
    postOptimisticComment(id: commentID)
  }

  private func retry(_ comment: OptimisticConcertComment) {
    model.markOptimisticCommentPosting(id: comment.id)
    postOptimisticComment(id: comment.id)
  }

  private func postOptimisticComment(id: UUID) {
    let startedAt = ContinuousClock.now
    Task {
      do {
        try await model.postOptimisticComment(id: id)
        errorMessage = nil
        successFeedback += 1
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
        failureFeedback += 1
      }
    }
  }

  private func update(_ comment: ConcertComment) {
    let text = ConcertInput.normalizedText(editDraft)
    guard !text.isEmpty else { return }
    Task {
      do {
        let updated = try await concertRepository.updateComment(commentID: comment.id, body: text)
        guard let index = model.comments.firstIndex(where: { $0.id == updated.id }) else { return }
        model.comments[index] = updated
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
        try await concertRepository.deleteComment(
          commentID: comment.id,
          concertID: comment.concertID
        )
        guard let index = model.comments.firstIndex(where: { $0.id == comment.id }) else { return }
        model.comments[index] = ConcertComment(
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
    let components = components
    return Int(components.seconds * 1000 + components.attoseconds / 1_000_000_000_000_000)
  }
}
