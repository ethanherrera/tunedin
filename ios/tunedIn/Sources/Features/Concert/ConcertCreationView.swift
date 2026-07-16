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
  @State private var isShowingDiscardConfirmation = false
  @State private var isShowingSetlist = false
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
          VStack(alignment: .leading, spacing: 14) {
            composerHeader
            coverPhoto
            requiredFields
            optionalFields
          }
          .padding(.horizontal, 16)
          .padding(.top, 8)
          .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
      }
      .toolbar(.hidden, for: .navigationBar)
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
      .fullScreenCover(isPresented: $isShowingSetlist) {
        ConcertCreationSetlistView(draft: $draft)
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

  private var composerHeader: some View {
    HStack {
      Text("New concert")
        .font(.system(size: 30, weight: .bold, design: .rounded))
        .foregroundStyle(TunedInDesign.primaryText)
      Spacer()
      TunedInPrivacyBadge()
    }
    .padding(.horizontal, 2)
  }

  private var coverPhoto: some View {
    let photoData = concertPhotoData
    let artistName = draft.primaryArtist?.displayName ?? "Concert"
    let isPreparingPhoto = isProcessingPhoto

    return PhotosPicker(selection: $selectedPhoto, matching: .images) {
      ZStack(alignment: .bottomTrailing) {
        Group {
          if let photoData, let image = UIImage(data: photoData) {
            Image(uiImage: image)
              .resizable()
              .scaledToFill()
          } else {
            ConcertArtworkImage(artistName: artistName)
          }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 190)
        .clipped()

        if isPreparingPhoto {
          ProgressView()
            .tint(.white)
            .padding(12)
            .background(.black.opacity(0.58), in: Circle())
            .padding(12)
            .accessibilityLabel("Preparing photo")
        } else {
          Label(photoData == nil ? "Add photo" : "Change photo", systemImage: "photo")
            .font(.caption.weight(.bold))
            .padding(.horizontal, 11)
            .padding(.vertical, 9)
            .foregroundStyle(.white)
            .background(.black.opacity(0.62), in: Capsule())
            .padding(12)
        }
      }
      .clipShape(RoundedRectangle(cornerRadius: TunedInDesign.cornerRadius, style: .continuous))
      .contentShape(RoundedRectangle(cornerRadius: TunedInDesign.cornerRadius, style: .continuous))
      .overlay {
        RoundedRectangle(cornerRadius: TunedInDesign.cornerRadius, style: .continuous)
          .strokeBorder(.white.opacity(0.2))
      }
    }
    .buttonStyle(.plain)
    .disabled(isProcessingPhoto)
  }

  private var requiredFields: some View {
    VStack(spacing: 0) {
      VStack(alignment: .leading, spacing: 8) {
        selectionButton(
          icon: "music.mic",
          value: draft.primaryArtist?.displayName,
          placeholder: "Search for the headliner",
          emphasized: true
        ) {
          catalogPickerTarget = .artist(draft.artists[0].id)
        }
        .accessibilityLabel("Headliner")

        if draft.hasAttemptedSave, draft.primaryArtist == nil {
          validationLabel("Choose a headliner.")
        }
      }
      .padding(.vertical, 2)

      cardDivider

      HStack(spacing: 14) {
        fieldIcon("calendar")
        Text("Date")
          .font(.body.weight(.semibold))
          .foregroundStyle(TunedInDesign.primaryText)
        Spacer()
        DatePicker("Concert date", selection: $draft.concertDate, displayedComponents: .date)
          .datePickerStyle(.compact)
          .labelsHidden()
          .tint(TunedInDesign.accent)
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 15)

      cardDivider

      VStack(alignment: .leading, spacing: 8) {
        selectionButton(
          icon: "mappin.and.ellipse",
          value: draft.place.map { place in
            if let areaName = place.areaName, !areaName.isEmpty {
              return "\(place.displayName) · \(areaName)"
            }
            return place.displayName
          },
          placeholder: "Search for the venue"
        ) {
          catalogPickerTarget = .place
        }
        .accessibilityLabel("Venue")

        if draft.hasAttemptedSave, draft.place == nil {
          validationLabel("Choose a venue.")
        }
      }
      .padding(.vertical, 2)
    }
    .composerCard()
  }

  private var optionalFields: some View {
    VStack(spacing: 0) {
      startTimeRows
      cardDivider
      tourRow

      ForEach(Array(draft.artists.dropFirst())) { artist in
        cardDivider
        supportingArtistRow(artist)
      }

      cardDivider
      optionButton(icon: "person.2", title: "Add another artist") {
        catalogPickerTarget = .artist(UUID())
      }
      .disabled(draft.artists.count == 10)

      cardDivider
      optionButton(
        icon: "music.note.list",
        title: draft.setlist.isEmpty
          ? "Add the songs you remember"
          : "Setlist · \(draft.setlist.count) \(draft.setlist.count == 1 ? "song" : "songs")"
      ) {
        isShowingSetlist = true
      }
    }
    .composerCard()
  }

  @ViewBuilder
  private var startTimeRows: some View {
    if draft.hasStartTime {
      HStack(spacing: 14) {
        fieldIcon("clock")
        Text("Start time")
          .font(.body.weight(.semibold))
          .foregroundStyle(TunedInDesign.primaryText)
        Spacer()
        DatePicker("Start time", selection: $draft.startTime, displayedComponents: .hourAndMinute)
          .labelsHidden()
        Button {
          withAnimation(.snappy) { draft.hasStartTime = false }
        } label: {
          Image(systemName: "xmark.circle.fill")
            .foregroundStyle(TunedInDesign.mutedText)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Remove start time")
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 13)

      cardDivider

      HStack(spacing: 14) {
        fieldIcon("globe.americas")
        Text("Time zone")
          .font(.body.weight(.semibold))
          .foregroundStyle(TunedInDesign.primaryText)
        Spacer()
        Menu {
          ForEach(TimeZone.knownTimeZoneIdentifiers.sorted(), id: \.self) { identifier in
            Button(identifier.replacingOccurrences(of: "_", with: " ")) {
              draft.venueTimeZoneIdentifier = identifier
            }
          }
        } label: {
          HStack(spacing: 5) {
            Text(Self.timeZoneDisplayName(draft.venueTimeZoneIdentifier))
              .lineLimit(1)
              .minimumScaleFactor(0.8)
            Image(systemName: "chevron.up.chevron.down")
              .font(.caption2.weight(.semibold))
          }
          .foregroundStyle(TunedInDesign.primaryText)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Time zone")
        .accessibilityValue(draft.venueTimeZoneIdentifier)
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 13)
    } else {
      optionButton(icon: "clock.badge.plus", title: "Add start time") {
        withAnimation(.snappy) { draft.hasStartTime = true }
      }
    }
  }

  @ViewBuilder
  private var tourRow: some View {
    if let tour = draft.tour {
      HStack(spacing: 6) {
        Button {
          catalogPickerTarget = .tour
        } label: {
          HStack(spacing: 14) {
            fieldIcon("ticket")
            Text(tour.displayName)
              .font(.body.weight(.semibold))
              .foregroundStyle(TunedInDesign.primaryText)
              .lineLimit(2)
            Spacer()
          }
          .contentShape(.interaction, Rectangle())
        }
        .buttonStyle(.plain)

        Button {
          draft.tour = nil
        } label: {
          Image(systemName: "xmark.circle.fill")
            .foregroundStyle(TunedInDesign.mutedText)
            .frame(width: 40, height: 40)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Remove tour")
      }
      .padding(.leading, 16)
      .padding(.trailing, 8)
      .padding(.vertical, 7)
    } else {
      optionButton(icon: "ticket", title: "Add tour") {
        catalogPickerTarget = .tour
      }
    }
  }

  private func supportingArtistRow(_ artist: ConcertDraft.Artist) -> some View {
    HStack(spacing: 6) {
      Button {
        catalogPickerTarget = .artist(artist.id)
      } label: {
        HStack(spacing: 14) {
          fieldIcon("person.wave.2")
          Text(artist.name)
            .font(.body.weight(.semibold))
            .foregroundStyle(TunedInDesign.primaryText)
            .lineLimit(2)
          Spacer()
        }
        .contentShape(.interaction, Rectangle())
      }
      .buttonStyle(.plain)

      Menu {
        Button("Make headliner") { draft.makePrimary(artist.id) }
        Button("Remove", role: .destructive) { draft.removeArtist(artist.id) }
      } label: {
        Image(systemName: "ellipsis")
          .font(.body.weight(.bold))
          .foregroundStyle(TunedInDesign.mutedText)
          .frame(width: 40, height: 40)
      }
      .accessibilityLabel("Options for \(artist.name)")
    }
    .padding(.leading, 16)
    .padding(.trailing, 8)
    .padding(.vertical, 7)
  }

  private func selectionButton(
    icon: String,
    value: String?,
    placeholder: String,
    emphasized: Bool = false,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      HStack(spacing: 14) {
        fieldIcon(icon)
        Text(value ?? placeholder)
          .font(emphasized ? .system(size: 25, weight: .bold, design: .serif) : .body.weight(.semibold))
          .foregroundStyle(value == nil ? TunedInDesign.mutedText : TunedInDesign.primaryText)
          .multilineTextAlignment(.leading)
          .lineLimit(2)
        Spacer()
        Image(systemName: "magnifyingglass")
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(TunedInDesign.accent)
      }
      .padding(.horizontal, 16)
      .padding(.vertical, emphasized ? 18 : 15)
      .contentShape(.interaction, Rectangle())
    }
    .buttonStyle(.plain)
  }

  private func optionButton(icon: String, title: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      HStack(spacing: 14) {
        fieldIcon(icon)
        Text(title)
          .font(.body.weight(.semibold))
          .foregroundStyle(TunedInDesign.primaryText)
          .multilineTextAlignment(.leading)
        Spacer()
        Image(systemName: "chevron.forward")
          .font(.caption.weight(.bold))
          .foregroundStyle(TunedInDesign.mutedText)
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 15)
      .contentShape(.interaction, Rectangle())
    }
    .buttonStyle(.plain)
  }

  private func fieldIcon(_ systemName: String) -> some View {
    Image(systemName: systemName)
      .font(.body.weight(.semibold))
      .foregroundStyle(TunedInDesign.accent)
      .frame(width: 24)
      .accessibilityHidden(true)
  }

  private var cardDivider: some View {
    Divider()
      .overlay(TunedInDesign.cardBorder.opacity(0.55))
      .padding(.leading, 54)
  }

  private func validationLabel(_ message: String) -> some View {
    Label(message, systemImage: "exclamationmark.circle.fill")
      .font(.caption)
      .foregroundStyle(.red)
      .padding(.horizontal, 16)
      .padding(.bottom, 12)
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
      TunedInGlassBottomBar {
        Button(action: save) {
          HStack(spacing: 8) {
            if isSaving {
              ProgressView()
                .controlSize(.small)
                .tint(TunedInDesign.actionForeground)
            }
            Text(isSaving ? "Creating…" : "Create concert")
              .font(.subheadline.weight(.bold))
          }
          .foregroundStyle(TunedInDesign.actionForeground)
          .frame(maxWidth: .infinity)
          .frame(height: 44)
          .background(TunedInDesign.accent, in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!canSaveCapture)
        .opacity(canSaveCapture ? 1 : 0.42)
        .accessibilityHint(
          draft.canSave
            ? "Creates this concert privately"
            : "Choose a headliner and venue first"
        )
      }
    } trailing: {
      EmptyView()
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

  private func processPhoto(_ item: PhotosPickerItem) async {
    isProcessingPhoto = true
    defer { isProcessingPhoto = false }
    do {
      guard let data = try await item.loadTransferable(type: Data.self) else { return }
      concertPhotoData = try await AvatarImageProcessor.processConcertPhoto(data)
    } catch {
      saveError = error.localizedDescription
    }
  }

  private func requestDismissal() {
    if draft.hasEnteredContent || concertPhotoData != nil || createdConcertAwaitingPhoto != nil {
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
              + "The photo is still ready here—tap Create concert to try it again."
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

  @ViewBuilder
  private func catalogPicker(for target: ConcertCatalogPickerTarget) -> some View {
    switch target {
    case let .artist(id):
      let isExistingArtist = draft.artists.contains(where: { $0.id == id })
      CatalogPickerView(
        repository: musicCatalogRepository,
        configuration: CatalogPickerConfiguration(
          kind: .artist,
          title: id == draft.artists.first?.id ? "Choose headliner" : "Choose artist",
          currentSelectionName: draft.artists.first(where: { $0.id == id })?.selection?.displayName,
          showsGuidance: false
        )
      ) { entity in
        guard case let .artist(artist) = entity else { return }
        if isExistingArtist {
          draft.setArtist(artist, for: id)
        } else {
          draft.addArtist(artist)
        }
        catalogPickerTarget = nil
      }
    case .place:
      CatalogPickerView(
        repository: musicCatalogRepository,
        configuration: CatalogPickerConfiguration(
          kind: .place,
          title: "Choose venue",
          currentSelectionName: draft.place?.displayName,
          showsGuidance: false
        )
      ) { entity in
        guard case let .place(place) = entity else { return }
        draft.place = place
        catalogPickerTarget = nil
      }
    case .tour:
      CatalogPickerView(
        repository: musicCatalogRepository,
        configuration: CatalogPickerConfiguration(
          kind: .tour,
          title: "Choose tour",
          artistContext: draft.selectedCatalogArtists,
          currentSelectionName: draft.tour?.displayName,
          showsGuidance: false
        )
      ) { entity in
        guard case let .tour(tour) = entity else { return }
        draft.tour = tour
        catalogPickerTarget = nil
      }
    case .song:
      EmptyView()
    }
  }

  private static func timeZoneDisplayName(_ identifier: String) -> String {
    guard let place = identifier.split(separator: "/").last else { return identifier }
    return String(place).replacingOccurrences(of: "_", with: " ")
  }
}

private extension View {
  func composerCard() -> some View {
    background(
      TunedInDesign.cardBackground,
      in: RoundedRectangle(cornerRadius: TunedInDesign.cornerRadius, style: .continuous)
    )
    .overlay {
      RoundedRectangle(cornerRadius: TunedInDesign.cornerRadius, style: .continuous)
        .strokeBorder(TunedInDesign.cardBorder.opacity(0.55))
    }
  }
}

private extension Duration {
  var creationTelemetryMilliseconds: Int {
    let components = components
    return Int(components.seconds * 1000 + components.attoseconds / 1_000_000_000_000_000)
  }
}
