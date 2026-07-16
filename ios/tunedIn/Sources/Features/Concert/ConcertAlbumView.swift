import PhotosUI
import SwiftUI

struct ConcertAlbumView: View {
  let detail: ConcertDetail
  let viewerID: UUID
  let viewerRole: ConcertViewerRole
  let concertRepository: any ConcertRepository
  let pageHeader: AnyView
  let refreshToken: Int
  let onRefresh: () async -> Void

  @EnvironmentObject private var concertFloatingControls: ConcertFloatingControls
  @Environment(\.telemetry) private var telemetry
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  @State private var photos: [ConcertAlbumPhoto] = []
  @State private var pendingUploads: [PendingAlbumUpload] = []
  @State private var selectedPhotoID: UUID?
  @State private var isLoading = true
  @State private var isLoadingMore = false
  @State private var isUploading = false
  @State private var canLoadMore = false
  @State private var policy: ConcertAlbumPolicy?
  @State private var loadErrorMessage: String?
  @State private var errorMessage: String?
  @State private var successFeedback = 0
  @State private var failureFeedback = 0

  private let columns = [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)]

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        pageHeader
        HStack(alignment: .firstTextBaseline) {
          VStack(alignment: .leading, spacing: 4) {
            Text("The album").font(.system(size: 30, weight: .bold, design: .rounded))
            Text(albumContext).font(.subheadline).foregroundStyle(TunedInDesign.mutedText)
          }
          Spacer()
        }

        if let errorMessage {
          Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.orange)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(TunedInDesign.raisedSurface, in: RoundedRectangle(cornerRadius: 14))
        }

        if !pendingUploads.isEmpty {
          uploadShelf
            .transition(
              reduceMotion
                ? .opacity
                : .move(edge: .top).combined(with: .opacity)
            )
        }

        if isLoading {
          LazyVGrid(columns: columns, spacing: 6) {
            ForEach(0 ..< 6, id: \.self) { _ in
              TunedInSkeletonBlock()
                .aspectRatio(CGSize(width: 4, height: 5), contentMode: .fit)
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
        } else if photos.isEmpty, pendingUploads.isEmpty {
          ConcertAlbumEmptyState(
            detail: detail,
            viewerCanAddPhotos: viewerRole.canEdit
          )
        } else {
          LazyVGrid(columns: columns, spacing: 6) {
            ForEach(photos) { photo in
              Button { selectedPhotoID = photo.id } label: {
                AlbumPhotoTile(photo: photo, repository: concertRepository)
              }
              .buttonStyle(.plain)
              .accessibilityLabel("Photo added by \(photo.displayName)")
            }
          }
          if canLoadMore {
            Button(isLoadingMore ? "Loading…" : "Show earlier photos") { Task { await loadMore() } }
              .font(.subheadline.weight(.bold)).frame(maxWidth: .infinity).disabled(isLoadingMore)
          }
        }
      }
      .padding(.horizontal, 14)
      .padding(.top, 12)
      .padding(.bottom, TunedInDesign.scrollContentBottomInset)
    }
    .refreshable {
      await onRefresh()
      await load(policy: .refresh)
    }
    .task(id: refreshToken) { await load(policy: .automatic) }
    .onChange(of: concertFloatingControls.pendingPhotoSelections) { _, items in
      guard !items.isEmpty else { return }
      stage(items)
      concertFloatingControls.pendingPhotoSelections = []
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
    .animation(TunedInMotion.feedback(reduceMotion: reduceMotion), value: pendingUploads.map(\.phase))
    .sensoryFeedback(.success, trigger: successFeedback)
    .sensoryFeedback(.error, trigger: failureFeedback)
  }
}

private extension ConcertAlbumView {
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

  private var uploadShelf: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(alignment: .firstTextBaseline) {
        VStack(alignment: .leading, spacing: 2) {
          Text(uploadShelfTitle)
            .font(.headline.weight(.bold))
          Text("Progress and recovery stay with each photo.")
            .font(.caption)
            .foregroundStyle(TunedInDesign.mutedText)
        }
        Spacer()
        if pendingUploads.allSatisfy({ $0.phase.canRetry }), !isUploading {
          Button("Retry all") {
            retry(pendingUploads.map(\.id))
          }
          .font(.caption.weight(.bold))
          .foregroundStyle(TunedInDesign.accent)
        }
      }

      ScrollView(.horizontal) {
        LazyHStack(spacing: 10) {
          ForEach(pendingUploads) { upload in
            PendingAlbumUploadTile(upload: upload) {
              retry([upload.id])
            }
            .frame(width: 128)
          }
        }
        .scrollTargetLayout()
      }
      .scrollIndicators(.hidden)
    }
    .padding(14)
    .background(TunedInDesign.cardBackground, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 20, style: .continuous)
        .strokeBorder(TunedInDesign.cardBorder.opacity(0.6))
    }
  }

  private var uploadShelfTitle: String {
    let activeCount = pendingUploads.filter { $0.phase.isActive }.count
    let failedCount = pendingUploads.filter { $0.phase.canRetry }.count
    if activeCount > 0 {
      return "Adding \(activeCount) \(activeCount == 1 ? "photo" : "photos")"
    }
    if failedCount > 0 {
      return "\(failedCount) \(failedCount == 1 ? "photo needs" : "photos need") attention"
    }
    return "Saved to this night"
  }

  private func load(policy readPolicy: CacheReadPolicy) async {
    loadErrorMessage = nil
    do {
      async let loadedPolicy = concertRepository.albumPolicy(policy: readPolicy)
      async let loadedPhotos = concertRepository.albumPhotos(
        concertID: detail.concert.id,
        cursor: nil,
        policy: readPolicy
      )
      (policy, photos) = try await (loadedPolicy, loadedPhotos)
      if let policy {
        concertFloatingControls.setAlbumPolicy(policy)
      }
      canLoadMore = photos.count == 30
      errorMessage = nil
    } catch {
      let failure = AppFailure(error)
      if failure == .permissionDenied || failure == .unavailable {
        photos = []
      }
      loadErrorMessage = error.localizedDescription
    }
    isLoading = false
  }

  private func retryLoad() async {
    isLoading = true
    await load(policy: .refresh)
  }

  private func loadMore() async {
    guard let last = photos.last, !isLoadingMore else { return }
    isLoadingMore = true
    do {
      let loaded = try await concertRepository.albumPhotos(
        concertID: detail.concert.id,
        cursor: ConcertAlbumPhotoCursor(attachedAt: last.attachedAt, photoID: last.id),
        policy: .networkOnly
      )
      let existingIDs = Set(photos.map(\.id))
      photos.append(contentsOf: loaded.filter { !existingIDs.contains($0.id) })
      canLoadMore = loaded.count == 30
    } catch { errorMessage = error.localizedDescription }
    isLoadingMore = false
  }

  private func stage(_ items: [PhotosPickerItem]) {
    let uploads = items.map {
      PendingAlbumUpload(
        id: UUID(),
        item: $0,
        previewData: nil,
        processedData: nil,
        reservation: nil,
        phase: .preparing
      )
    }
    pendingUploads.append(contentsOf: uploads)
    Task { await upload(uploads.map(\.id), isRetry: false) }
  }

  private func retry(_ uploadIDs: [UUID]) {
    Task { await upload(uploadIDs, isRetry: true) }
  }

  private func upload(_ uploadIDs: [UUID], isRetry: Bool) async {
    guard !uploadIDs.isEmpty, !isUploading else { return }
    let startedAt = ContinuousClock.now
    isUploading = true
    concertFloatingControls.setInteractionLocked(true)
    defer {
      isUploading = false
      concertFloatingControls.setInteractionLocked(false)
    }
    errorMessage = nil
    var successes: [ConcertAlbumPhoto] = []
    var failures: [any Error] = []

    for uploadID in uploadIDs {
      do {
        let photo = try await uploadPhoto(id: uploadID)
        successes.append(photo)
      } catch {
        failures.append(error)
      }
    }

    if !successes.isEmpty {
      successFeedback += 1
      try? await Task.sleep(for: .milliseconds(reduceMotion ? 250 : 850))
      let succeededIDs = Set(successes.map(\.id))
      pendingUploads.removeAll { upload in
        guard case let .saved(photo) = upload.phase else { return false }
        return succeededIDs.contains(photo.id)
      }
      photos.insert(contentsOf: successes.reversed(), at: 0)
    }

    if !failures.isEmpty {
      failureFeedback += 1
    }
    if failures.count > 1 {
      errorMessage = "Some photos need attention. Retry them here without selecting them again."
    }

    telemetry?.capture(
      .photoUploadCompleted,
      properties: [
        .attemptedCount: .integer(uploadIDs.count),
        .succeededCount: .integer(successes.count),
        .partialSuccess: .boolean(!successes.isEmpty && !failures.isEmpty),
        .retryUsed: .boolean(isRetry),
        .outcome: .string(
          failures.isEmpty
            ? TelemetryOutcome.succeeded.rawValue
            : (successes.isEmpty ? TelemetryOutcome.failed.rawValue : TelemetryOutcome.partial.rawValue)
        ),
        .durationMilliseconds: .integer(startedAt.duration(to: .now).albumTelemetryMilliseconds),
        .failureCategory: failures.first.map {
          .string(TelemetryFailureCategory($0.appFailure).rawValue)
        } ?? .string("none")
      ]
    )
  }

  private func uploadPhoto(id: UUID) async throws -> ConcertAlbumPhoto {
    guard let initialIndex = pendingUploads.firstIndex(where: { $0.id == id }) else {
      throw AlbumPickerError.unreadable
    }
    pendingUploads[initialIndex].phase = pendingUploads[initialIndex].processedData == nil ? .preparing : .uploading

    do {
      let data: Data
      if let processed = pendingUploads[initialIndex].processedData {
        data = processed
      } else {
        guard let source = try await pendingUploads[initialIndex].item.loadTransferable(type: Data.self) else {
          throw AlbumPickerError.unreadable
        }
        if let currentIndex = pendingUploads.firstIndex(where: { $0.id == id }) {
          pendingUploads[currentIndex].previewData = source
        }
        data = try await ConcertAlbumImageProcessor.process(source)
        if let currentIndex = pendingUploads.firstIndex(where: { $0.id == id }) {
          pendingUploads[currentIndex].processedData = data
          pendingUploads[currentIndex].phase = .uploading
        }
      }

      guard let currentIndex = pendingUploads.firstIndex(where: { $0.id == id }) else {
        throw AlbumPickerError.unreadable
      }
      var reservation = pendingUploads[currentIndex].reservation
      if reservation == nil {
        reservation = try await concertRepository.reserveAlbumPhoto(
          concertID: detail.concert.id,
          photoID: id
        )
        if let reservation, let refreshedIndex = pendingUploads.firstIndex(where: { $0.id == id }) {
          pendingUploads[refreshedIndex].reservation = reservation
        }
      }
      guard let reservation else { throw AlbumPickerError.unreadable }
      let photo = try await concertRepository.uploadReservedAlbumPhoto(data, reservation: reservation)
      if let refreshedIndex = pendingUploads.firstIndex(where: { $0.id == id }) {
        pendingUploads[refreshedIndex].phase = .saved(photo)
      }
      return photo
    } catch {
      if let currentIndex = pendingUploads.firstIndex(where: { $0.id == id }) {
        pendingUploads[currentIndex].phase = .failed(albumUploadFailureMessage(error))
      }
      throw error
    }
  }
}

private func albumUploadFailureMessage(_ error: any Error) -> String {
  switch error.appFailure {
  case .offline:
    "You’re offline. Retry when you’re connected."
  case .retryable:
    "The upload timed out. Your photo is still here."
  default:
    "This photo couldn’t be added. Your selection is still here."
  }
}

private extension Duration {
  var albumTelemetryMilliseconds: Int {
    let components = components
    return Int(components.seconds * 1000 + components.attoseconds / 1_000_000_000_000_000)
  }
}

private enum AlbumPickerError: LocalizedError {
  case unreadable

  var errorDescription: String? {
    "That photo could not be read."
  }
}

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
    .aspectRatio(CGSize(width: 4, height: 5), contentMode: .fit)
    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
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
        CachedRemoteImage(
          url: url,
          resource: .albumPhoto(photoID: photo.id, version: photo.version)
        ) { phase in
          switch phase {
          case let .success(image):
            image.resizable().scaledToFill()
          case .failure:
            TunedInImagePlaceholder(failed: true)
          case .empty:
            fallback
          @unknown default:
            fallback
          }
        }
      } else {
        fallback
      }
    }
    .task(id: "\(photo.id)-\(photo.version)") {
      do {
        url = try await repository.albumPhotoURL(
          photoID: photo.id,
          objectPath: photo.objectPath,
          version: photo.version
        )
      } catch {
        failed = true
      }
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
    ZStack {
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
    }
    .safeAreaInset(edge: .bottom, spacing: 0) {
      TunedInPersistentControlRegion {
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
    }
    .sheet(isPresented: $isEditingCaption) {
      NavigationStack {
        ZStack {
          TunedInDesign.pageBackground
            .ignoresSafeArea()

          VStack(alignment: .leading, spacing: 10) {
            Text("Add the detail you want to remember.")
              .font(.subheadline)
              .foregroundStyle(TunedInDesign.mutedText)
            TextEditor(text: $captionDraft)
              .padding(10)
              .scrollContentBackground(.hidden)
              .background(TunedInDesign.raisedSurface, in: RoundedRectangle(cornerRadius: 18))
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
          .padding(20)
        }
        .navigationTitle("Caption")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom, spacing: 0) {
          TunedInPersistentControlRegion {
            TunedInGlassTraversalLayout {
              TunedInGlassIconButton(
                systemImage: "chevron.backward",
                accessibilityLabel: "Cancel caption editing"
              ) {
                isEditingCaption = false
              }
              .disabled(isSavingCaption)
            } center: {
              TunedInGlassBottomBar {
                Text("Caption")
                  .font(.headline.weight(.bold))
                  .foregroundStyle(TunedInDesign.primaryText)
                  .frame(minWidth: 112, minHeight: 48)
                  .padding(.horizontal, 14)
              }
            } trailing: {
              TunedInFloatingAction(
                systemImage: isSavingCaption ? "ellipsis" : "checkmark",
                accessibilityLabel: isSavingCaption ? "Saving caption" : "Save caption"
              ) {
                Task { await saveCaption() }
              }
              .disabled(captionDraft.count > 300 || isSavingCaption)
              .opacity(captionDraft.count > 300 ? 0.45 : 1)
            }
            .padding(.horizontal, TunedInDesign.bottomControlHorizontalInset)
            .padding(.top, 8)
            .padding(.bottom, TunedInDesign.bottomControlInset)
          }
        }
      }
      .presentationDetents([.medium])
      .tunedInKeyboardManaged()
    }
    .tunedInEdgeSwipeBack { dismiss() }
    .tunedInKeyboardManaged()
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
    guard await (try? repository.deleteAlbumPhoto(
      photoID: photo.id,
      concertID: photo.concertID
    )) != nil else { return }
    photos.removeAll(where: { $0.id == photo.id }); selectedPhotoID = photos.first?.id
    if photos.isEmpty {
      dismiss()
    }
  }
}
