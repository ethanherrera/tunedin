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

  private let columns = [
    GridItem(.flexible(), spacing: 6),
    GridItem(.flexible(), spacing: 6)
  ]

  var body: some View {
    ZStack {
      TunedInDesign.pageBackground.ignoresSafeArea()

      ScrollView {
        VStack(alignment: .leading, spacing: 20) {
          EventScreenHeader(
            eyebrow: "\(event.headlinerName) · \(event.venueName)",
            title: diary.author.id == viewerID ? "Your diary" : "\(diary.author.displayName)’s diary",
            subtitle: "The review, album, and comments all follow this diary’s sharing setting."
          )

          EventDiaryPreviewCard(diary: diary)

          diaryPhotoSection
          diaryCommentSection

          if let errorMessage {
            Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
              .font(.caption.weight(.semibold))
              .foregroundStyle(.orange)
          }
        }
        .padding(20)
        .padding(.bottom, 24)
      }
      .refreshable { await load() }
    }
    .safeAreaInset(edge: .bottom, spacing: 0) {
      TunedInPersistentControlRegion {
        TunedInSubscreenBackBar(title: "Diary", action: onDismiss)
          .padding(.horizontal, TunedInDesign.bottomControlHorizontalInset)
          .padding(.top, 8)
          .padding(.bottom, TunedInDesign.bottomControlInset)
      }
    }
    .task { await load() }
    .onChange(of: photoSelection) { _, items in
      guard !items.isEmpty else { return }
      photoSelection = []
      Task { await upload(items) }
    }
  }

  private var diaryPhotoSection: some View {
    let uploadTitle = isUploading ? "Adding…" : "Add"
    return VStack(alignment: .leading, spacing: 12) {
      HStack {
        VStack(alignment: .leading, spacing: 3) {
          Text("Photos")
            .font(.headline)
            .foregroundStyle(TunedInDesign.primaryText)
          Text("\(photos.count) from this diary")
            .font(.caption)
            .foregroundStyle(TunedInDesign.mutedText)
        }
        Spacer()
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
      }

      if isLoading, photos.isEmpty {
        HStack(spacing: 6) {
          TunedInSkeletonBlock().aspectRatio(0.8, contentMode: .fit)
          TunedInSkeletonBlock().aspectRatio(0.8, contentMode: .fit)
        }
      } else if photos.isEmpty {
        Text(
          diary.author.id == viewerID
            ? "Add the first photo you want to keep with this memory."
            : "No photos have been shared with this diary yet."
        )
        .font(.subheadline)
        .foregroundStyle(TunedInDesign.mutedText)
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(TunedInDesign.cardBackground, in: RoundedRectangle(cornerRadius: 18))
      } else {
        LazyVGrid(columns: columns, spacing: 6) {
          ForEach(photos) { photo in
            EventDiaryPhotoTile(photo: photo, concertRepository: concertRepository)
          }
        }
      }
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
        .accessibilityLabel("Post diary comment")
      }

      if isLoading, comments.isEmpty {
        TunedInSkeletonBlock(cornerRadius: 18).frame(height: 76)
      } else if comments.isEmpty {
        Text("No comments yet. Start the conversation around this memory.")
          .font(.subheadline)
          .foregroundStyle(TunedInDesign.mutedText)
      } else {
        ForEach(comments) { comment in
          HStack(alignment: .top, spacing: 10) {
            Image(systemName: "person.crop.circle.fill")
              .font(.title2)
              .foregroundStyle(TunedInDesign.mutedText)
            VStack(alignment: .leading, spacing: 3) {
              Text(comment.displayName)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(TunedInDesign.primaryText)
              Text(comment.body ?? "Comment removed")
                .font(.subheadline)
                .foregroundStyle(comment.isDeleted ? TunedInDesign.mutedText : TunedInDesign.primaryText)
            }
            Spacer(minLength: 0)
          }
          .padding(12)
          .background(TunedInDesign.cardBackground, in: RoundedRectangle(cornerRadius: 16))
        }
      }
    }
  }

  @MainActor
  private func load() async {
    isLoading = photos.isEmpty && comments.isEmpty
    defer { isLoading = false }
    do {
      async let loadedPhotos = concertRepository.albumPhotos(concertID: diary.id, cursor: nil)
      async let loadedComments = concertRepository.comments(concertID: diary.id, cursor: nil)
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

private struct EventDiaryPhotoTile: View {
  let photo: ConcertAlbumPhoto
  let concertRepository: any ConcertRepository

  @State private var url: URL?

  var body: some View {
    ZStack {
      TunedInDesign.raisedSurface
      AsyncImage(url: url) { image in
        image.resizable().scaledToFill()
      } placeholder: {
        ProgressView().tint(TunedInDesign.accent)
      }
    }
    .aspectRatio(0.8, contentMode: .fit)
    .clipShape(RoundedRectangle(cornerRadius: 14))
    .task(id: "\(photo.id)-\(photo.version)") {
      url = try? await concertRepository.albumPhotoURL(
        photoID: photo.id,
        objectPath: photo.objectPath,
        version: photo.version
      )
    }
  }
}
