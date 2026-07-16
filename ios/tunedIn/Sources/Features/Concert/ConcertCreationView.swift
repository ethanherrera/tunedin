import PhotosUI
import SwiftUI

// swiftlint:disable:next type_body_length
struct ConcertCreationView: View {
  let concertRepository: any ConcertRepository

  @Environment(\.dismiss) private var dismiss
  @Environment(\.telemetry) private var telemetry
  @Environment(\.musicCatalogRepository) private var musicCatalogRepository

  @State var draft = ConcertDraft()
  @State private var isSaving = false
  @State var isShowingDetails = false
  @State private var isShowingDiscardConfirmation = false
  @State private var saveError: String?
  @State private var createdConcertAwaitingPhoto: Concert?
  @State private var selectedPhoto: PhotosPickerItem?
  @State private var concertPhotoData: Data?
  @State private var isProcessingPhoto = false
  @State private var catalogPickerTarget: ConcertCatalogPickerTarget?

  var body: some View {
    NavigationStack {
      ZStack {
        TunedInDesign.pageBackground
          .ignoresSafeArea()

        ScrollView {
          VStack(alignment: .leading, spacing: 0) {
            captureHeader
            quickCaptureCard
              .padding(.top, 22)
            detailsPrompt
              .padding(.top, 12)
          }
          .padding(.bottom, 24)
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
      }
      .navigationBarTitleDisplayMode(.inline)
      .safeAreaInset(edge: .bottom, spacing: 0) {
        TunedInPersistentControlRegion {
          saveBar
        }
      }
      .alert(discardTitle, isPresented: $isShowingDiscardConfirmation) {
        Button("Keep Editing", role: .cancel) {}
        Button(discardActionTitle, role: .destructive) {
          dismiss()
        }
      } message: {
        Text(discardMessage)
      }
      .alert("Couldn’t finish saving", isPresented: isShowingSaveError) {
        Button("OK", role: .cancel) {}
      } message: {
        Text(saveError ?? "Please try again.")
      }
      .sheet(isPresented: $isShowingDetails) {
        ConcertCreationDetailsView(draft: $draft)
      }
      .fullScreenCover(item: $catalogPickerTarget) { target in
        catalogPicker(for: target)
      }
      .onChange(of: selectedPhoto) { _, item in
        guard let item else { return }
        Task { await processPhoto(item) }
      }
    }
    .tint(TunedInDesign.accent)
    .tunedInKeyboardManaged()
  }

  private var saveBar: some View {
    TunedInGlassTraversalLayout {
      TunedInGlassIconButton(
        systemImage: "chevron.backward",
        accessibilityLabel: "Cancel concert"
      ) {
        requestDismissal()
      }
      .disabled(isSaving)
    } center: {
      EmptyView()
    } trailing: {
      TunedInGlassTextButton(
        isSaving ? "Saving" : "Save",
        systemImage: isSaving ? "ellipsis" : "checkmark",
        accessibilityHint: draft.canSave
          ? "Saves this concert privately"
          : "Enter an artist and venue to save this concert",
        action: save
      )
      .disabled(!canSaveCapture)
      .opacity(canSaveCapture ? 1 : 0.45)
    }
    .padding(.horizontal, TunedInDesign.bottomControlHorizontalInset)
    .padding(.top, 8)
    .padding(.bottom, TunedInDesign.bottomControlInset)
  }

  private var canSaveCapture: Bool {
    draft.canSave && !isSaving && !isProcessingPhoto
  }

  private var isShowingSaveError: Binding<Bool> {
    Binding(
      get: { saveError != nil },
      set: { isPresented in
        if !isPresented {
          saveError = nil
        }
      }
    )
  }

  private var captureHeader: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Label("Private by default", systemImage: "lock.fill")
          .font(.caption.weight(.bold))
          .foregroundStyle(TunedInDesign.accent)
        Spacer()
        TunedInPrivacyBadge()
      }

      Text("New concert")
        .font(.system(size: 38, weight: .bold, design: .rounded))
        .foregroundStyle(TunedInDesign.primaryText)
      Text("Start with the night. Add the memories when you want.")
        .font(.body)
        .foregroundStyle(TunedInDesign.mutedText)
    }
  }

  private var quickCaptureCard: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(alignment: .center, spacing: 14) {
        PhotosPicker(selection: $selectedPhoto, matching: .images) {
          ZStack(alignment: .bottomTrailing) {
            Group {
              if let concertPhotoData, let image = UIImage(data: concertPhotoData) {
                Image(uiImage: image).resizable().scaledToFill()
              } else {
                ConcertArtworkImage(artistName: draft.primaryArtist?.displayName ?? "Concert")
              }
            }
            .frame(width: 96, height: 120)
            .clipped()
            Image(systemName: "camera.fill")
              .font(.caption.weight(.bold))
              .frame(width: 30, height: 30)
              .foregroundStyle(.white)
              .background(.black.opacity(0.66), in: Circle())
              .padding(8)
          }
          .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
          .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .disabled(isProcessingPhoto)

        VStack(alignment: .leading, spacing: 6) {
          Text(concertPhotoData == nil ? "Add the feeling later" : "Photo ready")
            .font(.headline)
            .foregroundStyle(TunedInDesign.primaryText)
          Text("Add a photo if it helps you remember the room. You can always do this later.")
            .font(.caption)
            .foregroundStyle(TunedInDesign.mutedText)
          if isProcessingPhoto {
            ProgressView("Preparing photo…")
              .font(.caption)
              .foregroundStyle(TunedInDesign.mutedText)
          } else {
            Label(
              concertPhotoData == nil ? "Optional photo" : "Tap artwork to change",
              systemImage: concertPhotoData == nil ? "photo" : "checkmark.circle.fill"
            )
            .font(.caption.weight(.semibold))
            .foregroundStyle(TunedInDesign.accent)
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      .padding(12)
      .background(TunedInDesign.raisedSurface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))

      VStack(spacing: 0) {
        VStack(alignment: .leading, spacing: 5) {
          Text("ARTIST")
            .font(.caption2.weight(.black))
            .foregroundStyle(TunedInDesign.accent)
          catalogSelectionButton(
            value: draft.artists[0].selection?.displayName,
            placeholder: "Who did you see?",
            font: .system(size: 28, weight: .bold, design: .serif)
          ) {
            catalogPickerTarget = .artist(draft.artists[0].id)
          }
          .accessibilityLabel("Primary artist")
          if draft.hasAttemptedSave, draft.artists[0].selection == nil {
            captureValidationLabel("Choose the artist you saw.")
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)

        Divider()
          .overlay(TunedInDesign.cardBorder.opacity(0.55))
          .padding(.leading, 18)

        HStack(alignment: .top, spacing: 12) {
          Image(systemName: "mappin.and.ellipse")
            .font(.body.weight(.semibold))
            .foregroundStyle(TunedInDesign.accent)
            .frame(width: 24, height: 28)
          VStack(alignment: .leading, spacing: 5) {
            catalogSelectionButton(
              value: draft.place?.displayName,
              placeholder: "Venue",
              font: .title3.weight(.semibold)
            ) {
              catalogPickerTarget = .place
            }
            .accessibilityLabel("Venue")
            if let areaName = draft.place?.areaName {
              Text(areaName)
                .font(.caption)
                .foregroundStyle(TunedInDesign.mutedText)
            }
            if draft.hasAttemptedSave, draft.place == nil {
              captureValidationLabel("Choose the venue.")
            }
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)

        Divider()
          .overlay(TunedInDesign.cardBorder.opacity(0.55))
          .padding(.leading, 18)

        HStack {
          Label("When", systemImage: "calendar")
            .font(.body.weight(.semibold))
            .foregroundStyle(TunedInDesign.primaryText)
          Spacer()
          DatePicker("Concert date", selection: $draft.concertDate, displayedComponents: .date)
            .datePickerStyle(.compact)
            .labelsHidden()
            .tint(TunedInDesign.accent)
        }
        .padding(18)
      }
      .background(
        TunedInDesign.cardBackground,
        in: RoundedRectangle(cornerRadius: 22, style: .continuous)
      )
    }
  }

  private func processPhoto(_ item: PhotosPickerItem) async {
    isProcessingPhoto = true
    defer { isProcessingPhoto = false }
    do {
      guard let data = try await item.loadTransferable(type: Data.self) else { return }
      concertPhotoData = try await AvatarImageProcessor.processConcertPhoto(data)
    } catch { saveError = error.localizedDescription }
  }

  private var detailsPrompt: some View {
    Button {
      isShowingDetails = true
    } label: {
      HStack(spacing: 13) {
        Image(systemName: "sparkles")
          .font(.body.weight(.semibold))
          .foregroundStyle(TunedInDesign.accent)
          .frame(width: 36, height: 36)
          .background(TunedInDesign.accentTint, in: Circle())
        VStack(alignment: .leading, spacing: 2) {
          Text("More details")
            .font(.headline)
            .foregroundStyle(TunedInDesign.primaryText)
          Text(detailsSummary)
            .font(.subheadline)
            .foregroundStyle(TunedInDesign.mutedText)
            .lineLimit(1)
        }
        Spacer()
        Image(systemName: "chevron.forward")
          .font(.subheadline.weight(.bold))
          .foregroundStyle(TunedInDesign.mutedText)
      }
      .padding(.horizontal, 6)
      .padding(.vertical, 12)
    }
    .buttonStyle(.plain)
    .accessibilityHint("Add the lineup, context, and setlist")
  }

  private var detailsSummary: String {
    let additions = (draft.artists.count - 1) + draft.setlist.count
    if additions == 0, draft.tour == nil, !draft.hasStartTime {
      return "Lineup, setlist, time, and more"
    }
    return "\(additions) added detail\(additions == 1 ? "" : "s")"
  }

  private func captureValidationLabel(_ message: String) -> some View {
    Label(message, systemImage: "exclamationmark.circle.fill")
      .font(.caption)
      .foregroundStyle(.red)
  }

  private func requestDismissal() {
    if draft.hasEnteredContent || createdConcertAwaitingPhoto != nil {
      isShowingDiscardConfirmation = true
    } else {
      dismiss()
    }
  }

  private var discardTitle: String {
    createdConcertAwaitingPhoto == nil ? "Discard this concert?" : "Leave without the photo?"
  }

  private var discardActionTitle: String {
    createdConcertAwaitingPhoto == nil ? "Discard" : "Close"
  }

  private var discardMessage: String {
    createdConcertAwaitingPhoto == nil
      ? "Your unsaved concert details will be lost."
      : "The concert is already saved privately. The photo has not been added."
  }

  private func save() {
    draft.hasAttemptedSave = true

    guard let input = draft.creationInput else { return }
    isSaving = true
    let startedAt = ContinuousClock.now

    Task {
      defer { isSaving = false }
      do {
        var concert: Concert
        if let createdConcertAwaitingPhoto {
          concert = createdConcertAwaitingPhoto
        } else {
          concert = try await concertRepository.createPrivateConcert(input)
          createdConcertAwaitingPhoto = concert
        }
        if let concertPhotoData {
          do {
            concert = try await concertRepository.setConcertPhoto(concertPhotoData, concertID: concert.id)
          } catch {
            saveError = "Your concert is saved, but the photo didn’t upload. "
              + "The photo is still ready here—tap Save to try it again."
            return
          }
        }
        createdConcertAwaitingPhoto = nil
        telemetry?.capture(
          .concertCreated,
          properties: [.durationMilliseconds: .integer(startedAt.duration(to: .now).creationTelemetryMilliseconds)]
        )
        dismiss()
      } catch {
        let failure = AppFailure(error)
        if failure.shouldReportToTelemetry {
          telemetry?.captureOperation(
            .createConcert,
            outcome: .failed,
            duration: startedAt.duration(to: .now),
            failure: failure
          )
        }
        saveError = error.localizedDescription
      }
    }
  }

  private func catalogSelectionButton(
    value: String?,
    placeholder: String,
    font: Font,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      HStack {
        Text(value ?? placeholder)
          .font(font)
          .foregroundStyle(value == nil ? TunedInDesign.mutedText : TunedInDesign.primaryText)
          .multilineTextAlignment(.leading)
        Spacer()
        Image(systemName: "magnifyingglass")
          .foregroundStyle(TunedInDesign.accent)
      }
      .contentShape(.interaction, Rectangle())
    }
    .buttonStyle(.plain)
  }

  @ViewBuilder
  private func catalogPicker(for target: ConcertCatalogPickerTarget) -> some View {
    switch target {
    case let .artist(id):
      CatalogPickerView(
        repository: musicCatalogRepository,
        configuration: CatalogPickerConfiguration(
          kind: .artist,
          title: "Choose headliner",
          currentSelectionName: draft.artists.first(where: { $0.id == id })?.selection?.displayName
        )
      ) { entity in
        guard case let .artist(artist) = entity else { return }
        draft.setArtist(artist, for: id)
        catalogPickerTarget = nil
      }
    case .place:
      CatalogPickerView(
        repository: musicCatalogRepository,
        configuration: CatalogPickerConfiguration(
          kind: .place,
          title: "Choose venue",
          currentSelectionName: draft.place?.displayName
        )
      ) { entity in
        guard case let .place(place) = entity else { return }
        draft.place = place
        catalogPickerTarget = nil
      }
    case .song, .tour:
      EmptyView()
    }
  }
}

private extension Duration {
  var creationTelemetryMilliseconds: Int {
    let components = components
    return Int(components.seconds * 1000 + components.attoseconds / 1_000_000_000_000_000)
  }
}
