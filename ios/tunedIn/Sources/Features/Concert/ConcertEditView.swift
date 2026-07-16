// The three focused editing pages share one draft and save boundary.
// swiftlint:disable type_body_length
import PhotosUI
import SwiftUI

struct ConcertEditView: View {
  private enum PhotoDraftChange: Equatable {
    case unchanged
    case replacement(Data)
    case removal
  }

  private enum EditPage: Int, CaseIterable, Identifiable {
    case night
    case songs
    case sharing

    var id: Int {
      rawValue
    }

    var title: String {
      switch self {
      case .night: "Details"
      case .songs: "Setlist"
      case .sharing: "Sharing"
      }
    }

    var icon: String {
      switch self {
      case .night: "calendar"
      case .songs: "music.note.list"
      case .sharing: "person.2.fill"
      }
    }
  }

  let detail: ConcertDetail
  let canMakePrivate: Bool
  let concertRepository: any ConcertRepository
  let loadLatestDetail: @Sendable () async throws -> ConcertDetail
  let onSaved: (Concert) -> Void

  @Environment(\.dismiss) private var dismiss
  @Environment(\.telemetry) private var telemetry
  @Environment(\.musicCatalogRepository) private var musicCatalogRepository
  @State private var draft: ConcertDraft
  @State private var originalDraft: ConcertDraft
  @State private var visibility: ConcertVisibility
  @State private var originalVisibility: ConcertVisibility
  @State private var expectedVersion: Int64
  @State private var page: EditPage = .night
  @State private var isSaving = false
  @State private var isReloadingAfterConflict = false
  @State private var errorMessage: String?
  @State private var conflictMessage: String?
  @State private var pendingVisibilityNarrowing: ConcertVisibility?
  @State private var selectedPhoto: PhotosPickerItem?
  @State private var photoDraftChange: PhotoDraftChange = .unchanged
  @State private var isProcessingPhoto = false
  @State private var isConfirmingPhotoRemoval = false
  @State private var isShowingDiscardConfirmation = false
  @State private var workingDetail: ConcertDetail
  @State private var catalogPickerTarget: ConcertCatalogPickerTarget?
  @Namespace private var editSelectionNamespace

  init(
    detail: ConcertDetail,
    canMakePrivate: Bool,
    concertRepository: any ConcertRepository,
    loadLatestDetail: @escaping @Sendable () async throws -> ConcertDetail,
    onSaved: @escaping (Concert) -> Void
  ) {
    self.detail = detail
    self.canMakePrivate = canMakePrivate
    self.concertRepository = concertRepository
    self.loadLatestDetail = loadLatestDetail
    self.onSaved = onSaved
    let initialDraft = ConcertDraft(detail: detail)
    _draft = State(initialValue: initialDraft)
    _originalDraft = State(initialValue: initialDraft)
    _visibility = State(initialValue: detail.concert.visibility)
    _originalVisibility = State(initialValue: detail.concert.visibility)
    _expectedVersion = State(initialValue: detail.concert.version)
    _workingDetail = State(initialValue: detail)
  }

  var body: some View {
    NavigationStack {
      ZStack {
        TunedInDesign.pageBackground
          .ignoresSafeArea()

        VStack(spacing: 0) {
          TabView(selection: $page) {
            nightPage.tag(EditPage.night)
            songsPage.tag(EditPage.songs)
            sharingPage.tag(EditPage.sharing)
          }
          .tabViewStyle(.page(indexDisplayMode: .never))
        }
      }
      .safeAreaInset(edge: .bottom, spacing: 0) {
        TunedInPersistentControlRegion {
          saveBar
        }
      }
      .toolbar {
        ToolbarItem(placement: .principal) {
          Text("Edit concert")
            .font(.headline)
            .foregroundStyle(TunedInDesign.primaryText)
        }
      }
      .alert("Couldn’t save your changes", isPresented: isShowingError) {
        Button("OK", role: .cancel) {}
      } message: {
        Text(errorMessage ?? "Please try again.")
      }
      .alert("Remove concert photo?", isPresented: $isConfirmingPhotoRemoval) {
        Button("Cancel", role: .cancel) {}
        Button("Remove", role: .destructive) {
          photoDraftChange = .removal
          selectedPhoto = nil
        }
      } message: { Text("The generated concert artwork will be used after you save.") }
      .alert("Discard your changes?", isPresented: $isShowingDiscardConfirmation) {
        Button("Keep Editing", role: .cancel) {}
        Button("Discard", role: .destructive) { dismiss() }
      } message: {
        Text("Your unsaved concert changes will be lost.")
      }
      .alert("This concert changed", isPresented: isShowingConflict) {
        Button(isReloadingAfterConflict ? "Loading latest…" : "Load latest version") {
          Task { await reloadAfterConflict() }
        }
        .disabled(isReloadingAfterConflict)
        Button("Keep editing", role: .cancel) {}
      } message: {
        Text(
          conflictMessage
            ?? "Someone saved changes first. Load the latest version, review it, then make your edit again."
        )
      }
      .confirmationDialog(
        accessRestrictionTitle,
        isPresented: isShowingVisibilityNarrowingConfirmation,
        titleVisibility: .visible,
        presenting: pendingVisibilityNarrowing
      ) { option in
        Button(confirmAccessRestrictionTitle(for: option), role: .destructive) {
          visibility = option
          pendingVisibilityNarrowing = nil
        }
        Button(cancelAccessRestrictionTitle(for: option), role: .cancel) {
          pendingVisibilityNarrowing = nil
        }
      } message: { _ in
        Text(accessRestrictionDescription)
      }
    }
    .tint(TunedInDesign.accent)
    .tunedInKeyboardManaged()
    .onChange(of: selectedPhoto) { _, item in
      guard let item else { return }
      Task { await processPhoto(item) }
    }
    .fullScreenCover(item: $catalogPickerTarget) { target in
      catalogPicker(for: target)
    }
  }

  private var nightPage: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 18) {
        VStack(alignment: .leading, spacing: 5) {
          Text("Shape the night")
            .font(.system(size: 30, weight: .bold, design: .rounded))
            .foregroundStyle(TunedInDesign.primaryText)
          Text("Everything here stays in one draft until you save.")
            .font(.subheadline)
            .foregroundStyle(TunedInDesign.mutedText)
        }

        concertPhotoEditor

        nightBasics

        editSection {
          Text("Details")
            .font(.headline)
            .foregroundStyle(TunedInDesign.primaryText)
          HStack {
            VStack(alignment: .leading, spacing: 2) {
              Text("City or area").font(.caption).foregroundStyle(TunedInDesign.mutedText)
              Text(draft.city.isEmpty ? "Derived from venue" : draft.city)
                .foregroundStyle(draft.city.isEmpty ? TunedInDesign.mutedText : TunedInDesign.primaryText)
            }
            Spacer()
            Image(systemName: "lock.fill")
              .font(.caption)
              .foregroundStyle(TunedInDesign.mutedText)
          }
          Button {
            catalogPickerTarget = .tour
          } label: {
            HStack {
              VStack(alignment: .leading, spacing: 2) {
                Text("Tour (optional)").font(.caption).foregroundStyle(TunedInDesign.mutedText)
                Text(draft.tour?.displayName ?? "Choose tour")
                  .foregroundStyle(draft.tour == nil ? TunedInDesign.mutedText : TunedInDesign.primaryText)
              }
              Spacer()
              Image(systemName: "magnifyingglass").foregroundStyle(TunedInDesign.accent)
            }
            .contentShape(.interaction, Rectangle())
          }
          .buttonStyle(.plain)
          if draft.tour != nil {
            Button("Remove tour", role: .destructive) { draft.tour = nil }
              .font(.caption.weight(.semibold))
          }
          Toggle("Add a start time", isOn: $draft.hasStartTime)
          if draft.hasStartTime {
            DatePicker("Start time", selection: $draft.startTime, displayedComponents: .hourAndMinute)
            Picker("Venue time zone", selection: $draft.venueTimeZoneIdentifier) {
              ForEach(TimeZone.knownTimeZoneIdentifiers.sorted(), id: \.self) { identifier in
                Text(identifier).tag(identifier)
              }
            }
          }
        }

        if draft.artists.count > 1 {
          editSection {
            Text("On the bill")
              .font(.headline)
              .foregroundStyle(TunedInDesign.primaryText)
            ForEach(draft.artists.dropFirst()) { artist in
              HStack {
                Button {
                  catalogPickerTarget = .artist(artist.id)
                } label: {
                  Text(artist.name)
                    .foregroundStyle(TunedInDesign.primaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                Menu {
                  Button("Make headliner") { draft.makePrimary(artist.id) }
                  Button("Remove", role: .destructive) { draft.removeArtist(artist.id) }
                } label: {
                  Image(systemName: "ellipsis.circle")
                    .foregroundStyle(TunedInDesign.mutedText)
                }
              }
            }
          }
        }

        Button {
          catalogPickerTarget = .artist(UUID())
        } label: {
          Label("Add another artist", systemImage: "plus.circle.fill")
            .font(.headline)
            .foregroundStyle(TunedInDesign.accent)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(TunedInDesign.raisedSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(draft.artists.count == 10)
      }
      .padding(.horizontal, 20)
      .padding(.top, 12)
      .padding(.bottom, TunedInDesign.scrollContentBottomInset)
    }
  }

  private var nightBasics: some View {
    VStack(spacing: 0) {
      VStack(alignment: .leading, spacing: 5) {
        Text("HEADLINER")
          .font(.caption2.weight(.black))
          .foregroundStyle(TunedInDesign.accent)
        catalogSelectionButton(
          value: draft.artists.first?.selection?.displayName,
          placeholder: "Choose headliner",
          font: .system(size: 28, weight: .bold, design: .serif)
        ) {
          if let id = draft.artists.first?.id {
            catalogPickerTarget = .artist(id)
          }
        }
        .accessibilityLabel("Headliner")
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(18)

      Divider()
        .overlay(TunedInDesign.cardBorder.opacity(0.55))
        .padding(.leading, 18)

      HStack(alignment: .top, spacing: 12) {
        Image(systemName: "mappin.and.ellipse")
          .foregroundStyle(TunedInDesign.accent)
          .frame(width: 24, height: 28)
        VStack(alignment: .leading, spacing: 5) {
          catalogSelectionButton(
            value: draft.place?.displayName,
            placeholder: "Choose venue",
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
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(18)

      Divider()
        .overlay(TunedInDesign.cardBorder.opacity(0.55))
        .padding(.leading, 18)

      HStack {
        Label("Concert date", systemImage: "calendar")
          .font(.body.weight(.semibold))
          .foregroundStyle(TunedInDesign.primaryText)
        Spacer()
        DatePicker("Concert date", selection: $draft.concertDate, displayedComponents: .date)
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

  private func editSection(@ViewBuilder content: () -> some View) -> some View {
    VStack(alignment: .leading, spacing: 13) {
      content()
    }
    .padding(18)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
      TunedInDesign.cardBackground,
      in: RoundedRectangle(cornerRadius: 22, style: .continuous)
    )
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

  private var concertPhotoEditor: some View {
    HStack(spacing: 14) {
      photoDraftPreview
        .frame(width: 88, height: 112)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

      VStack(alignment: .leading, spacing: 9) {
        Text("Main photo").font(.headline).foregroundStyle(TunedInDesign.primaryText)
        Text(photoDraftStatus).font(.caption).foregroundStyle(TunedInDesign.mutedText)
        PhotosPicker(selection: $selectedPhoto, matching: .images) {
          Label(hasDraftPhoto ? "Change photo" : "Add photo", systemImage: "photo")
            .font(.subheadline.weight(.semibold))
        }
        if hasDraftPhoto {
          Button("Remove", role: .destructive) { isConfirmingPhotoRemoval = true }
            .font(.subheadline.weight(.semibold))
        }
        if isProcessingPhoto {
          ProgressView("Preparing…").controlSize(.small)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .disabled(isProcessingPhoto)
    }
    .padding(14)
    .background(TunedInDesign.raisedSurface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
  }

  @ViewBuilder
  private var photoDraftPreview: some View {
    switch photoDraftChange {
    case let .replacement(data):
      if let image = UIImage(data: data) {
        Image(uiImage: image)
          .resizable()
          .scaledToFill()
      } else {
        generatedArtwork
      }
    case .removal:
      generatedArtwork
    case .unchanged:
      ConcertPhotoView(
        concert: workingDetail.concert,
        artistName: draft.primaryArtist?.displayName ?? "Concert",
        repository: concertRepository
      )
    }
  }

  private var generatedArtwork: some View {
    ConcertArtworkImage(artistName: draft.primaryArtist?.displayName ?? "Concert")
  }

  private var hasDraftPhoto: Bool {
    switch photoDraftChange {
    case .replacement:
      true
    case .removal:
      false
    case .unchanged:
      workingDetail.concert.photoObjectPath != nil
    }
  }

  private var photoDraftStatus: String {
    switch photoDraftChange {
    case .replacement:
      "New photo ready to save"
    case .removal:
      "Generated artwork will be used"
    case .unchanged:
      "Optional · saved with the rest"
    }
  }

  private func processPhoto(_ item: PhotosPickerItem) async {
    isProcessingPhoto = true
    defer { isProcessingPhoto = false }
    do {
      guard let data = try await item.loadTransferable(type: Data.self) else { return }
      photoDraftChange = .replacement(try await AvatarImageProcessor.processConcertPhoto(data))
    } catch { errorMessage = error.localizedDescription }
  }

  private var songsPage: some View {
    ConcertSetlistDraftView(
      draft: $draft,
      idleSubtitle: "A clean read of the night, in order."
    ) { songID in
      catalogPickerTarget = .song(songID)
    }
  }

  private var sharingPage: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 18) {
        VStack(alignment: .leading, spacing: 4) {
          Text("Sharing")
            .font(.system(size: 30, weight: .bold, design: .rounded))
            .foregroundStyle(TunedInDesign.primaryText)
          Text("Choose who can see this after you save.")
            .font(.subheadline)
            .foregroundStyle(TunedInDesign.mutedText)
        }

        VStack(spacing: 10) {
          ForEach(availableVisibility, id: \.self) { option in
            visibilityChoice(option)
          }
        }

        TunedInFormCard {
          Label("People stay separate", systemImage: "person.2")
            .font(.headline)
            .foregroundStyle(TunedInDesign.primaryText)
          Text(
            collaboratorDraftDescription
          )
          .font(.subheadline)
          .foregroundStyle(TunedInDesign.mutedText)
        }
      }
      .padding(.horizontal, 20)
      .padding(.top, 10)
      .padding(.bottom, TunedInDesign.scrollContentBottomInset)
    }
  }

  private var availableVisibility: [ConcertVisibility] {
    canMakePrivate ? ConcertVisibility.allCases : [.collaborators, .friends]
  }

  private var collaboratorDraftDescription: String {
    guard !workingDetail.collaborators.isEmpty else {
      return "No one is tagged. Add editors from the People view after you save."
    }

    let editorSuffix = workingDetail.collaborators.count == 1 ? "" : "s"
    return "\(workingDetail.collaborators.count) tagged editor\(editorSuffix). "
      + "Manage them from the People view so access changes never hide inside this draft."
  }

  private func visibilityChoice(_ option: ConcertVisibility) -> some View {
    Button {
      if option == .private || (visibility == .friends && option == .collaborators) {
        pendingVisibilityNarrowing = option
      } else {
        withAnimation(.snappy) { visibility = option }
      }
    } label: {
      HStack(spacing: 14) {
        Image(systemName: visibilityIcon(option))
          .font(.headline)
          .foregroundStyle(visibility == option ? TunedInDesign.actionForeground : TunedInDesign.accent)
          .frame(width: 42, height: 42)
          .background(visibility == option ? TunedInDesign.accent : TunedInDesign.accentTint, in: Circle())
        VStack(alignment: .leading, spacing: 2) {
          Text(visibilityTitle(option))
            .font(.headline)
          Text(visibilitySubtitle(option))
            .font(.subheadline)
            .foregroundStyle(
              visibility == option ? TunedInDesign.actionForeground.opacity(0.8) : TunedInDesign.mutedText
            )
        }
        Spacer()
        if visibility == option {
          Image(systemName: "checkmark.circle.fill")
        }
      }
      .foregroundStyle(visibility == option ? TunedInDesign.actionForeground : TunedInDesign.primaryText)
      .padding(15)
      .background(
        visibility == option ? TunedInDesign.accent : TunedInDesign.cardBackground,
        in: RoundedRectangle(cornerRadius: 18, style: .continuous)
      )
      .overlay {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
          .strokeBorder(TunedInDesign.cardBorder.opacity(0.7))
      }
    }
    .buttonStyle(.plain)
  }

  private var sharingTitle: String {
    switch visibility {
    case .private: "Only you can see this."
    case .collaborators: "Tagged people can edit."
    case .friends: "Friends can view and comment."
    }
  }

  private var sharingDescription: String {
    switch visibility {
    case .private: "You can change this later."
    case .collaborators: "Editors can update the details and setlist."
    case .friends: "Editors keep editing rights; friends cannot change the night."
    }
  }

  private var saveBar: some View {
    TunedInGlassTraversalLayout {
      TunedInGlassIconButton(
        systemImage: "chevron.backward",
        accessibilityLabel: "Cancel editing"
      ) {
        if hasUnsavedChanges {
          isShowingDiscardConfirmation = true
        } else {
          dismiss()
        }
      }
      .disabled(isSaving)
    } center: {
      TunedInGlassBottomBar {
        HStack(spacing: 2) {
          ForEach(EditPage.allCases) { item in
            Button {
              withAnimation(.smooth(duration: 0.24, extraBounce: 0)) { page = item }
            } label: {
              VStack(spacing: 2) {
                Image(systemName: item.icon).font(.subheadline.weight(.bold))
                Text(item.title)
                  .font(.caption2.weight(.bold))
                  .lineLimit(1)
                  .minimumScaleFactor(0.68)
              }
              .foregroundStyle(page == item ? TunedInDesign.actionForeground : TunedInDesign.primaryText)
              .frame(maxWidth: .infinity)
              .frame(height: 48)
              .background {
                if page == item {
                  Capsule()
                    .fill(TunedInDesign.accent)
                    .matchedGeometryEffect(id: "edit-page", in: editSelectionNamespace)
                }
              }
              .contentShape(.interaction, Capsule())
            }
            .buttonStyle(.plain)
            .contentShape(.interaction, Capsule())
            .accessibilityLabel("Show \(item.title.lowercased())")
          }
        }
      }
      .frame(maxWidth: 252)
    } trailing: {
      TunedInGlassTextButton(
        isSaving ? "Saving" : "Save",
        systemImage: isSaving ? "ellipsis" : "checkmark",
        accessibilityHint: "Saves the complete draft and returns to the concert",
        action: save
      )
      .disabled(!canSaveDraft)
      .opacity(canSaveDraft ? 1 : 0.45)
    }
    .padding(.horizontal, TunedInDesign.bottomControlHorizontalInset)
    .padding(.top, 8)
    .padding(.bottom, TunedInDesign.bottomControlInset)
  }

  private var hasMetadataChanges: Bool {
    draft != originalDraft || visibility != originalVisibility
  }

  private var hasUnsavedChanges: Bool {
    hasMetadataChanges || photoDraftChange != .unchanged
  }

  private var canSaveDraft: Bool {
    draft.canSave && hasUnsavedChanges && !isSaving && !isProcessingPhoto
  }

  private var isShowingError: Binding<Bool> {
    Binding(get: { errorMessage != nil }, set: {
      if !$0 {
        errorMessage = nil
      }
    })
  }

  private var isShowingVisibilityNarrowingConfirmation: Binding<Bool> {
    Binding(get: { pendingVisibilityNarrowing != nil }, set: {
      if !$0 {
        pendingVisibilityNarrowing = nil
      }
    })
  }

  private var accessRestrictionTitle: String {
    pendingVisibilityNarrowing == .private ? "Make this concert private?" : "Remove Friends access?"
  }

  private var accessRestrictionDescription: String {
    pendingVisibilityNarrowing == .private
      ? "When you save, everyone you tagged will lose access and only you will be able to see this concert."
      : "When you save, friends who are not tagged editors will lose access. Tagged editors keep their role."
  }

  private func cancelAccessRestrictionTitle(for option: ConcertVisibility) -> String {
    option == .private ? "Keep sharing" : "Keep Friends access"
  }

  private func confirmAccessRestrictionTitle(for option: ConcertVisibility) -> String {
    option == .private ? "Make Private" : "Limit to \(visibilityTitle(option))"
  }

  private var isShowingConflict: Binding<Bool> {
    Binding(get: { conflictMessage != nil }, set: {
      if !$0 {
        conflictMessage = nil
      }
    })
  }

  @ViewBuilder
  private func catalogPicker(for target: ConcertCatalogPickerTarget) -> some View {
    switch target {
    case let .artist(id):
      CatalogPickerView(
        repository: musicCatalogRepository,
        configuration: CatalogPickerConfiguration(
          kind: .artist,
          title: draft.artists.contains(where: { $0.id == id }) ? "Replace artist" : "Add artist",
          concertContextID: detail.concert.id,
          currentSelectionName: draft.artists.first(where: { $0.id == id })?.selection?.displayName
        )
      ) { entity in
        guard case let .artist(artist) = entity else { return }
        if draft.artists.contains(where: { $0.id == id }) {
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
          concertContextID: detail.concert.id,
          currentSelectionName: draft.place?.displayName
        )
      ) { entity in
        guard case let .place(place) = entity else { return }
        draft.place = place
        catalogPickerTarget = nil
      }
    case let .song(id):
      CatalogPickerView(
        repository: musicCatalogRepository,
        configuration: CatalogPickerConfiguration(
          kind: .song,
          title: id == nil ? "Add song" : "Replace song",
          artistContext: draft.selectedCatalogArtists,
          concertContextID: detail.concert.id,
          currentSelectionName: id.flatMap { selectedID in
            draft.setlist.first(where: { $0.id == selectedID })?.title
          }
        )
      ) { entity in
        guard case let .song(song) = entity else { return }
        if let id {
          draft.replaceSetlistItem(id, with: song)
        } else {
          draft.addSetlistItem(song)
        }
        catalogPickerTarget = nil
      }
    case .tour:
      CatalogPickerView(
        repository: musicCatalogRepository,
        configuration: CatalogPickerConfiguration(
          kind: .tour,
          title: "Choose tour",
          artistContext: draft.selectedCatalogArtists,
          concertContextID: detail.concert.id,
          currentSelectionName: draft.tour?.displayName
        )
      ) { entity in
        guard case let .tour(tour) = entity else { return }
        draft.tour = tour
        catalogPickerTarget = nil
      }
    }
  }

  private func visibilityIcon(_ option: ConcertVisibility) -> String {
    switch option {
    case .private: "lock.fill"
    case .collaborators: "person.2.fill"
    case .friends: "heart.fill"
    }
  }

  private func visibilityTitle(_ option: ConcertVisibility) -> String {
    switch option {
    case .private: "Private"
    case .collaborators: "Collaborators"
    case .friends: "Friends"
    }
  }

  private func visibilitySubtitle(_ option: ConcertVisibility) -> String {
    switch option {
    case .private: "Just you, for now"
    case .collaborators: "Only your tagged editors"
    case .friends: "Your accepted friends can look in"
    }
  }

  private func save() {
    draft.hasAttemptedSave = true
    guard canSaveDraft else { return }
    isSaving = true
    let startedAt = ContinuousClock.now
    Task {
      var updatedConcert = workingDetail.concert
      var metadataWasSaved = false
      defer { isSaving = false }

      do {
        if hasMetadataChanges {
          guard let input = draft.updateInput(
            concertID: detail.concert.id,
            expectedVersion: expectedVersion,
            visibility: visibility
          ) else { return }
          updatedConcert = try await concertRepository.updateConcert(input)
          metadataWasSaved = true
          adoptSavedMetadata(updatedConcert)
        }

        switch photoDraftChange {
        case let .replacement(jpeg):
          updatedConcert = try await concertRepository.setConcertPhoto(
            jpeg,
            concertID: detail.concert.id
          )
          adoptSavedPhoto(updatedConcert)
        case .removal:
          updatedConcert = try await concertRepository.removeConcertPhoto(
            concertID: detail.concert.id
          )
          adoptSavedPhoto(updatedConcert)
        case .unchanged:
          break
        }

        telemetry?.capture(
          .concertUpdated,
          properties: [
            .changeKind: .string(changeKindForTelemetry.rawValue),
            .durationMilliseconds: .integer(startedAt.duration(to: .now).editTelemetryMilliseconds)
          ]
        )
        onSaved(updatedConcert)
        dismiss()
      } catch {
        if metadataWasSaved {
          onSaved(updatedConcert)
          errorMessage = "Your details are saved, but the photo couldn’t be updated. "
            + "The photo is still ready here—tap Save to try it again."
          return
        }

        let failure = AppFailure(error)
        if failure.shouldReportToTelemetry {
          telemetry?.captureOperation(
            .updateConcert,
            outcome: .failed,
            duration: startedAt.duration(to: .now),
            failure: failure
          )
        }
        if isConcertConflict(error) {
          conflictMessage = error.localizedDescription
        } else {
          errorMessage = error.localizedDescription
        }
      }
    }
  }

  private func adoptSavedMetadata(_ concert: Concert) {
    expectedVersion = concert.version
    originalDraft = draft
    originalVisibility = visibility
    workingDetail = detailReplacingConcert(concert)
  }

  private func adoptSavedPhoto(_ concert: Concert) {
    photoDraftChange = .unchanged
    selectedPhoto = nil
    workingDetail = detailReplacingConcert(concert)
  }

  private func detailReplacingConcert(_ concert: Concert) -> ConcertDetail {
    ConcertDetail(
      concert: concert,
      artists: workingDetail.artists,
      setlist: workingDetail.setlist,
      history: workingDetail.history,
      collaborators: workingDetail.collaborators
    )
  }

  private var changeKindForTelemetry: TelemetryChangeKind {
    switch page {
    case .night: .details
    case .songs: .setlist
    case .sharing: .sharing
    }
  }

  private func reloadAfterConflict() async {
    isReloadingAfterConflict = true
    defer { isReloadingAfterConflict = false }

    do {
      let latest = try await loadLatestDetail()
      let latestDraft = ConcertDraft(detail: latest)
      draft = latestDraft
      originalDraft = latestDraft
      visibility = latest.concert.visibility
      originalVisibility = visibility
      expectedVersion = latest.concert.version
      workingDetail = latest
      photoDraftChange = .unchanged
      selectedPhoto = nil
      conflictMessage = nil
      errorMessage = nil
    } catch {
      conflictMessage = nil
      errorMessage = error.localizedDescription
    }
  }

  private func isConcertConflict(_ error: Error) -> Bool {
    error.appFailure == .conflict
  }
}

private extension Duration {
  var editTelemetryMilliseconds: Int {
    let components = components
    return Int(components.seconds * 1000 + components.attoseconds / 1_000_000_000_000_000)
  }
}

// swiftlint:enable type_body_length
