import PhotosUI
import SwiftUI

struct EventDiaryDetailView: View {
  let event: CommunityEventSummary
  let diary: EventDiaryPreview
  let viewerID: UUID
  let concertRepository: any ConcertRepository
  let onChanged: () -> Void
  let onDismiss: () -> Void

  @State private var photos: [ConcertAlbumPhoto] = []
  @State private var comments: [ConcertComment] = []
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
          diaryAuthorHeader
          diaryMediaSection
          diaryReview
          diaryCommentSection

          if let errorMessage {
            Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
              .font(.caption.weight(.semibold))
              .foregroundStyle(.orange)
          }
        }
        .padding(20)
        .padding(.bottom, 96)
      }
      .refreshable { await load(policy: .refresh) }

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
    .task { await load(policy: .automatic) }
    .onChange(of: photoSelection) { _, items in
      guard !items.isEmpty else { return }
      photoSelection = []
      Task { await upload(items) }
    }
  }

  private var diaryAuthorHeader: some View {
    HStack(spacing: 12) {
      SocialProfileButton(profile: diary.author) {
        ProfileAvatarView(profile: diary.author, size: 44)
      }
      VStack(alignment: .leading, spacing: 3) {
        HStack(spacing: 5) {
          SocialProfileButton(profile: diary.author) {
            Text(diary.author.displayName)
              .fontWeight(.bold)
              .foregroundStyle(TunedInDesign.primaryText)
          }
          Image(systemName: diary.audience.icon)
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
      if let score = diary.score {
        CommunityEventScoreBadge(score: score, size: .large)
      }
    }
  }

  @ViewBuilder
  private var diaryMediaSection: some View {
    let uploadTitle = isUploading ? "Adding…" : "Add"
    if isLoading, diary.photoCount > 0, photos.isEmpty {
      TunedInSkeletonBlock(cornerRadius: 20)
        .aspectRatio(0.8, contentMode: .fit)
    } else if !photos.isEmpty {
      VStack(alignment: .trailing, spacing: 8) {
        if diary.author.id == viewerID {
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
            DiaryPhotoImage(photo: photo, concertRepository: concertRepository)
              .frame(maxWidth: .infinity, maxHeight: .infinity)
          }
        }
        .tabViewStyle(.page(indexDisplayMode: photos.count > 1 ? .automatic : .never))
        .frame(height: 468)
        .padding(.horizontal, -20)
      }
    } else if diary.author.id == viewerID {
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

  private var diaryReview: some View {
    VStack(alignment: .leading, spacing: 12) {
      if let note = diary.note {
        Text(note)
          .font(.body)
          .foregroundStyle(TunedInDesign.primaryText)
      }

      DiaryEngagementLine(diary: diary)
    }
  }

  private var diaryCommentSection: some View {
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
          EventDiaryCommentRow(comment: comment)
          Divider().overlay(TunedInDesign.cardBorder)
        }
      }
    }
  }

  @MainActor
  private func load(policy: CacheReadPolicy) async {
    isLoading = photos.isEmpty && comments.isEmpty
    defer { isLoading = false }
    do {
      async let loadedPhotos = concertRepository.albumPhotos(
        concertID: diary.id,
        cursor: nil,
        policy: policy
      )
      async let loadedComments = concertRepository.comments(
        concertID: diary.id,
        cursor: nil,
        policy: policy
      )
      (photos, comments) = try await (loadedPhotos, loadedComments)
      errorMessage = nil
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  @MainActor
  private func upload(_ items: [PhotosPickerItem]) async {
    guard diary.author.id == viewerID, !isUploading else { return }
    isUploading = true
    defer { isUploading = false }
    var failures = 0
    for item in items {
      do {
        guard let source = try await item.loadTransferable(type: Data.self) else {
          throw AppFailure.unexpected
        }
        let data = try await ConcertAlbumImageProcessor.process(source)
        let photoID = UUID()
        let reservation = try await concertRepository.reserveAlbumPhoto(
          concertID: diary.id,
          photoID: photoID
        )
        let photo = try await concertRepository.uploadReservedAlbumPhoto(
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
      let comment = try await concertRepository.createComment(concertID: diary.id, body: body)
      comments.insert(comment, at: 0)
      commentDraft = ""
      errorMessage = nil
      onChanged()
    } catch {
      errorMessage = error.localizedDescription
    }
  }
}

private struct EventDiaryCommentRow: View {
  let comment: ConcertComment

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
