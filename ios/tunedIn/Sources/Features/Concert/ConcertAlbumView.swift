import PhotosUI
import SwiftUI

struct ConcertAlbumView: View {
  let detail: ConcertDetail
  let viewerID: UUID
  let viewerRole: ConcertViewerRole
  let concertRepository: any ConcertRepository
  let pageHeader: AnyView

  @EnvironmentObject private var concertFloatingControls: ConcertFloatingControls
  @Environment(\.telemetry) private var telemetry

  @State private var photos: [ConcertAlbumPhoto] = []
  @State private var failedUploads: [FailedAlbumUpload] = []
  @State private var selectedPhotoID: UUID?
  @State private var isLoading = true
  @State private var isLoadingMore = false
  @State private var isUploading = false
  @State private var uploadProgress = 0
  @State private var uploadTotal = 0
  @State private var canLoadMore = false
  @State private var policy: ConcertAlbumPolicy?
  @State private var loadErrorMessage: String?
  @State private var errorMessage: String?

  private let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        pageHeader
        HStack(alignment: .firstTextBaseline) {
          VStack(alignment: .leading, spacing: 4) {
            Text("Photos").font(.system(size: 29, weight: .bold, design: .serif))
            Text(albumContext).font(.subheadline).foregroundStyle(TunedInDesign.mutedText)
          }
          Spacer()
        }

        if isUploading {
          ProgressView(value: Double(uploadProgress), total: Double(max(uploadTotal, 1))) {
            Text("Adding photo \(min(uploadProgress + 1, uploadTotal)) of \(uploadTotal)")
              .font(.caption.weight(.semibold))
          }
        }
        if let errorMessage {
          Text(errorMessage).font(.caption).foregroundStyle(.red)
        }
        if !failedUploads.isEmpty {
          Button("Retry \(failedUploads.count) failed \(failedUploads.count == 1 ? "photo" : "photos")") {
            Task { await retryFailures() }
          }
          .font(.subheadline.weight(.bold)).foregroundStyle(TunedInDesign.accent)
          .disabled(isUploading)
        }

        if isLoading {
          LazyVGrid(columns: columns, spacing: 10) {
            ForEach(0 ..< 6, id: \.self) { _ in
              TunedInSkeletonBlock()
                .aspectRatio(1, contentMode: .fit)
            }
          }
          .accessibilityLabel("Opening album")
        } else if let loadErrorMessage, photos.isEmpty {
          ContentUnavailableView {
            Label("Couldn’t open this album", systemImage: "exclamationmark.triangle")
          } description: {
            Text(loadErrorMessage)
          } actions: {
            Button("Try again") {
              Task { await retryLoad() }
            }
          }
          .padding(.vertical, 32)
        } else if photos.isEmpty {
          ContentUnavailableView(
            "No photos yet",
            systemImage: "photo.on.rectangle.angled",
            description: Text(viewerRole.canEdit ? "Add the first photo from this night." : "The editors haven’t added photos yet.")
          )
          .padding(.vertical, 48)
        } else {
          LazyVGrid(columns: columns, spacing: 10) {
            ForEach(photos) { photo in
              Button { selectedPhotoID = photo.id } label: {
                AlbumPhotoTile(photo: photo, repository: concertRepository)
              }.buttonStyle(.plain)
            }
          }
          if canLoadMore {
            Button(isLoadingMore ? "Loading…" : "Show earlier photos") { Task { await loadMore() } }
              .font(.subheadline.weight(.bold)).frame(maxWidth: .infinity).disabled(isLoadingMore)
          }
        }
      }
      .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 132)
    }
    .task { await load() }
    .onChange(of: concertFloatingControls.pendingPhotoSelections) { _, items in
      guard !items.isEmpty else { return }
      Task { await upload(items.map { FailedAlbumUpload(photoID: UUID(), item: $0, reservation: nil) }) }
    }
    .fullScreenCover(isPresented: viewerPresented) {
      ConcertAlbumViewer(
        photos: $photos,
        selectedPhotoID: $selectedPhotoID,
        viewerID: viewerID,
        viewerRole: viewerRole,
        repository: concertRepository
      )
    }
  }

  private var albumContext: String {
    let count = photos.count
    guard count > 0 else { return "A shared album for this night" }
    let contributors = Set(photos.map(\.uploaderID)).count
    return "\(count) \(count == 1 ? "photo" : "photos") · \(contributors) \(contributors == 1 ? "person" : "people")"
  }

  private var viewerPresented: Binding<Bool> {
    Binding(get: { selectedPhotoID != nil }, set: {
      if !$0 {
        selectedPhotoID = nil
      }
    })
  }

  private func load() async {
    loadErrorMessage = nil
    do {
      async let loadedPolicy = concertRepository.albumPolicy()
      async let loadedPhotos = concertRepository.albumPhotos(concertID: detail.concert.id, cursor: nil)
      (policy, photos) = try await (loadedPolicy, loadedPhotos)
      if let policy {
        concertFloatingControls.setAlbumPolicy(policy)
      }
      canLoadMore = photos.count == 30
    } catch { loadErrorMessage = error.localizedDescription }
    isLoading = false
  }

  private func retryLoad() async {
    isLoading = true
    await load()
  }

  private func loadMore() async {
    guard let last = photos.last, !isLoadingMore else { return }
    isLoadingMore = true
    do {
      let loaded = try await concertRepository.albumPhotos(
        concertID: detail.concert.id,
        cursor: ConcertAlbumPhotoCursor(attachedAt: last.attachedAt, photoID: last.id)
      )
      photos.append(contentsOf: loaded); canLoadMore = loaded.count == 30
    } catch { errorMessage = error.localizedDescription }
    isLoadingMore = false
  }

  private func upload(_ uploads: [FailedAlbumUpload]) async {
    let startedAt = ContinuousClock.now
    let isRetry = uploads.contains { $0.reservation != nil }
    isUploading = true
    concertFloatingControls.setInteractionLocked(true)
    defer {
      isUploading = false
      concertFloatingControls.setInteractionLocked(false)
    }
    uploadProgress = 0; uploadTotal = uploads.count; failedUploads = []; errorMessage = nil
    let result = await AlbumUploadBatchExecutor.run(uploads) { upload in
      var reservation = upload.reservation
      do {
        guard let source = try await upload.item.loadTransferable(type: Data.self) else {
          throw AlbumPickerError.unreadable
        }
        let data = try await ConcertAlbumImageProcessor.process(source)
        if reservation == nil {
          reservation = try await concertRepository.reserveAlbumPhoto(
            concertID: detail.concert.id,
            photoID: upload.photoID
          )
        }
        guard let reservation else { throw AlbumPickerError.unreadable }
        let photo = try await concertRepository.uploadReservedAlbumPhoto(data, reservation: reservation)
        return .success(photo)
      } catch {
        let failed = FailedAlbumUpload(
          photoID: upload.photoID,
          item: upload.item,
          reservation: reservation
        )
        return .failure(AlbumUploadAttemptError(item: failed, underlying: error))
      }
    } progress: { completed, _ in
      uploadProgress = completed
    }
    photos.insert(contentsOf: result.successes.reversed(), at: 0)
    failedUploads = result.failures.map(\.item)
    telemetry?.capture(
      .photoUploadCompleted,
      properties: [
        .attemptedCount: .integer(uploads.count),
        .succeededCount: .integer(result.successes.count),
        .partialSuccess: .boolean(!result.successes.isEmpty && !result.failures.isEmpty),
        .retryUsed: .boolean(isRetry),
        .outcome: .string(
          result.failures.isEmpty
            ? TelemetryOutcome.succeeded.rawValue
            : (result.successes.isEmpty ? TelemetryOutcome.failed.rawValue : TelemetryOutcome.partial.rawValue)
        ),
        .durationMilliseconds: .integer(startedAt.duration(to: .now).albumTelemetryMilliseconds),
        .failureCategory: result.failures.first.map {
          .string(TelemetryFailureCategory($0.error.appFailure).rawValue)
        } ?? .string("none")
      ]
    )
    if let failure = result.failures.first {
      switch failure.error.appFailure {
      case .offline:
        errorMessage = "You’re offline. Successful photos are already in the album."
      case .retryable:
        errorMessage = "The server did not respond in time. Successful photos are already in the album."
      default:
        errorMessage = "Some photos could not be added. Successful photos are already in the album."
      }
    }
    concertFloatingControls.pendingPhotoSelections = []
  }

  private func retryFailures() async {
    let failures = failedUploads; failedUploads = []
    await upload(failures)
  }
}

private extension Duration {
  var albumTelemetryMilliseconds: Int {
    let components = self.components
    return Int(components.seconds * 1_000 + components.attoseconds / 1_000_000_000_000_000)
  }
}

private struct FailedAlbumUpload: Identifiable {
  let photoID: UUID
  let item: PhotosPickerItem
  let reservation: ConcertPhotoReservation?
  var id: UUID {
    photoID
  }
}

private enum AlbumPickerError: LocalizedError { case unreadable }

private struct AlbumPhotoTile: View {
  let photo: ConcertAlbumPhoto
  let repository: any ConcertRepository

  var body: some View {
    ZStack(alignment: .bottomLeading) {
      AlbumPhotoImage(photo: photo, repository: repository)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()

      LinearGradient(
        colors: [.clear, .black.opacity(0.74)],
        startPoint: .top,
        endPoint: .bottom
      )
      .frame(height: 58)

      Text(photo.displayName)
        .font(.caption2.weight(.bold))
        .foregroundStyle(.white)
        .lineLimit(1)
        .padding(10)
    }
    .frame(maxWidth: .infinity)
    .aspectRatio(1, contentMode: .fit)
    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
  }
}

private struct AlbumPhotoImage: View {
  let photo: ConcertAlbumPhoto
  let repository: any ConcertRepository
  @State private var url: URL?
  @State private var failed = false
  var body: some View {
    Group {
      if let url {
        AsyncImage(url: url) { image in image.resizable().scaledToFill() } placeholder: { fallback }
      } else {
        fallback
      }
    }.task(id: "\(photo.id)-\(photo.version)") {
      do { url = try await repository.albumPhotoURL(photoID: photo.id, objectPath: photo.objectPath, version: photo.version) }
      catch { failed = true }
    }
  }

  private var fallback: some View {
    TunedInImagePlaceholder(failed: failed)
  }
}

private struct ConcertAlbumViewer: View {
  @Binding var photos: [ConcertAlbumPhoto]
  @Binding var selectedPhotoID: UUID?
  let viewerID: UUID
  let viewerRole: ConcertViewerRole
  let repository: any ConcertRepository
  @Environment(\.dismiss) private var dismiss
  @State private var captionDraft = ""
  @State private var isEditingCaption = false
  @State private var captionError: String?
  @State private var isSavingCaption = false

  var body: some View {
    ZStack(alignment: .bottom) {
      Color.black.ignoresSafeArea()
      TabView(selection: $selectedPhotoID) {
        ForEach(photos) { photo in
          VStack(spacing: 16) {
            AlbumPhotoImage(photo: photo, repository: repository).scaledToFit()
            VStack(alignment: .leading, spacing: 5) {
              Text(photo.displayName).font(.headline)
              Text(ConcertDisplay.longDateTime(photo.attachedAt)).font(.caption).foregroundStyle(.secondary)
              if let caption = photo.caption {
                Text(caption).padding(.top, 4)
              }
            }.foregroundStyle(.white).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 20)
            Spacer()
          }.tag(Optional(photo.id))
        }
      }.tabViewStyle(.page(indexDisplayMode: .automatic))

      TunedInGlassTraversalLayout {
        TunedInGlassIconButton(
          systemImage: "chevron.backward",
          accessibilityLabel: "Back to album"
        ) {
          dismiss()
        }
      } center: {
        TunedInGlassBottomBar {
          Text("Album")
            .font(.headline.weight(.bold))
            .foregroundStyle(TunedInDesign.primaryText)
            .frame(minWidth: 112, minHeight: 48)
            .padding(.horizontal, 14)
        }
      } trailing: {
        if let photo = selectedPhoto, canEdit(photo) {
          Menu {
            if photo.uploaderID == viewerID {
              Button {
                captionDraft = photo.caption ?? ""
                captionError = nil
                isEditingCaption = true
              } label: {
                Label("Edit caption", systemImage: "text.quote")
              }
            }

            Button("Delete photo", systemImage: "trash", role: .destructive) {
              Task { await delete(photo) }
            }
          } label: {
            TunedInFloatingActionLabel(systemImage: "ellipsis")
          }
          .accessibilityLabel("Photo actions")
        }
      }
      .padding(.horizontal, TunedInDesign.bottomControlHorizontalInset)
      .padding(.bottom, TunedInDesign.bottomControlInset)
    }
    .sheet(isPresented: $isEditingCaption) {
      NavigationStack {
        VStack(alignment: .leading, spacing: 8) {
          TextEditor(text: $captionDraft)
            .padding(8)
            .scrollContentBackground(.hidden)
            .background(TunedInDesign.raisedSurface, in: RoundedRectangle(cornerRadius: 14))
          HStack {
            if let captionError {
              Text(captionError).foregroundStyle(.red)
            }
            Spacer()
            Text("\(captionDraft.count)/300")
          }
          .font(.caption)
          .foregroundStyle(TunedInDesign.mutedText)
        }
        .padding()
        .background(TunedInDesign.pageBackground)
        .navigationTitle("Caption")
        .toolbar {
          ToolbarItem(placement: .cancellationAction) { Button("Cancel") { isEditingCaption = false } }
          ToolbarItem(placement: .confirmationAction) {
            Button(isSavingCaption ? "Saving…" : "Save") { Task { await saveCaption() } }
              .disabled(captionDraft.count > 300 || isSavingCaption)
          }
        }
      }.presentationDetents([.medium])
    }
    .tunedInEdgeSwipeBack { dismiss() }
  }

  private var selectedPhoto: ConcertAlbumPhoto? {
    photos.first(where: { $0.id == selectedPhotoID })
  }

  private func canEdit(_ photo: ConcertAlbumPhoto) -> Bool {
    viewerRole == .owner || (viewerRole == .editor && photo.uploaderID == viewerID)
  }

  private func saveCaption() async {
    guard let photo = selectedPhoto else { return }
    isSavingCaption = true
    defer { isSavingCaption = false }
    do {
      let normalized = captionDraft.trimmingCharacters(in: .whitespacesAndNewlines)
      let updated = try await repository.updateAlbumPhotoCaption(
        photoID: photo.id,
        caption: normalized.isEmpty ? nil : normalized
      )
      if let index = photos.firstIndex(where: { $0.id == photo.id }) {
        photos[index] = updated
      }
      isEditingCaption = false
    } catch {
      captionError = error.localizedDescription
    }
  }

  private func delete(_ photo: ConcertAlbumPhoto) async {
    guard await (try? repository.deleteAlbumPhoto(photoID: photo.id)) != nil else { return }
    photos.removeAll(where: { $0.id == photo.id }); selectedPhotoID = photos.first?.id
    if photos.isEmpty {
      dismiss()
    }
  }
}
