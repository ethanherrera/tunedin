import PhotosUI
import SwiftUI

struct EventPostDetailView: View {
  let event: CommunityEventSummary
  let post: EventPostPreview
  let viewerID: UUID
  let postRepository: any PostRepository
  let onChanged: () -> Void
  let onDismiss: () -> Void

  @State private var photos: [PostMedia] = []
  @State private var comments: [PostComment] = []
  @State private var photoSelection: [PhotosPickerItem] = []
  @State private var commentDraft = ""
  @State private var isLoading = true
  @State private var isUploading = false
  @State private var isPosting = false
  @State private var errorMessage: String?

  var body: some View {
    ZStack {
      TunedInDesign.pageBackground.ignoresSafeArea()

      ScrollView {
        VStack(alignment: .leading, spacing: 20) {
          postAuthorHeader
          postMediaSection
          postReview
          postCommentSection

          if let errorMessage {
            Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
              .font(.caption.weight(.semibold))
              .foregroundStyle(.orange)
          }
        }
        .padding(20)
        .padding(.bottom, 96)
      }
      .refreshable { await load() }

      EventScrollTopMask()
        .frame(maxHeight: .infinity, alignment: .top)
    }
    .safeAreaInset(edge: .bottom, spacing: 0) {
      TunedInPersistentControlRegion {
        TunedInSubscreenBackBar(title: "Back to concert", action: onDismiss)
          .padding(.horizontal, TunedInDesign.bottomControlHorizontalInset)
          .padding(.top, 8)
          .padding(.bottom, TunedInDesign.bottomControlInset)
      }
    }
    .tunedInEdgeSwipeBack(action: onDismiss)
    .task { await load() }
    .onChange(of: photoSelection) { _, items in
      guard !items.isEmpty else { return }
      photoSelection = []
      Task { await upload(items) }
    }
  }

  private var postAuthorHeader: some View {
    HStack(spacing: 12) {
      SocialProfileButton(profile: post.author) {
        ProfileAvatarView(profile: post.author, size: 44)
      }
      VStack(alignment: .leading, spacing: 3) {
        HStack(spacing: 5) {
          SocialProfileButton(profile: post.author) {
            Text(post.author.displayName)
              .fontWeight(.bold)
              .foregroundStyle(TunedInDesign.primaryText)
          }
          Image(systemName: post.audience.icon)
            .font(.caption2)
        }
        .font(.subheadline)
        .foregroundStyle(TunedInDesign.primaryText)
        Text("\(event.headlinerName) · \(event.venueName)")
          .font(.caption)
          .foregroundStyle(TunedInDesign.mutedText)
          .lineLimit(1)
        Text(CommunityEventDateText.fullDate(event.eventDate))
          .font(.caption)
          .foregroundStyle(TunedInDesign.mutedText)
      }
      Spacer()
      if let score = post.score {
        CommunityEventScoreBadge(score: score, size: .large)
      }
    }
  }

  @ViewBuilder
  private var postMediaSection: some View {
    let uploadTitle = isUploading ? "Adding…" : "Add"
    if isLoading, post.photoCount > 0, photos.isEmpty {
      TunedInSkeletonBlock(cornerRadius: 20)
        .aspectRatio(0.8, contentMode: .fit)
    } else if !photos.isEmpty {
      VStack(alignment: .trailing, spacing: 8) {
        if post.author.id == viewerID {
          PhotosPicker(
            selection: $photoSelection,
            maxSelectionCount: 10,
            matching: .images
          ) {
            Label(uploadTitle, systemImage: "photo.badge.plus")
              .font(.subheadline.weight(.bold))
          }
          .disabled(isUploading)
        }
        TabView {
          ForEach(photos) { photo in
            PostMediaImage(photo: photo, postRepository: postRepository)
              .frame(maxWidth: .infinity, maxHeight: .infinity)
          }
        }
        .tabViewStyle(.page(indexDisplayMode: photos.count > 1 ? .automatic : .never))
        .frame(height: 468)
        .padding(.horizontal, -20)
      }
    } else if post.author.id == viewerID {
      PhotosPicker(
        selection: $photoSelection,
        maxSelectionCount: 10,
        matching: .images
      ) {
        Label(uploadTitle == "Add" ? "Add photos" : uploadTitle, systemImage: "photo.badge.plus")
          .font(.subheadline.weight(.bold))
          .foregroundStyle(TunedInDesign.primaryText)
          .padding(.vertical, 8)
      }
      .disabled(isUploading)
    }
  }

  private var postReview: some View {
    VStack(alignment: .leading, spacing: 12) {
      if let note = post.note {
        Text(note)
          .font(.body)
          .foregroundStyle(TunedInDesign.primaryText)
      }

      PostEngagementLine(post: post)
    }
  }

  private var postCommentSection: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Comments")
        .font(.headline)
        .foregroundStyle(TunedInDesign.primaryText)

      HStack(alignment: .bottom, spacing: 10) {
        TextField("Leave a comment", text: $commentDraft, axis: .vertical)
          .lineLimit(1 ... 4)
          .padding(.horizontal, 14)
          .padding(.vertical, 11)
          .background(TunedInDesign.raisedSurface, in: RoundedRectangle(cornerRadius: 16))
        Button { Task { await postComment() } } label: {
          Image(systemName: "arrow.up")
            .font(.headline.weight(.bold))
            .foregroundStyle(TunedInDesign.actionForeground)
            .frame(width: 44, height: 44)
            .background(TunedInDesign.accent, in: Circle())
        }
        .disabled(isPosting || CatalogInput.optionalNormalizedText(commentDraft) == nil)
        .accessibilityLabel("Post comment")
      }

      if isLoading, comments.isEmpty {
        TunedInSkeletonBlock(cornerRadius: 18).frame(height: 76)
      } else if comments.isEmpty {
        Text("No comments yet.")
          .font(.subheadline)
          .foregroundStyle(TunedInDesign.mutedText)
      } else {
        ForEach(comments) { comment in
          EventPostCommentRow(comment: comment)
          Divider().overlay(TunedInDesign.cardBorder)
        }
      }
    }
  }

  @MainActor
  private func load() async {
    isLoading = photos.isEmpty && comments.isEmpty
    defer { isLoading = false }
    do {
      async let loadedPhotos = postRepository.media(
        postID: post.id,
        cursor: nil
      )
      async let loadedComments = postRepository.comments(
        postID: post.id,
        cursor: nil
      )
      (photos, comments) = try await (loadedPhotos, loadedComments)
      errorMessage = nil
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  @MainActor
  private func upload(_ items: [PhotosPickerItem]) async {
    guard post.author.id == viewerID, !isUploading else { return }
    isUploading = true
    defer { isUploading = false }
    var failures = 0
    for item in items {
      do {
        guard let source = try await item.loadTransferable(type: Data.self) else {
          throw AppFailure.unexpected
        }
        let data = try await PostImageProcessor.process(source)
        let mediaID = UUID()
        let reservation = try await postRepository.reserveMedia(
          postID: post.id,
          mediaID: mediaID
        )
        let photo = try await postRepository.uploadReservedMedia(
          data,
          reservation: reservation
        )
        photos.insert(photo, at: 0)
      } catch {
        failures += 1
        errorMessage = error.localizedDescription
      }
    }
    if failures == 0 { errorMessage = nil }
    if items.count > failures { onChanged() }
  }

  @MainActor
  private func postComment() async {
    guard let body = CatalogInput.optionalNormalizedText(commentDraft), !isPosting else { return }
    isPosting = true
    defer { isPosting = false }
    do {
      let comment = try await postRepository.createComment(postID: post.id, body: body)
      comments.insert(comment, at: 0)
      commentDraft = ""
      errorMessage = nil
      onChanged()
    } catch {
      errorMessage = error.localizedDescription
    }
  }
}

private struct EventPostCommentRow: View {
  let comment: PostComment

  var body: some View {
    HStack(alignment: .top, spacing: 10) {
      SocialProfileButton(profile: comment.socialProfile) {
        Image(systemName: "person.crop.circle.fill")
          .font(.title2)
          .foregroundStyle(TunedInDesign.mutedText)
      }
      VStack(alignment: .leading, spacing: 3) {
        SocialProfileButton(profile: comment.socialProfile) {
          Text(comment.displayName)
            .font(.subheadline.weight(.bold))
            .foregroundStyle(TunedInDesign.primaryText)
        }
        Text(comment.body ?? "Comment removed")
          .font(.subheadline)
          .foregroundStyle(comment.isDeleted ? TunedInDesign.mutedText : TunedInDesign.primaryText)
      }
      Spacer(minLength: 0)
    }
    .padding(.vertical, 8)
  }
}
