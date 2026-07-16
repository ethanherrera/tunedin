import SwiftUI

struct CatalogPickerConfiguration: Equatable, Sendable {
  let kind: CatalogEntityKind
  let title: String
  let artistContext: [CatalogArtist]
  let concertContextID: UUID?
  let currentSelectionName: String?
  let initialQuery: String

  init(
    kind: CatalogEntityKind,
    title: String? = nil,
    artistContext: [CatalogArtist] = [],
    concertContextID: UUID? = nil,
    currentSelectionName: String? = nil,
    initialQuery: String = ""
  ) {
    self.kind = kind
    self.title = title ?? "Choose \(kind.singularTitle.lowercased())"
    self.artistContext = artistContext
    self.concertContextID = concertContextID
    self.currentSelectionName = currentSelectionName
    self.initialQuery = initialQuery
  }
}

struct CatalogPickerView: View {
  let repository: any MusicCatalogRepository
  let configuration: CatalogPickerConfiguration
  let onSelect: (CatalogEntity) -> Void

  @Environment(\.dismiss) private var dismiss
  @State private var model: CatalogSearchModel
  @State private var isPresentingCustomEntry = false
  @State private var isUsingArtistContext = true
  @State private var selectionTask: Task<Void, Never>?
  @State private var recentSearches: [String]

  init(
    repository: any MusicCatalogRepository,
    configuration: CatalogPickerConfiguration,
    onSelect: @escaping (CatalogEntity) -> Void
  ) {
    self.repository = repository
    self.configuration = configuration
    self.onSelect = onSelect
    _model = State(
      initialValue: CatalogSearchModel(
        repository: repository,
        kind: configuration.kind,
        artistContextIDs: configuration.artistContext.map(\.id),
        concertContextID: configuration.concertContextID
      )
    )
    _recentSearches = State(
      initialValue: CatalogRecentSearchStore.values(for: configuration.kind)
    )
  }

  var body: some View {
    NavigationStack {
      ZStack {
        TunedInDesign.pageBackground.ignoresSafeArea()

        VStack(spacing: 0) {
          header
          searchField
          songSearchScope
          phaseContent
        }
      }
      .toolbar(.hidden, for: .navigationBar)
      .safeAreaInset(edge: .bottom, spacing: 0) {
        TunedInPersistentControlRegion {
          TunedInSubscreenBackBar(title: configuration.kind.singularTitle) {
            cancelSelectionAndDismiss()
          }
          .padding(.horizontal, TunedInDesign.bottomControlHorizontalInset)
          .padding(.top, 8)
          .padding(.bottom, TunedInDesign.bottomControlInset)
        }
      }
    }
    .tint(TunedInDesign.accent)
    .tunedInKeyboardManaged()
    .tunedInEdgeSwipeBack { cancelSelectionAndDismiss() }
    .fullScreenCover(isPresented: $isPresentingCustomEntry) {
      CatalogCustomEntryView(
        repository: repository,
        kind: configuration.kind,
        suggestedName: CatalogInput.normalizedText(model.query),
        artistContext: configuration.artistContext,
        concertContextID: configuration.concertContextID
      ) { entity in
        onSelect(entity)
        isPresentingCustomEntry = false
        Task { @MainActor in
          await Task.yield()
          dismiss()
        }
      }
    }
    .task {
      guard !configuration.initialQuery.isEmpty, model.query.isEmpty else { return }
      model.updateQuery(configuration.initialQuery)
    }
    .onDisappear(perform: cancelSelection)
    .alert("Couldn’t select that result", isPresented: selectionErrorIsPresented) {
      Button("OK", role: .cancel) { model.clearSelectionError() }
    } message: {
      Text(model.selectionErrorMessage ?? "Please try again.")
    }
  }

  @ViewBuilder
  private var songSearchScope: some View {
    if configuration.kind == .song, !configuration.artistContext.isEmpty {
      Picker("Recording search scope", selection: $isUsingArtistContext) {
        Text("Lineup artists").tag(true)
        Text("All artists").tag(false)
      }
      .pickerStyle(.segmented)
      .padding(.horizontal, 20)
      .padding(.bottom, 10)
      .onChange(of: isUsingArtistContext) { _, enabled in
        model.setArtistContextEnabled(enabled)
      }
      .accessibilityHint("Choose whether MusicBrainz recording results are filtered to the concert lineup.")
    }
  }

  private var header: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(configuration.title)
        .font(.system(size: 32, weight: .bold, design: .serif))
        .foregroundStyle(TunedInDesign.primaryText)

      if let current = configuration.currentSelectionName {
        Text("Current: \(current)")
          .font(.subheadline)
          .foregroundStyle(TunedInDesign.mutedText)
          .lineLimit(2)
      } else {
        Text(disambiguationHint)
          .font(.subheadline)
          .foregroundStyle(TunedInDesign.mutedText)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.horizontal, 20)
    .padding(.top, 18)
    .padding(.bottom, 12)
  }

  private var searchField: some View {
    TunedInGlassSearchField(
      text: Binding(
        get: { model.query },
        set: {
          selectionTask?.cancel()
          selectionTask = nil
          model.updateQuery($0)
        }
      ),
      prompt: configuration.kind.searchPrompt
    )
    .padding(.horizontal, 20)
    .padding(.bottom, 10)
  }

  @ViewBuilder
  private var phaseContent: some View {
    switch model.phase {
    case .idle:
      if recentSearches.isEmpty {
        statusView(
          title: "Start with two characters",
          description: "Search your saved catalog and MusicBrainz together.",
          systemImage: "magnifyingglass"
        )
      } else {
        CatalogRecentSearchesView(
          kind: configuration.kind,
          values: recentSearches,
          onSelect: updateQuery,
          onAddCustom: showCustomEntry
        )
      }
    case .loading:
      catalogLoadingView
    case .results:
      resultsList
    case .empty:
      statusWithCustomAction(
        title: "No matching \(configuration.kind.singularTitle.lowercased())",
        description: "Try a more specific search, or add a reusable entry to your tunedIn catalog.",
        systemImage: "music.note"
      )
    case .offline:
      retryStatus(
        title: "You’re offline",
        description: "Reconnect and try again. Your existing concert selection has not changed.",
        systemImage: "wifi.slash"
      )
    case let .rateLimited(retryAfterSeconds):
      retryStatus(
        title: "Search is taking a beat",
        description: retryAfterSeconds.map {
          "MusicBrainz asked us to wait about \(max(1, Int($0.rounded(.up)))) seconds."
        } ?? "MusicBrainz asked us to wait before searching again.",
        systemImage: "clock.badge.exclamationmark"
      )
    case let .failed(message, retryable):
      if retryable {
        retryStatus(title: "Couldn’t search", description: message, systemImage: "exclamationmark.triangle")
      } else {
        statusWithCustomAction(title: "Couldn’t search", description: message, systemImage: "exclamationmark.triangle")
      }
    }
  }

  private var resultsList: some View {
    CatalogResultsList(
      model: model,
      configuration: configuration,
      isUsingArtistContext: isUsingArtistContext,
      onSelect: select,
      onAddCustom: showCustomEntry
    )
  }

  private var customAction: some View {
    CatalogCustomEntryAction(action: showCustomEntry)
  }

  private func statusView(title: String, description: String, systemImage: String) -> some View {
    ContentUnavailableView {
      Label(title, systemImage: systemImage)
    } description: {
      Text(description)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .padding(.horizontal, 20)
  }

  private func statusWithCustomAction(title: String, description: String, systemImage: String) -> some View {
    ContentUnavailableView {
      Label(title, systemImage: systemImage)
    } description: {
      Text(description)
    } actions: {
      Button("Clear search") { updateQuery("") }
      customAction
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .padding(.horizontal, 20)
  }

  private func retryStatus(title: String, description: String, systemImage: String) -> some View {
    ContentUnavailableView {
      Label(title, systemImage: systemImage)
    } description: {
      Text(description)
    } actions: {
      Button("Try again") { model.retry() }
        .buttonStyle(.borderedProminent)
      Button("Clear search") { updateQuery("") }
      customAction
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .padding(.horizontal, 20)
  }

  private var catalogLoadingView: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Searching your catalog and MusicBrainz…")
        .font(.subheadline)
        .foregroundStyle(TunedInDesign.mutedText)

      ForEach(0 ..< 4, id: \.self) { _ in
        TunedInSkeletonBlock(cornerRadius: 16)
          .frame(height: 68)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .padding(.horizontal, 20)
    .padding(.top, 12)
    .accessibilityLabel("Searching the catalog")
  }

  private var disambiguationHint: String {
    switch configuration.kind {
    case .artist: "Compare type, area, and disambiguation before choosing."
    case .area: "Compare country and parent area before choosing."
    case .place: "The selected venue determines the concert city."
    case .song: "Compare artist credit and release date before choosing."
    case .tour: "Compare the associated artist before choosing."
    }
  }

  private var selectionErrorIsPresented: Binding<Bool> {
    Binding(
      get: { model.selectionErrorMessage != nil },
      set: {
        if !$0 {
          model.clearSelectionError()
        }
      }
    )
  }

  private func select(_ result: CatalogResult) {
    selectionTask?.cancel()
    selectionTask = Task { @MainActor in
      guard let entity = await model.resolve(result) else { return }
      guard !Task.isCancelled else { return }
      recentSearches = CatalogRecentSearchStore.record(
        entity.displayName,
        for: configuration.kind
      )
      onSelect(entity)
      dismiss()
    }
  }

  private func updateQuery(_ query: String) {
    selectionTask?.cancel()
    selectionTask = nil
    model.updateQuery(query)
  }

  private func showCustomEntry() {
    isPresentingCustomEntry = true
  }

  private func cancelSelection() {
    selectionTask?.cancel()
    selectionTask = nil
    model.cancelResolution()
  }

  private func cancelSelectionAndDismiss() {
    cancelSelection()
    dismiss()
  }
}
