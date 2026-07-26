import PhotosUI
import SwiftUI

struct EventDiscoveryView: View {
  private enum SearchScope: String, CaseIterable, Hashable {
    case concerts = "Concerts"
    case people = "People"
  }

  private struct SearchRequest: Hashable {
    let scope: SearchScope
    let query: String
  }

  let viewerID: UUID
  let eventRepository: any EventRepository
  let musicCatalogRepository: any MusicCatalogRepository
  let onOpenEvent: (CommunityEventSummary) -> Void
  let onOpenProfile: (SocialProfile) -> Void
  let onDismiss: () -> Void

  @State private var query = ""
  @State private var selectedScope = SearchScope.concerts
  @State private var results: [CommunityEventSummary] = []
  @State private var isLoadingEvents = true
  @State private var eventErrorMessage: String?
  @State private var isPresentingCreation = false
  @State private var peopleModel: PeopleHubModel

  init(
    viewerID: UUID,
    eventRepository: any EventRepository,
    musicCatalogRepository: any MusicCatalogRepository,
    socialRepository: any SocialRepository,
    currentUsername: String,
    onOpenEvent: @escaping (CommunityEventSummary) -> Void,
    onOpenProfile: @escaping (SocialProfile) -> Void,
    onDismiss: @escaping () -> Void
  ) {
    self.viewerID = viewerID
    self.eventRepository = eventRepository
    self.musicCatalogRepository = musicCatalogRepository
    self.onOpenEvent = onOpenEvent
    self.onOpenProfile = onOpenProfile
    self.onDismiss = onDismiss
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

      ScrollView {
        VStack(alignment: .leading, spacing: 18) {
          Text("Search")
            .font(.system(size: 34, weight: .bold))
            .foregroundStyle(TunedInDesign.primaryText)

          TunedInGlassSearchField(
            text: $query,
            prompt: "Artist, venue, city, or @username"
          )

          Picker("Search category", selection: $selectedScope) {
            ForEach(SearchScope.allCases, id: \.self) { scope in
              Text(scope.rawValue).tag(scope)
            }
          }
          .pickerStyle(.segmented)

          searchResults

          if selectedScope == .concerts {
            Button { isPresentingCreation = true } label: {
              Label("Add a concert", systemImage: "plus.circle.fill")
                .font(.headline)
                .foregroundStyle(TunedInDesign.actionForeground)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(TunedInDesign.accent, in: Capsule())
            }
            .buttonStyle(TunedInPosterButtonStyle())
            .padding(.top, 4)
          }
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 24)
      }
      .refreshable { await refreshSelectedScope() }
    }
    .toolbar(.hidden, for: .navigationBar)
    .safeAreaInset(edge: .bottom, spacing: 0) {
      TunedInPersistentControlRegion {
        TunedInSubscreenBackBar(title: "Search", action: onDismiss)
          .padding(.horizontal, TunedInDesign.bottomControlHorizontalInset)
          .padding(.top, 8)
          .padding(.bottom, TunedInDesign.bottomControlInset)
      }
    }
    .task(id: searchRequest) {
      if !query.isEmpty {
        try? await Task.sleep(for: .milliseconds(250))
        guard !Task.isCancelled else { return }
      }
      await searchSelectedScope()
    }
    .fullScreenCover(isPresented: $isPresentingCreation) {
      CommunityEventCreationView(
        creatorID: viewerID,
        eventRepository: eventRepository,
        musicCatalogRepository: musicCatalogRepository,
        onCreated: { event in
          isPresentingCreation = false
          onOpenEvent(event)
        },
        onDismiss: { isPresentingCreation = false }
      )
    }
  }

  @ViewBuilder
  private var searchResults: some View {
    switch selectedScope {
    case .concerts:
      concertResults
    case .people:
      peopleResults
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
        title: query.isEmpty ? "No concerts yet" : "No matching concert",
        message: "If the concert isn’t here, add it for the community using the music catalog."
      )
    } else {
      LazyVStack(spacing: 12) {
        eventSection(title: "Upcoming", events: upcomingResults)
        eventSection(title: "Past", events: pastResults)
      }
    }
  }

  @ViewBuilder
  private var peopleResults: some View {
    let normalizedQuery = ProfileInput.normalizedSearchQuery(query)
    if normalizedQuery.isEmpty {
      EventEmptyView(
        systemImage: "person.2",
        title: "Find people",
        message: "Search by @username to find friends and public profiles."
      )
    } else if peopleModel.isSearching {
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
          Button { onOpenProfile(profile) } label: {
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
    SearchRequest(scope: selectedScope, query: query)
  }

  private var upcomingResults: [CommunityEventSummary] {
    results
      .filter { $0.phase() != .memories }
      .sorted { $0.eventDate < $1.eventDate }
  }

  private var pastResults: [CommunityEventSummary] {
    results
      .filter { $0.phase() == .memories }
      .sorted { $0.eventDate > $1.eventDate }
  }

  @ViewBuilder
  private func eventSection(title: String, events: [CommunityEventSummary]) -> some View {
    if !events.isEmpty {
      Text(title)
        .font(.headline)
        .foregroundStyle(TunedInDesign.primaryText)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, title == "Past" ? 8 : 0)
      ForEach(events) { event in
        Button { onOpenEvent(event) } label: {
          CommunityEventRow(event: event, showsSource: true, eventRepository: eventRepository)
        }
        .buttonStyle(TunedInPosterButtonStyle())
      }
    }
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

  @MainActor
  private func refreshSelectedScope() async {
    switch selectedScope {
    case .concerts:
      await searchEvents()
    case .people:
      await searchPeople(refresh: true)
    }
  }

  @MainActor
  private func searchEvents() async {
    isLoadingEvents = results.isEmpty
    defer { isLoadingEvents = false }
    do {
      results = try await eventRepository.searchEvents(query: query, viewerID: viewerID)
      eventErrorMessage = nil
    } catch {
      eventErrorMessage = error.localizedDescription
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
