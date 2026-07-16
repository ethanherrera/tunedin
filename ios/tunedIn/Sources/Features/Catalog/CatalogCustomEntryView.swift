import SwiftUI

enum CatalogCustomEntryDefaults {
  static func selectedArtists(
    for kind: CatalogEntityKind,
    artistContext: [CatalogArtist]
  ) -> [CatalogArtist] {
    kind == .song ? Array(artistContext.prefix(1)) : artistContext
  }
}

// swiftlint:disable:next type_body_length
struct CatalogCustomEntryView: View {
  private enum AreaPickerPurpose: String, Identifiable {
    case artistArea
    case parentArea
    case placeArea

    var id: String {
      rawValue
    }

    var title: String {
      switch self {
      case .artistArea: "Choose artist area"
      case .parentArea: "Choose parent area"
      case .placeArea: "Choose venue city"
      }
    }
  }

  let repository: any MusicCatalogRepository
  let kind: CatalogEntityKind
  let suggestedName: String
  let artistContext: [CatalogArtist]
  let concertContextID: UUID?
  let onCreated: (CatalogEntity) -> Void

  @Environment(\.dismiss) private var dismiss
  @State private var name: String
  @State private var artistType = ""
  @State private var disambiguation = ""
  @State private var countryCode = ""
  @State private var placeType = ""
  @State private var address = ""
  @State private var selectedArea: CatalogArea?
  @State private var selectedParentArea: CatalogArea?
  @State private var selectedArtists: [CatalogArtist]
  @State private var areaPickerPurpose: AreaPickerPurpose?
  @State private var isPresentingArtistPicker = false
  @State private var isSaving = false
  @State private var errorMessage: String?

  init(
    repository: any MusicCatalogRepository,
    kind: CatalogEntityKind,
    suggestedName: String,
    artistContext: [CatalogArtist],
    concertContextID: UUID?,
    onCreated: @escaping (CatalogEntity) -> Void
  ) {
    self.repository = repository
    self.kind = kind
    self.suggestedName = suggestedName
    self.artistContext = artistContext
    self.concertContextID = concertContextID
    self.onCreated = onCreated
    _name = State(initialValue: suggestedName)
    _selectedArtists = State(
      initialValue: CatalogCustomEntryDefaults.selectedArtists(for: kind, artistContext: artistContext)
    )
  }

  var body: some View {
    NavigationStack {
      ZStack {
        TunedInDesign.pageBackground.ignoresSafeArea()

        ScrollView {
          VStack(alignment: .leading, spacing: 18) {
            header
            fields
            reuseNotice
          }
          .padding(.horizontal, 20)
          .padding(.top, 18)
          .padding(.bottom, 28)
        }
      }
      .toolbar(.hidden, for: .navigationBar)
      .safeAreaInset(edge: .bottom, spacing: 0) {
        TunedInPersistentControlRegion {
          bottomControls
        }
      }
    }
    .tint(TunedInDesign.accent)
    .tunedInKeyboardManaged()
    .tunedInEdgeSwipeBack(isEnabled: !isSaving) { dismiss() }
    .fullScreenCover(item: $areaPickerPurpose) { purpose in
      CatalogPickerView(
        repository: repository,
        configuration: CatalogPickerConfiguration(
          kind: .area,
          title: purpose.title,
          concertContextID: concertContextID,
          currentSelectionName: currentAreaName(for: purpose)
        )
      ) { entity in
        guard case let .area(area) = entity else { return }
        switch purpose {
        case .artistArea, .placeArea: selectedArea = area
        case .parentArea: selectedParentArea = area
        }
        areaPickerPurpose = nil
      }
    }
    .fullScreenCover(isPresented: $isPresentingArtistPicker) {
      CatalogPickerView(
        repository: repository,
        configuration: CatalogPickerConfiguration(
          kind: .artist,
          title: "Choose an artist",
          concertContextID: concertContextID
        )
      ) { entity in
        guard case let .artist(artist) = entity else { return }
        if !selectedArtists.contains(where: { $0.id == artist.id }) {
          selectedArtists.append(artist)
        }
        isPresentingArtistPicker = false
      }
    }
    .alert("Couldn’t add to your catalog", isPresented: isShowingError) {
      Button("OK", role: .cancel) { errorMessage = nil }
    } message: {
      Text(errorMessage ?? "Please try again.")
    }
  }

  private var header: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text("Add \(kind.singularTitle.lowercased())")
        .font(.system(size: 32, weight: .bold, design: .serif))
        .foregroundStyle(TunedInDesign.primaryText)
      Text("This creates a reusable entry in your tunedIn catalog for future searches.")
        .font(.subheadline)
        .foregroundStyle(TunedInDesign.mutedText)
    }
  }

  @ViewBuilder
  private var fields: some View {
    switch kind {
    case .artist:
      artistFields
    case .area:
      areaFields
    case .place:
      placeFields
    case .song:
      songFields
    case .tour:
      tourFields
    }
  }

  private var nameField: some View {
    TextField(namePrompt, text: $name)
      .textInputAutocapitalization(.words)
      .autocorrectionDisabled(false)
      .accessibilityLabel(namePrompt)
  }

  private var artistFields: some View {
    TunedInFormCard {
      Text("Artist details")
        .font(.headline)
        .foregroundStyle(TunedInDesign.primaryText)
      nameField
      Picker("Type", selection: $artistType) {
        Text("Not specified").tag("")
        ForEach(["Person", "Group", "Orchestra", "Choir", "Character", "Other"], id: \.self) {
          Text($0).tag($0)
        }
      }
      TextField("Disambiguation (optional)", text: $disambiguation)
      selectionButton(
        title: "Area (optional)",
        selection: selectedArea?.displayName,
        systemImage: "map"
      ) {
        areaPickerPurpose = .artistArea
      }
      if selectedArea != nil {
        Button("Remove area", role: .destructive) { selectedArea = nil }
          .font(.caption.weight(.semibold))
      }
    }
  }

  private var areaFields: some View {
    TunedInFormCard {
      Text("City or area details")
        .font(.headline)
        .foregroundStyle(TunedInDesign.primaryText)
      nameField
      TextField("Country code (optional)", text: $countryCode)
        .textInputAutocapitalization(.characters)
        .autocorrectionDisabled()
        .onChange(of: countryCode) { _, value in
          countryCode = String(value.uppercased().prefix(2))
        }
      selectionButton(
        title: "Parent area (optional)",
        selection: selectedParentArea?.displayName,
        systemImage: "map"
      ) {
        areaPickerPurpose = .parentArea
      }
      if selectedParentArea != nil {
        Button("Remove parent area", role: .destructive) { selectedParentArea = nil }
          .font(.caption.weight(.semibold))
      }
    }
  }

  private var placeFields: some View {
    TunedInFormCard {
      Text("Venue details")
        .font(.headline)
        .foregroundStyle(TunedInDesign.primaryText)
      nameField
      Picker("Type", selection: $placeType) {
        Text("Not specified").tag("")
        ForEach(["Venue", "Stadium", "Arena", "Amphitheatre", "Hall", "Club", "Other"], id: \.self) {
          Text($0).tag($0)
        }
      }
      TextField("Address (optional)", text: $address)
        .textContentType(.fullStreetAddress)
      selectionButton(
        title: "City or area",
        selection: selectedArea?.displayName,
        systemImage: "mappin.and.ellipse"
      ) {
        areaPickerPurpose = .placeArea
      }
      Text("The chosen area becomes the concert city; it cannot be entered separately.")
        .font(.caption)
        .foregroundStyle(TunedInDesign.mutedText)
    }
  }

  private var songFields: some View {
    TunedInFormCard {
      Text("Song details")
        .font(.headline)
        .foregroundStyle(TunedInDesign.primaryText)
      nameField
      artistSelections
    }
  }

  private var tourFields: some View {
    TunedInFormCard {
      Text("Tour details")
        .font(.headline)
        .foregroundStyle(TunedInDesign.primaryText)
      nameField
      artistSelections
    }
  }

  private var artistSelections: some View {
    VStack(alignment: .leading, spacing: 9) {
      Text("Artists")
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(TunedInDesign.primaryText)
      ForEach(selectedArtists) { artist in
        HStack {
          Text(artist.displayName)
            .foregroundStyle(TunedInDesign.primaryText)
          Spacer()
          Button {
            selectedArtists.removeAll { $0.id == artist.id }
          } label: {
            Image(systemName: "xmark.circle.fill")
              .foregroundStyle(TunedInDesign.mutedText)
          }
          .buttonStyle(.plain)
          .accessibilityLabel("Remove \(artist.displayName)")
        }
      }
      Button {
        isPresentingArtistPicker = true
      } label: {
        Label("Add artist", systemImage: "plus.circle")
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(TunedInDesign.accent)
      }
      .buttonStyle(.plain)
      if selectedArtists.isEmpty {
        Text("Choose at least one artist so this entry can be distinguished and reused.")
          .font(.caption)
          .foregroundStyle(TunedInDesign.mutedText)
      }
    }
  }

  private var reuseNotice: some View {
    Label(
      "If this exact entry already exists in your catalog, tunedIn will reuse it instead of creating a duplicate.",
      systemImage: "arrow.triangle.2.circlepath"
    )
    .font(.caption)
    .foregroundStyle(TunedInDesign.mutedText)
    .padding(14)
    .background(TunedInDesign.raisedSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
  }

  private var bottomControls: some View {
    TunedInGlassTraversalLayout {
      TunedInGlassIconButton(
        systemImage: "chevron.backward",
        accessibilityLabel: "Cancel custom entry"
      ) {
        dismiss()
      }
      .disabled(isSaving)
    } center: {
      TunedInGlassBottomBar {
        Text("Your catalog")
          .font(.subheadline.weight(.bold))
          .foregroundStyle(TunedInDesign.primaryText)
          .frame(minWidth: 112, minHeight: 48)
          .padding(.horizontal, 14)
      }
    } trailing: {
      TunedInFloatingAction(
        systemImage: isSaving ? "ellipsis" : "checkmark",
        accessibilityLabel: isSaving ? "Adding catalog entry" : "Add to catalog",
        action: save
      )
      .disabled(!canSave || isSaving)
      .opacity(canSave && !isSaving ? 1 : 0.45)
    }
    .padding(.horizontal, TunedInDesign.bottomControlHorizontalInset)
    .padding(.top, 8)
    .padding(.bottom, TunedInDesign.bottomControlInset)
  }

  private var namePrompt: String {
    switch kind {
    case .artist: "Artist name"
    case .area: "City or area name"
    case .place: "Venue name"
    case .song: "Song title"
    case .tour: "Tour name"
    }
  }

  private var canSave: Bool {
    guard CatalogInput.isValidName(name) else { return false }
    return switch kind {
    case .artist, .area: true
    case .place: selectedArea != nil
    case .song, .tour: !selectedArtists.isEmpty
    }
  }

  private var isShowingError: Binding<Bool> {
    Binding(get: { errorMessage != nil }, set: {
      if !$0 {
        errorMessage = nil
      }
    })
  }

  private func selectionButton(
    title: String,
    selection: String?,
    systemImage: String,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      HStack(spacing: 10) {
        Image(systemName: systemImage)
          .foregroundStyle(TunedInDesign.accent)
        VStack(alignment: .leading, spacing: 2) {
          Text(title)
            .font(.caption)
            .foregroundStyle(TunedInDesign.mutedText)
          Text(selection ?? "Choose")
            .font(.body.weight(.semibold))
            .foregroundStyle(TunedInDesign.primaryText)
        }
        Spacer()
        Image(systemName: "chevron.forward")
          .font(.caption.weight(.bold))
          .foregroundStyle(TunedInDesign.mutedText)
      }
      .contentShape(.interaction, Rectangle())
    }
    .buttonStyle(.plain)
  }

  private func currentAreaName(for purpose: AreaPickerPurpose) -> String? {
    switch purpose {
    case .artistArea, .placeArea: selectedArea?.displayName
    case .parentArea: selectedParentArea?.displayName
    }
  }

  private func save() {
    guard canSave else { return }
    isSaving = true
    errorMessage = nil
    Task {
      do {
        let entity: CatalogEntity
        switch kind {
        case .artist:
          entity = try await .artist(
            repository.createCustomArtist(
              CustomCatalogArtistInput(
                name: name,
                artistType: CatalogInput.optionalNormalizedText(artistType),
                disambiguation: CatalogInput.optionalNormalizedText(disambiguation),
                areaID: selectedArea?.id,
                areaName: selectedArea?.displayName,
                concertContextID: concertContextID
              )
            )
          )
        case .area:
          entity = try await .area(
            repository.createCustomArea(
              CustomCatalogAreaInput(
                name: name,
                countryCode: CatalogInput.optionalNormalizedText(countryCode),
                parentAreaID: selectedParentArea?.id,
                concertContextID: concertContextID
              )
            )
          )
        case .place:
          guard let selectedArea else { return }
          entity = try await .place(
            repository.createCustomPlace(
              CustomCatalogPlaceInput(
                name: name,
                placeType: CatalogInput.optionalNormalizedText(placeType),
                address: CatalogInput.optionalNormalizedText(address),
                areaID: selectedArea.id,
                areaName: selectedArea.displayName,
                concertContextID: concertContextID
              )
            )
          )
        case .song:
          entity = try await .song(
            repository.createCustomSong(
              CustomCatalogSongInput(
                title: name,
                artistIDs: selectedArtists.map(\.id),
                artistNames: selectedArtists.map(\.displayName),
                concertContextID: concertContextID
              )
            )
          )
        case .tour:
          entity = try await .tour(
            repository.createCustomTour(
              CustomCatalogTourInput(
                name: name,
                artistIDs: selectedArtists.map(\.id),
                artistNames: selectedArtists.map(\.displayName),
                concertContextID: concertContextID
              )
            )
          )
        }
        onCreated(entity)
      } catch {
        errorMessage = error.localizedDescription
        isSaving = false
      }
    }
  }
}
