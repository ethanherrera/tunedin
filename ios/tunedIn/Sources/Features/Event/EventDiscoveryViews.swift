import PhotosUI
import SwiftUI

struct EventDiscoveryView: View {
  private enum SearchScope: String, CaseIterable, Hashable {
    case concerts = "Concert"
    case people = "People"
  }

  private struct SearchRequest: Hashable {
    let scope: SearchScope
    let query: String
    let filter: EventSearchFilter
  }

  let viewerID: UUID
  let eventRepository: any EventRepository
  let onOpenEvent: (CommunityEventSummary) -> Void
  let onOpenProfile: (SocialProfile) -> Void

  @State private var query = ""
  @State private var selectedScope = SearchScope.concerts
  @State private var results: [CommunityEventSummary] = []
  @State private var isLoadingEvents = false
  @State private var isLoadingMoreEvents = false
  @State private var eventSearchHasMore = false
  @State private var nextEventSearchOffset = 0
  @State private var eventSearchFilter = EventSearchFilter.none
  @State private var isShowingFilterMenu = false
  @State private var isShowingDateFilter = false
  @State private var eventErrorMessage: String?
  @State private var peopleModel: PeopleHubModel
  @FocusState private var isSearchFieldFocused: Bool

  init(
    viewerID: UUID,
    eventRepository: any EventRepository,
    socialRepository: any SocialRepository,
    currentUsername: String,
    onOpenEvent: @escaping (CommunityEventSummary) -> Void,
    onOpenProfile: @escaping (SocialProfile) -> Void
  ) {
    self.viewerID = viewerID
    self.eventRepository = eventRepository
    self.onOpenEvent = onOpenEvent
    self.onOpenProfile = onOpenProfile
    _peopleModel = State(
      initialValue: PeopleHubModel(
        repository: socialRepository,
        currentUsername: currentUsername
      )
    )
  }

  var body: some View {
    ZStack {
      TunedInDesign.pageBackground.ignoresSafeArea()

      VStack(alignment: .leading, spacing: 14) {
        VStack(alignment: .leading, spacing: 14) {
          TunedInGlassSearchField(
            text: $query,
            prompt: selectedScope == .concerts ? "Search concerts" : "Search people by username",
            isFocused: $isSearchFieldFocused
          )

          Picker("Search category", selection: $selectedScope) {
            ForEach(SearchScope.allCases, id: \.self) { scope in
              Text(scope.rawValue).tag(scope)
            }
          }
          .pickerStyle(.segmented)
          .opacity(isSearchActive ? 1 : 0)
          .allowsHitTesting(isSearchActive)
          .accessibilityHidden(!isSearchActive)

        }
        .padding(.horizontal, 20)
        .padding(.top, 18)

        ScrollView {
          searchResults
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
      }

      if selectedScope == .concerts, isSearchActive {
        if isShowingFilterMenu {
          Color.clear
            .contentShape(Rectangle())
            .onTapGesture {
              isShowingFilterMenu = false
            }
        }

        VStack {
          Spacer()
          HStack {
            Spacer()
            VStack(alignment: .trailing, spacing: 10) {
              if isShowingFilterMenu {
                EventSearchFilterMenu(isActive: isDateFilterActive) {
                  isShowingFilterMenu = false
                  Task { @MainActor in
                    await Task.yield()
                    isShowingDateFilter = true
                  }
                }
                .transition(.scale(scale: 0.9, anchor: .bottomTrailing).combined(with: .opacity))
              }

              floatingFilterControl
            }
          }
        }
        .padding(.trailing, 24)
        .padding(.bottom, 20)
        .animation(.snappy(duration: 0.24), value: isShowingFilterMenu)
      }
    }
    .toolbar(.hidden, for: .navigationBar)
    .sheet(isPresented: $isShowingDateFilter) {
      EventSearchDateFilterSheet(filter: eventSearchFilter) { filter in
        eventSearchFilter = filter
      } onClear: {
        eventSearchFilter = .none
      }
      .presentationDetents([.medium, .large])
    }
    .task(id: searchRequest) {
      guard !normalizedQuery.isEmpty else {
        clearSearchResults()
        return
      }
      try? await Task.sleep(for: .milliseconds(250))
      guard !Task.isCancelled else { return }
      await searchSelectedScope()
    }
  }

  @ViewBuilder
  private var searchResults: some View {
    if !normalizedQuery.isEmpty {
      switch selectedScope {
      case .concerts:
        concertResults
      case .people:
        peopleResults
      }
    }
  }

  @ViewBuilder
  private var concertResults: some View {
    if isLoadingEvents {
      ForEach(0 ..< 4, id: \.self) { _ in
        TunedInSkeletonBlock(cornerRadius: TunedInDesign.cornerRadius)
          .frame(height: 126)
      }
    } else if let eventErrorMessage {
      EventFailureView(message: eventErrorMessage) { Task { await searchEvents() } }
    } else if results.isEmpty {
      EventEmptyView(
        systemImage: "music.note.list",
        title: "No matching concerts",
        message: "Try a different artist, venue, city, or tour."
      )
    } else {
      LazyVStack(spacing: 12) {
        ForEach(results) { event in
          Button {
            isSearchFieldFocused = false
            onOpenEvent(event)
          } label: {
            CommunityEventRow(event: event, showsSource: true, eventRepository: eventRepository)
          }
          .buttonStyle(TunedInPosterButtonStyle())
          .onAppear {
            guard event.id == results.last?.id, eventSearchHasMore, !isLoadingMoreEvents else { return }
            Task { await loadMoreEvents() }
          }
        }
        if isLoadingMoreEvents {
          ProgressView("Loading more concerts")
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
        }
      }
    }
  }

  @ViewBuilder
  private var peopleResults: some View {
    let normalizedQuery = ProfileInput.normalizedSearchQuery(query)
    if peopleModel.isSearching {
      VStack(spacing: 8) {
        ForEach(0 ..< 5, id: \.self) { _ in
          HStack(spacing: 12) {
            TunedInSkeletonBlock(cornerRadius: 26).frame(width: 52, height: 52)
            VStack(alignment: .leading, spacing: 7) {
              TunedInSkeletonBlock(cornerRadius: 5).frame(width: 132, height: 15)
              TunedInSkeletonBlock(cornerRadius: 5).frame(width: 180, height: 12)
            }
            Spacer()
          }
          .padding(.vertical, 8)
        }
      }
      .accessibilityLabel("Searching people")
    } else if let errorMessage = peopleModel.errorMessage {
      EventFailureView(message: errorMessage) { Task { await searchPeople(refresh: true) } }
    } else if peopleModel.searchResults.isEmpty {
      EventEmptyView(
        systemImage: "person.crop.circle.badge.questionmark",
        title: "No people found",
        message: "Try another @username."
      )
    } else {
      LazyVStack(spacing: 0) {
        ForEach(peopleModel.searchResults) { profile in
          Button {
            isSearchFieldFocused = false
            onOpenProfile(profile)
          } label: {
            PeopleSearchResultRow(profile: profile)
          }
          .buttonStyle(.plain)

          if profile.id != peopleModel.searchResults.last?.id {
            Divider()
              .overlay(TunedInDesign.cardBorder.opacity(0.7))
              .padding(.leading, 64)
          }
        }
      }
    }
  }

  private var searchRequest: SearchRequest {
    SearchRequest(
      scope: selectedScope,
      query: query,
      filter: selectedScope == .concerts ? eventSearchFilter : .none
    )
  }

  private var normalizedQuery: String {
    switch selectedScope {
    case .concerts:
      CatalogInput.normalizedText(query)
    case .people:
      ProfileInput.normalizedSearchQuery(query)
    }
  }

  private var isSearchActive: Bool {
    !query.isEmpty
  }

  private var floatingFilterControl: some View {
    TunedInGlassIconButton(
      systemImage: "line.3.horizontal.decrease",
      accessibilityLabel: "Open search filters",
      style: isDateFilterActive ? .accent : .neutral,
      remainsVisibleWithKeyboard: true
    ) {
      isSearchFieldFocused = false
      isShowingFilterMenu.toggle()
    }
  }

  private var isDateFilterActive: Bool {
    eventSearchFilter != .none
  }

  @MainActor
  private func searchSelectedScope() async {
    switch selectedScope {
    case .concerts:
      await searchEvents()
    case .people:
      await searchPeople()
    }
  }

  private func clearSearchResults() {
    results = []
    isLoadingEvents = false
    isLoadingMoreEvents = false
    eventSearchHasMore = false
    nextEventSearchOffset = 0
    eventErrorMessage = nil
    peopleModel.query = ""
  }

  @MainActor
  private func searchEvents() async {
    guard !CatalogInput.normalizedText(query).isEmpty else { return }
    isLoadingEvents = true
    defer { isLoadingEvents = false }
    do {
      let page = try await eventRepository.searchEvents(
        query: query,
        filter: eventSearchFilter,
        offset: 0,
        viewerID: viewerID
      )
      guard !Task.isCancelled else { return }
      results = page.events
      nextEventSearchOffset = page.offset + EventSearchPage.limit
      eventSearchHasMore = page.hasMore
      eventErrorMessage = nil
    } catch {
      guard !Task.isCancelled else { return }
      eventErrorMessage = error.localizedDescription
    }
  }

  @MainActor
  private func loadMoreEvents() async {
    guard eventSearchHasMore, !isLoadingMoreEvents else { return }
    isLoadingMoreEvents = true
    defer { isLoadingMoreEvents = false }
    do {
      let page = try await eventRepository.searchEvents(
        query: query,
        filter: eventSearchFilter,
        offset: nextEventSearchOffset,
        viewerID: viewerID
      )
      guard !Task.isCancelled else { return }
      let existingIDs = Set(results.map(\.id))
      results.append(contentsOf: page.events.filter { !existingIDs.contains($0.id) })
      nextEventSearchOffset = page.offset + EventSearchPage.limit
      eventSearchHasMore = page.hasMore
    } catch {
      guard !Task.isCancelled else { return }
      eventSearchHasMore = false
    }
  }

  @MainActor
  private func searchPeople(refresh: Bool = false) async {
    peopleModel.query = query
    if refresh {
      await peopleModel.refreshSearch()
    } else {
      await peopleModel.search()
    }
  }
}

private struct EventSearchFilterMenu: View {
  let isActive: Bool
  let onSelectDate: () -> Void

  var body: some View {
    TunedInGlassPopover {
      Button(action: onSelectDate) {
        HStack(spacing: 10) {
          Label("Date", systemImage: "calendar")
          Spacer()
          if isActive {
            Image(systemName: "checkmark")
              .font(.subheadline.weight(.bold))
          }
        }
          .font(.body.weight(.semibold))
          .foregroundStyle(isActive ? TunedInDesign.accent : TunedInDesign.primaryText)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.horizontal, 18)
          .padding(.vertical, 16)
          .contentShape(.interaction, RoundedRectangle(cornerRadius: TunedInDesign.cornerRadius))
          .background(
            isActive ? TunedInDesign.accent.opacity(0.12) : .clear,
            in: RoundedRectangle(cornerRadius: TunedInDesign.cornerRadius, style: .continuous)
          )
      }
      .buttonStyle(.plain)
      .accessibilityHint("Filters concerts by date")
    }
    .frame(width: 156)
  }
}

private struct EventSearchDateFilterSheet: View {
  let filter: EventSearchFilter
  let onApply: (EventSearchFilter) -> Void
  let onClear: () -> Void

  @Environment(\.dismiss) private var dismiss
  @State private var fromDate: Date?
  @State private var toDate: Date?

  init(
    filter: EventSearchFilter,
    onApply: @escaping (EventSearchFilter) -> Void,
    onClear: @escaping () -> Void
  ) {
    self.filter = filter
    self.onApply = onApply
    self.onClear = onClear
    _fromDate = State(initialValue: filter.beginDate)
    _toDate = State(initialValue: filter.endDate)
  }

  var body: some View {
    NavigationStack {
      ZStack {
        TunedInDesign.pageBackground.ignoresSafeArea()

        ScrollView {
          VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
              Text("Date")
                .font(.title2.weight(.bold))
                .foregroundStyle(TunedInDesign.primaryText)
              Text("Use either bound, or both for a date range.")
                .font(.subheadline)
                .foregroundStyle(TunedInDesign.mutedText)
            }

            TunedInGlassSection {
              VStack(spacing: 0) {
                optionalDatePicker("From", selection: $fromDate)
                  .onChange(of: fromDate) { _, fromDate in
                    guard let fromDate, let toDate, toDate < fromDate else { return }
                    self.toDate = fromDate
                  }

                Divider()
                  .overlay(TunedInDesign.cardBorder)
                  .padding(.vertical, 10)

                optionalDatePicker("To", selection: $toDate)
                  .onChange(of: toDate) { _, toDate in
                    guard let toDate, let fromDate, fromDate > toDate else { return }
                    self.fromDate = toDate
                  }
              }
            }
          }
          .padding(.horizontal, 20)
          .padding(.top, 24)
          .padding(.bottom, TunedInDesign.scrollContentBottomInset + TunedInDesign.controlSize)
        }
      }
      .toolbar(.hidden, for: .navigationBar)
      .safeAreaInset(edge: .bottom, spacing: 0) {
        TunedInPersistentControlRegion {
          bottomControls
            .padding(.horizontal, TunedInDesign.bottomControlHorizontalInset)
            .padding(.top, 8)
            .padding(.bottom, TunedInDesign.bottomControlInset)
        }
      }
    }
    .tunedInEdgeSwipeBack { dismiss() }
  }

  private var bottomControls: some View {
    TunedInGlassTraversalLayout {
      TunedInGlassIconButton(
        systemImage: "chevron.backward",
        accessibilityLabel: "Back to concert search",
        remainsVisibleWithKeyboard: true
      ) {
        dismiss()
      }
    } center: {
      TunedInGlassBottomBar {
        Button {
          onClear()
          dismiss()
        } label: {
          Text("Clear")
            .font(.subheadline.weight(.bold))
            .foregroundStyle(TunedInDesign.primaryText)
            .frame(minWidth: 112, minHeight: 48)
            .padding(.horizontal, 14)
            .contentShape(.interaction, Capsule())
        }
        .buttonStyle(.plain)
      }
    } trailing: {
      TunedInGlassIconButton(
        systemImage: "checkmark",
        accessibilityLabel: "Apply date filter",
        style: .accent,
        remainsVisibleWithKeyboard: true
      ) {
        onApply(EventSearchFilter(beginDate: fromDate, endDate: toDate))
        dismiss()
      }
    }
  }

  private func optionalDatePicker(
    _ title: String,
    selection: Binding<Date?>
  ) -> some View {
    HStack {
      DatePicker(title, selection: Binding(
        get: { selection.wrappedValue ?? Calendar.current.startOfDay(for: .now) },
        set: { selection.wrappedValue = Calendar.current.startOfDay(for: $0) }
      ), displayedComponents: .date)
      .tint(TunedInDesign.accent)

      if selection.wrappedValue != nil {
        Button("Clear \(title)", systemImage: "xmark.circle.fill") {
          selection.wrappedValue = nil
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .accessibilityLabel("Clear \(title.lowercased()) date")
      }
    }
  }
}

// swiftlint:disable:next type_body_length
struct CommunityEventCreationView: View {
  let creatorID: UUID
  let eventRepository: any EventRepository
  let musicCatalogRepository: any MusicCatalogRepository
  let onCreated: (CommunityEventSummary) -> Void
  let onDismiss: () -> Void

  @State private var artist: CatalogArtist?
  @State private var place: CatalogPlace?
  @State private var tour: CatalogTour?
  @State private var eventDate = Self.defaultEventDate
  @State private var timeZoneIdentifier = TimeZone.current.identifier
  @State private var listing = CommunityEventListing.listed
  @State private var pickerKind: CatalogEntityKind?
  @State private var isPresentingTimeZonePicker = false
  @State private var isSaving = false
  @State private var selectedCoverPhoto: PhotosPickerItem?
  @State private var coverPhotoData: Data?
  @State private var isProcessingCover = false
  @State private var duplicateCandidates: [CommunityEventSummary] = []
  @State private var isCheckingDuplicates = false
  @State private var errorMessage: String?

  var body: some View {
    ZStack {
      TunedInDesign.pageBackground.ignoresSafeArea()

      ScrollView {
        VStack(alignment: .leading, spacing: 18) {
          EventScreenHeader(
            eyebrow: "Community made",
            title: "Add a concert",
            subtitle: "Use shared catalog entries so everyone lands on the same artist and venue."
          )

          TunedInFormCard {
            catalogButton(
              title: "Artist",
              value: artist?.displayName,
              systemImage: "music.mic",
              kind: .artist
            )
            Divider()
            catalogButton(
              title: "Venue",
              value: place.map { [$0.displayName, $0.areaName].compactMap(\.self).joined(separator: " · ") },
              systemImage: "mappin.and.ellipse",
              kind: .place
            )
            Divider()
            catalogButton(
              title: "Tour (optional)",
              value: tour?.displayName,
              systemImage: "point.topleft.down.to.point.bottomright.curvepath",
              kind: .tour
            )
          }

          coverPhotoPicker

          TunedInFormCard {
            DatePicker(
              "Concert date",
              selection: $eventDate,
              displayedComponents: [.date, .hourAndMinute]
            )
            .foregroundStyle(TunedInDesign.primaryText)
            .environment(\.timeZone, selectedTimeZone)

            Button { isPresentingTimeZonePicker = true } label: {
              HStack(spacing: 12) {
                Image(systemName: "globe.americas")
                  .foregroundStyle(TunedInDesign.accent)
                  .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                  Text("Venue time zone")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(TunedInDesign.mutedText)
                  Text(EventTimeZoneText.name(for: timeZoneIdentifier))
                    .font(.body.weight(.semibold))
                    .foregroundStyle(TunedInDesign.primaryText)
                }
                Spacer()
                Image(systemName: "chevron.right")
                  .font(.caption.weight(.bold))
                  .foregroundStyle(TunedInDesign.mutedText)
              }
            }
            .buttonStyle(.plain)

            Picker("Who can find it", selection: $listing) {
              Text("Listed").tag(CommunityEventListing.listed)
              Text("Unlisted").tag(CommunityEventListing.unlisted)
            }
            .pickerStyle(.segmented)

            Text(listing == .listed
              ? "Anyone can discover this concert."
              : "Only people with access or an invitation can open this concert.")
              .font(.caption)
              .foregroundStyle(TunedInDesign.mutedText)
          }

          if isCheckingDuplicates {
            Label("Checking nearby concerts…", systemImage: "magnifyingglass")
              .font(.caption.weight(.semibold))
              .foregroundStyle(TunedInDesign.mutedText)
          } else if !duplicateCandidates.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
              Text("Possible matches")
                .font(.headline)
                .foregroundStyle(TunedInDesign.primaryText)
              Text("Open one if it is the same concert. You can still create a separate concert when it is not.")
                .font(.caption)
                .foregroundStyle(TunedInDesign.mutedText)
              ForEach(duplicateCandidates) { candidate in
                Button { onCreated(candidate) } label: {
                  CommunityEventRow(
                    event: candidate,
                    showsSource: true,
                    eventRepository: eventRepository
                  )
                }
                .buttonStyle(TunedInPosterButtonStyle())
              }
            }
          }

          if let errorMessage {
            Label(errorMessage, systemImage: "exclamationmark.triangle")
              .font(.subheadline)
              .foregroundStyle(TunedInDesign.accent)
          }

          Button { Task { await create() } } label: {
            HStack {
              if isSaving { ProgressView().tint(TunedInDesign.actionForeground) }
              Text(
                isSaving
                  ? "Creating…"
                  : (duplicateCandidates.isEmpty ? "Create concert" : "Create separate concert")
              )
            }
            .font(.headline)
            .foregroundStyle(TunedInDesign.actionForeground)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(canSubmit ? TunedInDesign.accent : TunedInDesign.raisedSurface, in: Capsule())
          }
          .buttonStyle(TunedInPosterButtonStyle())
          .disabled(!canSubmit || isSaving)
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 24)
      }
    }
    .safeAreaInset(edge: .bottom, spacing: 0) {
      TunedInPersistentControlRegion {
        TunedInSubscreenBackBar(title: "Add concert", action: onDismiss)
          .padding(.horizontal, TunedInDesign.bottomControlHorizontalInset)
          .padding(.top, 8)
          .padding(.bottom, TunedInDesign.bottomControlInset)
      }
    }
    .tunedInEdgeSwipeBack(isEnabled: !isSaving, action: onDismiss)
    .fullScreenCover(item: $pickerKind) { kind in
      CatalogPickerView(
        repository: musicCatalogRepository,
        configuration: CatalogPickerConfiguration(
          kind: kind,
          title: pickerTitle(kind),
          artistContext: artist.map { [$0] } ?? [],
          currentSelectionName: currentSelectionName(kind)
        )
      ) { entity in
        apply(entity)
        pickerKind = nil
      }
    }
    .fullScreenCover(isPresented: $isPresentingTimeZonePicker) {
      EventTimeZonePickerView(
        selectedIdentifier: timeZoneIdentifier,
        referenceDate: eventDate,
        onSelect: selectTimeZone,
        onDismiss: { isPresentingTimeZonePicker = false }
      )
    }
    .task(id: duplicateLookupKey) {
      guard creationInput != nil else {
        duplicateCandidates = []
        return
      }
      try? await Task.sleep(for: .milliseconds(300))
      guard !Task.isCancelled else { return }
      await checkDuplicates()
    }
    .onChange(of: selectedCoverPhoto) { _, item in
      guard let item else { return }
      Task { await processCoverPhoto(item) }
    }
  }

  private var canSubmit: Bool { artist != nil && place != nil && !isProcessingCover }

  private var coverPhotoPicker: some View {
    CommunityEventCoverPicker(
      selection: $selectedCoverPhoto,
      photoData: coverPhotoData,
      isProcessing: isProcessingCover,
      isDisabled: isProcessingCover || isSaving
    )
  }

  private var selectedTimeZone: TimeZone {
    TimeZone(identifier: timeZoneIdentifier) ?? .current
  }

  private var creationInput: CommunityEventCreationInput? {
    guard let artist, let place else { return nil }
    return CommunityEventCreationInput(
      artists: [artist],
      place: place,
      tour: tour,
      eventDate: eventDate,
      startsAt: eventDate,
      timeZoneIdentifier: timeZoneIdentifier,
      listing: listing
    )
  }

  private var duplicateLookupKey: String {
    guard let input = creationInput else { return "empty" }
    return [
      input.artists.first?.id.uuidString ?? "",
      input.place.id.uuidString,
      input.eventDate.timeIntervalSince1970.formatted(),
      input.startsAt.timeIntervalSince1970.formatted(),
      input.timeZoneIdentifier,
      input.listing.rawValue
    ].joined(separator: "|")
  }

  private static var defaultEventDate: Date {
    let calendar = Calendar.current
    let shifted = calendar.date(byAdding: .day, value: 14, to: .now) ?? .now
    return calendar.date(bySettingHour: 19, minute: 30, second: 0, of: shifted) ?? shifted
  }

  private func catalogButton(
    title: String,
    value: String?,
    systemImage: String,
    kind: CatalogEntityKind
  ) -> some View {
    Button { pickerKind = kind } label: {
      HStack(spacing: 12) {
        Image(systemName: systemImage)
          .foregroundStyle(TunedInDesign.accent)
          .frame(width: 24)
        VStack(alignment: .leading, spacing: 2) {
          Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(TunedInDesign.mutedText)
          Text(value ?? ("Choose " + title.lowercased()))
            .font(.body.weight(.semibold))
            .foregroundStyle(TunedInDesign.primaryText)
            .lineLimit(2)
        }
        Spacer()
        Image(systemName: "chevron.right")
          .font(.caption.weight(.bold))
          .foregroundStyle(TunedInDesign.mutedText)
      }
    }
    .buttonStyle(.plain)
  }

  @MainActor
  private func create() async {
    guard let input = creationInput else { return }
    isSaving = true
    defer { isSaving = false }
    do {
      var detail = try await eventRepository.createEvent(input, creatorID: creatorID)
      if let coverPhotoData {
        detail = try await eventRepository.setEventCover(
          coverPhotoData,
          eventID: detail.id,
          creatorID: creatorID
        )
      }
      errorMessage = nil
      onCreated(detail.summary)
    } catch let CommunityEventError.duplicateEvent(eventID) {
      do {
        var detail = try await eventRepository.eventDetail(id: eventID, viewerID: creatorID)
        if let coverPhotoData {
          detail = try await eventRepository.setEventCover(
            coverPhotoData,
            eventID: detail.id,
            creatorID: creatorID
          )
        }
        onCreated(detail.summary)
      } catch {
        errorMessage = error.localizedDescription
      }
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  @MainActor
  private func processCoverPhoto(_ item: PhotosPickerItem) async {
    isProcessingCover = true
    defer { isProcessingCover = false }
    do {
      guard let data = try await item.loadTransferable(type: Data.self) else { return }
      coverPhotoData = try await AvatarImageProcessor.processEventCover(data)
      errorMessage = nil
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  @MainActor
  private func checkDuplicates() async {
    guard let input = creationInput else { return }
    isCheckingDuplicates = true
    defer { isCheckingDuplicates = false }
    do {
      duplicateCandidates = try await eventRepository.duplicateCandidates(
        for: input,
        viewerID: creatorID
      )
    } catch {
      duplicateCandidates = []
    }
  }

  private func apply(_ entity: CatalogEntity) {
    switch entity {
    case let .artist(value): artist = value
    case let .place(value): place = value
    case let .tour(value): tour = value
    case .area, .song: break
    }
  }

  private func selectTimeZone(_ identifier: String) {
    guard let newTimeZone = TimeZone(identifier: identifier) else { return }
    eventDate = CommunityEventDateCoding.preservingWallClockTime(
      eventDate,
      from: selectedTimeZone,
      to: newTimeZone
    )
    timeZoneIdentifier = identifier
    isPresentingTimeZonePicker = false
  }

  private func pickerTitle(_ kind: CatalogEntityKind) -> String {
    switch kind {
    case .artist: "Who is playing?"
    case .place: "Where is the concert?"
    case .tour: "Which tour?"
    case .area, .song: "Choose " + kind.singularTitle.lowercased()
    }
  }

  private func currentSelectionName(_ kind: CatalogEntityKind) -> String? {
    switch kind {
    case .artist: artist?.displayName
    case .place: place?.displayName
    case .tour: tour?.displayName
    case .area, .song: nil
    }
  }
}

private struct CommunityEventCoverPicker: View {
  @Binding var selection: PhotosPickerItem?
  let photoData: Data?
  let isProcessing: Bool
  let isDisabled: Bool

  var body: some View {
    TunedInFormCard {
      PhotosPicker(selection: $selection, matching: .images) {
        VStack(alignment: .leading, spacing: 12) {
          CommunityEventCoverPreview(photoData: photoData)
          HStack(spacing: 12) {
            Image(systemName: photoData == nil ? "camera.fill" : "checkmark.circle.fill")
              .foregroundStyle(TunedInDesign.accent)
              .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
              Text(photoData == nil ? "Add a cover photo" : "Cover photo ready")
                .font(.body.weight(.semibold))
                .foregroundStyle(TunedInDesign.primaryText)
              Text(isProcessing ? "Preparing photo…" : "Optional · tap to choose or change")
                .font(.caption)
                .foregroundStyle(TunedInDesign.mutedText)
            }
            Spacer()
          }
        }
      }
      .buttonStyle(.plain)
      .disabled(isDisabled)
    }
  }

}

private struct CommunityEventCoverPreview: View {
  let photoData: Data?

  var body: some View {
    Group {
      if let photoData, let image = UIImage(data: photoData) {
        Image(uiImage: image).resizable().scaledToFill()
      } else {
        ZStack {
          LinearGradient(
            colors: [TunedInDesign.accent.opacity(0.85), Color.purple.opacity(0.72)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
          )
          Image(systemName: "photo.badge.plus")
            .font(.system(size: 30, weight: .semibold))
            .foregroundStyle(.white)
        }
      }
    }
    .frame(maxWidth: .infinity)
    .frame(height: 150)
    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
  }
}
