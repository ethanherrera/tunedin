import SwiftUI

// Phase 0 intentionally keeps the fixture-backed journey together while its
// shared components settle; split by feature before enabling the live repository.
// swiftlint:disable file_length

struct CommunityActivityFeedView: View {
  let viewerID: UUID
  let repository: any EventRepository
  let onOpenEvent: (CommunityEventSummary) -> Void

  @State private var activities: [EventActivity] = []
  @State private var isLoading = true
  @State private var errorMessage: String?

  var body: some View {
    ZStack {
      TunedInDesign.pageBackground.ignoresSafeArea()

      ScrollView {
        VStack(alignment: .leading, spacing: 22) {
          EventScreenHeader(
            eyebrow: "Your circle",
            title: "Feed",
            subtitle: "Plans before the show. Memories after it."
          )

          if isLoading {
            ForEach(0 ..< 3, id: \.self) { _ in
              TunedInSkeletonBlock(cornerRadius: TunedInDesign.cornerRadius)
                .frame(height: 150)
            }
          } else if let errorMessage {
            EventFailureView(message: errorMessage) { Task { await load() } }
          } else if activities.isEmpty {
            EventEmptyView(
              systemImage: "person.2.wave.2",
              title: "Your circle is quiet",
              message: "When friends make plans or share concert memories, they’ll appear here."
            )
          } else {
            LazyVStack(spacing: 14) {
              ForEach(activities) { activity in
                Button { onOpenEvent(activity.event) } label: {
                  CommunityActivityCard(activity: activity)
                }
                .buttonStyle(TunedInPosterButtonStyle())
              }
            }
          }
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, TunedInDesign.scrollContentBottomInset)
      }
      .refreshable { await load() }
    }
    .toolbar(.hidden, for: .navigationBar)
    .task { await load() }
  }

  @MainActor
  private func load() async {
    isLoading = activities.isEmpty
    defer { isLoading = false }
    do {
      activities = try await repository.activityFeed(viewerID: viewerID)
      errorMessage = nil
    } catch {
      errorMessage = error.localizedDescription
    }
  }
}

struct CommunityPlansView: View {
  let viewerID: UUID
  let repository: any EventRepository
  let onOpenEvent: (CommunityEventSummary) -> Void

  @State private var events: [CommunityEventSummary] = []
  @State private var isLoading = true
  @State private var errorMessage: String?

  var body: some View {
    ZStack {
      TunedInDesign.pageBackground.ignoresSafeArea()

      ScrollView {
        VStack(alignment: .leading, spacing: 22) {
          EventScreenHeader(
            eyebrow: "Your calendar",
            title: "Plans",
            subtitle: "Every show you’re going to—and the friends joining you."
          )

          if isLoading {
            ForEach(0 ..< 3, id: \.self) { _ in
              TunedInSkeletonBlock(cornerRadius: TunedInDesign.cornerRadius)
                .frame(height: 126)
            }
          } else if let errorMessage {
            EventFailureView(message: errorMessage) { Task { await load() } }
          } else if events.isEmpty {
            EventEmptyView(
              systemImage: "calendar.badge.plus",
              title: "No plans yet",
              message: "Find a concert and say you’re going. It will land here automatically."
            )
          } else {
            eventSection(title: "Coming up", events: upcoming)
            eventSection(title: "Past shows", events: past)
          }
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, TunedInDesign.scrollContentBottomInset)
      }
      .refreshable { await load() }
    }
    .toolbar(.hidden, for: .navigationBar)
    .task { await load() }
  }

  @ViewBuilder
  private func eventSection(title: String, events: [CommunityEventSummary]) -> some View {
    if !events.isEmpty {
      VStack(alignment: .leading, spacing: 12) {
        Text(title)
          .font(.headline)
          .foregroundStyle(TunedInDesign.primaryText)

        ForEach(events) { event in
          Button { onOpenEvent(event) } label: {
            CommunityEventRow(event: event, showsSource: false)
          }
          .buttonStyle(TunedInPosterButtonStyle())
        }
      }
    }
  }

  private var upcoming: [CommunityEventSummary] {
    events.filter { $0.phase() != .memories }
  }

  private var past: [CommunityEventSummary] {
    events.filter { $0.phase() == .memories }
  }

  @MainActor
  private func load() async {
    isLoading = events.isEmpty
    defer { isLoading = false }
    do {
      events = try await repository.plans(viewerID: viewerID)
      errorMessage = nil
    } catch {
      errorMessage = error.localizedDescription
    }
  }
}

struct EventDiscoveryView: View {
  let viewerID: UUID
  let eventRepository: any EventRepository
  let musicCatalogRepository: any MusicCatalogRepository
  let onOpenEvent: (CommunityEventSummary) -> Void
  let onSearchPeople: () -> Void
  let onDismiss: () -> Void

  @State private var query = ""
  @State private var results: [CommunityEventSummary] = []
  @State private var isLoading = true
  @State private var errorMessage: String?
  @State private var isPresentingCreation = false

  var body: some View {
    ZStack {
      TunedInDesign.pageBackground.ignoresSafeArea()

      ScrollView {
        VStack(alignment: .leading, spacing: 18) {
          EventScreenHeader(
            eyebrow: "Find your next show",
            title: "Concerts",
            subtitle: "Search shared events first. Add one only when it isn’t here."
          )

          TunedInGlassSearchField(text: $query, prompt: "Artist, venue, or city")

          Button(action: onSearchPeople) {
            Label("Looking for a person? Search people", systemImage: "person.crop.circle.badge.magnifyingglass")
              .font(.subheadline.weight(.semibold))
              .foregroundStyle(TunedInDesign.primaryText)
              .frame(maxWidth: .infinity, alignment: .leading)
              .padding(14)
              .background(TunedInDesign.raisedSurface, in: RoundedRectangle(cornerRadius: 16))
          }
          .buttonStyle(.plain)

          if isLoading {
            ForEach(0 ..< 4, id: \.self) { _ in
              TunedInSkeletonBlock(cornerRadius: TunedInDesign.cornerRadius)
                .frame(height: 126)
            }
          } else if let errorMessage {
            EventFailureView(message: errorMessage) { Task { await search() } }
          } else if results.isEmpty {
            EventEmptyView(
              systemImage: "music.note.list",
              title: query.isEmpty ? "No shared events yet" : "No matching concert",
              message: "If the concert isn’t here, add it for the community using the music catalog."
            )
          } else {
            LazyVStack(spacing: 12) {
              ForEach(results) { event in
                Button { onOpenEvent(event) } label: {
                  CommunityEventRow(event: event, showsSource: true)
                }
                .buttonStyle(TunedInPosterButtonStyle())
              }
            }
          }

          Button { isPresentingCreation = true } label: {
            Label("Add a community event", systemImage: "plus.circle.fill")
              .font(.headline)
              .foregroundStyle(TunedInDesign.actionForeground)
              .frame(maxWidth: .infinity)
              .padding(.vertical, 15)
              .background(TunedInDesign.accent, in: Capsule())
          }
          .buttonStyle(TunedInPosterButtonStyle())
          .padding(.top, 4)
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 24)
      }
    }
    .toolbar(.hidden, for: .navigationBar)
    .safeAreaInset(edge: .bottom, spacing: 0) {
      TunedInPersistentControlRegion {
        TunedInSubscreenBackBar(title: "Find concerts", action: onDismiss)
          .padding(.horizontal, TunedInDesign.bottomControlHorizontalInset)
          .padding(.top, 8)
          .padding(.bottom, TunedInDesign.bottomControlInset)
      }
    }
    .task(id: query) {
      if !query.isEmpty {
        try? await Task.sleep(for: .milliseconds(250))
        guard !Task.isCancelled else { return }
      }
      await search()
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

  @MainActor
  private func search() async {
    isLoading = results.isEmpty
    defer { isLoading = false }
    do {
      results = try await eventRepository.searchEvents(query: query, viewerID: viewerID)
      errorMessage = nil
    } catch {
      errorMessage = error.localizedDescription
    }
  }
}

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
  @State private var includesTime = true
  @State private var listing = CommunityEventListing.listed
  @State private var pickerKind: CatalogEntityKind?
  @State private var isSaving = false
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

          TunedInFormCard {
            DatePicker(
              "Concert date",
              selection: $eventDate,
              displayedComponents: includesTime ? [.date, .hourAndMinute] : [.date]
            )
            .foregroundStyle(TunedInDesign.primaryText)

            Toggle("Start time is known", isOn: $includesTime)
              .tint(TunedInDesign.accent)

            Picker("Who can find it", selection: $listing) {
              Text("Listed").tag(CommunityEventListing.listed)
              Text("Unlisted").tag(CommunityEventListing.unlisted)
            }
            .pickerStyle(.segmented)

            Text(listing == .listed
              ? "Anyone can discover this event."
              : "Only people with access or an invitation can open it.")
              .font(.caption)
              .foregroundStyle(TunedInDesign.mutedText)
          }

          if let errorMessage {
            Label(errorMessage, systemImage: "exclamationmark.triangle")
              .font(.subheadline)
              .foregroundStyle(TunedInDesign.accent)
          }

          Button { Task { await create() } } label: {
            HStack {
              if isSaving { ProgressView().tint(TunedInDesign.actionForeground) }
              Text(isSaving ? "Checking for matches…" : "Create shared event")
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
  }

  private var canSubmit: Bool { artist != nil && place != nil }

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
    guard let artist, let place else { return }
    isSaving = true
    defer { isSaving = false }
    let input = CommunityEventCreationInput(
      artists: [artist],
      place: place,
      tour: tour,
      eventDate: eventDate,
      startsAt: includesTime ? eventDate : nil,
      timeZoneIdentifier: TimeZone.current.identifier,
      listing: listing
    )
    do {
      let detail = try await eventRepository.createEvent(input, creatorID: creatorID)
      errorMessage = nil
      onCreated(detail.summary)
    } catch let CommunityEventError.duplicateEvent(eventID) {
      do {
        let detail = try await eventRepository.eventDetail(id: eventID, viewerID: creatorID)
        onCreated(detail.summary)
      } catch {
        errorMessage = error.localizedDescription
      }
    } catch {
      errorMessage = error.localizedDescription
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

struct CommunityEventDetailView: View {
  private enum Page: String, CaseIterable {
    case event = "Event"
    case people = "People"
    case memories = "Memories"

    var icon: String {
      switch self {
      case .event: "music.note"
      case .people: "person.2"
      case .memories: "photo.on.rectangle.angled"
      }
    }
  }

  let eventID: UUID
  let viewerID: UUID
  let repository: any EventRepository
  let onDismiss: () -> Void

  @State private var detail: CommunityEventDetail?
  @State private var selectedPage = Page.event
  @State private var isLoading = true
  @State private var errorMessage: String?
  @State private var isPresentingInvites = false
  @Namespace private var selectionNamespace

  var body: some View {
    ZStack {
      TunedInDesign.pageBackground.ignoresSafeArea()

      if isLoading, detail == nil {
        VStack(spacing: 14) {
          TunedInSkeletonBlock(cornerRadius: 24).frame(height: 220)
          TunedInSkeletonBlock(cornerRadius: 24).frame(height: 180)
          Spacer()
        }
        .padding(20)
      } else if let errorMessage, detail == nil {
        EventFailureView(message: errorMessage) { Task { await load() } }
          .padding(20)
      } else if let detail {
        ScrollView {
          VStack(alignment: .leading, spacing: 18) {
            CommunityEventHero(
              detail: detail,
              onSetAttendance: { status, audience in
                Task { await setAttendance(status, audience: audience) }
              }
            )

            switch selectedPage {
            case .event:
              EventOverviewPage(
                detail: detail,
                viewerID: viewerID,
                repository: repository,
                onPostAdded: { Task { await load() } }
              )
            case .people:
              EventPeoplePage(detail: detail)
            case .memories:
              EventMemoriesPage(
                detail: detail,
                viewerID: viewerID,
                repository: repository,
                onSaved: { Task { await load() } }
              )
            }
          }
          .padding(.horizontal, 20)
          .padding(.top, 18)
          .padding(.bottom, 24)
        }
        .refreshable { await load() }
      }
    }
    .toolbar(.hidden, for: .navigationBar)
    .safeAreaInset(edge: .bottom, spacing: 0) {
      TunedInPersistentControlRegion {
        detailBottomBar
          .padding(.horizontal, TunedInDesign.bottomControlHorizontalInset)
          .padding(.top, 6)
          .padding(.bottom, TunedInDesign.bottomControlInset)
      }
    }
    .task { await load() }
    .sheet(isPresented: $isPresentingInvites) {
      EventInviteView(
        eventID: eventID,
        viewerID: viewerID,
        repository: repository
      )
      .presentationDetents([.medium, .large])
      .presentationDragIndicator(.visible)
    }
  }

  private var detailBottomBar: some View {
    TunedInGlassTraversalLayout {
      TunedInGlassIconButton(
        systemImage: "chevron.backward",
        accessibilityLabel: "Back to previous screen",
        action: onDismiss
      )
    } center: {
      TunedInGlassBottomBar {
        HStack(spacing: 2) {
          ForEach(Page.allCases, id: \.self) { page in
            Button { selectedPage = page } label: {
              VStack(spacing: 2) {
                Image(systemName: page.icon).font(.caption.weight(.bold))
                Text(page.rawValue).font(.caption2.weight(.bold))
              }
              .foregroundStyle(
                selectedPage == page ? TunedInDesign.selectedControlForeground : TunedInDesign.primaryText
              )
              .frame(maxWidth: .infinity)
              .frame(height: 48)
              .background {
                if selectedPage == page {
                  TunedInSelectionLens()
                    .matchedGeometryEffect(id: "event-detail-page", in: selectionNamespace)
                }
              }
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(selectedPage == page ? .isSelected : [])
          }
        }
      }
      .frame(maxWidth: 252)
    } trailing: {
      TunedInGlassIconButton(
        systemImage: "paperplane",
        accessibilityLabel: "Invite friends"
      ) {
        isPresentingInvites = true
      }
    }
  }

  @MainActor
  private func load() async {
    isLoading = detail == nil
    defer { isLoading = false }
    do {
      detail = try await repository.eventDetail(id: eventID, viewerID: viewerID)
      errorMessage = nil
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  @MainActor
  private func setAttendance(_ status: EventAttendanceStatus?, audience: EventAudience) async {
    do {
      detail = try await repository.setAttendance(
        eventID: eventID,
        viewerID: viewerID,
        status: status,
        audience: audience
      )
      errorMessage = nil
    } catch {
      errorMessage = error.localizedDescription
    }
  }
}

private struct CommunityEventHero: View {
  let detail: CommunityEventDetail
  let onSetAttendance: (EventAttendanceStatus?, EventAudience) -> Void

  @State private var audience = EventAudience.friends

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      HStack(alignment: .top, spacing: 16) {
        EventDateTile(date: detail.summary.eventDate)
        VStack(alignment: .leading, spacing: 6) {
          Text(detail.summary.title)
            .font(.system(.title, design: .rounded, weight: .bold))
            .foregroundStyle(TunedInDesign.primaryText)
          Text("\(detail.summary.venueName) · \(detail.summary.areaName)")
            .font(.subheadline.weight(.medium))
            .foregroundStyle(TunedInDesign.mutedText)
          phaseLabel
        }
      }

      Divider().overlay(TunedInDesign.cardBorder)

      HStack(spacing: 12) {
        Button {
          onSetAttendance(nextAttendance, audience)
        } label: {
          Label(attendanceTitle, systemImage: attendanceIcon)
            .font(.headline)
            .foregroundStyle(TunedInDesign.actionForeground)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background(TunedInDesign.accent, in: Capsule())
        }
        .buttonStyle(TunedInPosterButtonStyle())

        Menu {
          ForEach(EventAudience.allCases, id: \.self) { option in
            Button {
              audience = option
              if let current = detail.summary.currentUserAttendance {
                onSetAttendance(current, option)
              }
            } label: {
              if audience == option {
                Label(option.title, systemImage: "checkmark")
              } else {
                Text(option.title)
              }
            }
          }
        } label: {
          Image(systemName: audienceIcon)
            .font(.body.weight(.bold))
            .foregroundStyle(TunedInDesign.primaryText)
            .frame(width: 48, height: 48)
            .background(TunedInDesign.raisedSurface, in: Circle())
        }
        .accessibilityLabel("Attendance visibility: \(audience.title)")
      }

      if !detail.summary.friendPreviews.isEmpty {
        HStack(spacing: 10) {
          EventAvatarStack(profiles: detail.summary.friendPreviews.map(\.profile))
          Text(friendLine)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(TunedInDesign.primaryText)
        }
      }
    }
    .padding(18)
    .background(
      LinearGradient(
        colors: [TunedInDesign.accentTint, TunedInDesign.cardBackground],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
      ),
      in: RoundedRectangle(cornerRadius: TunedInDesign.largeCornerRadius, style: .continuous)
    )
    .overlay {
      RoundedRectangle(cornerRadius: TunedInDesign.largeCornerRadius, style: .continuous)
        .strokeBorder(TunedInDesign.cardBorder.opacity(0.55))
    }
  }

  private var attendanceTitle: String {
    if detail.summary.currentUserAttendance != nil { return "Added to my plans" }
    return detail.summary.phase() == .memories ? "I went" : "I’m going"
  }

  private var attendanceIcon: String {
    detail.summary.currentUserAttendance == nil ? "plus" : "checkmark"
  }

  private var nextAttendance: EventAttendanceStatus? {
    guard detail.summary.currentUserAttendance == nil else { return nil }
    return detail.summary.phase() == .memories ? .went : .going
  }

  private var audienceIcon: String {
    switch audience {
    case .privateOnly: "lock.fill"
    case .friends: "person.2.fill"
    case .community: "globe.americas.fill"
    }
  }

  @ViewBuilder
  private var phaseLabel: some View {
    switch detail.summary.phase() {
    case .upcoming:
      Label(detail.summary.sourceLabel, systemImage: "person.3.fill")
        .foregroundStyle(TunedInDesign.accent)
    case .postponed:
      Label("Postponed", systemImage: "clock.badge.exclamationmark")
        .foregroundStyle(TunedInDesign.accent)
    case .cancelled:
      Label("Cancelled", systemImage: "xmark.circle.fill")
        .foregroundStyle(TunedInDesign.accent)
    case .memories:
      Label("Memories unlocked", systemImage: "sparkles")
        .foregroundStyle(TunedInDesign.accent)
    }
  }

  private var friendLine: String {
    let names = detail.summary.friendPreviews.prefix(2).map { $0.profile.displayName }
    let total = detail.summary.friendPreviews.count
    if total == 1, let name = names.first {
      return name + " is going"
    }
    let remainder = total - names.count
    return names.joined(separator: " and ")
      + (remainder > 0 ? " + \(remainder) more are going" : " are going")
  }
}

private struct EventOverviewPage: View {
  let detail: CommunityEventDetail
  let viewerID: UUID
  let repository: any EventRepository
  let onPostAdded: () -> Void

  @State private var comment = ""
  @State private var audience = EventAudience.friends
  @State private var isPosting = false
  @State private var errorMessage: String?

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      TunedInFormCard {
        Label("Event details", systemImage: "calendar")
          .font(.headline)
          .foregroundStyle(TunedInDesign.primaryText)
        EventMetadataRow(label: "Date", value: detail.summary.eventDate.formatted(date: .complete, time: .omitted))
        if let startsAt = detail.summary.startsAt {
          EventMetadataRow(label: "Starts", value: startsAt.formatted(date: .omitted, time: .shortened))
        }
        EventMetadataRow(label: "Venue", value: detail.summary.venueName)
        EventMetadataRow(label: "Location", value: detail.summary.areaName)
        EventMetadataRow(label: "Source", value: detail.summary.sourceLabel)
      }

      VStack(alignment: .leading, spacing: 12) {
        Text(detail.summary.phase() == .memories ? "What people remember" : "Before the show")
          .font(.headline)
          .foregroundStyle(TunedInDesign.primaryText)

        if detail.summary.phase() != .memories {
          HStack(spacing: 8) {
            TextField("What are you excited for?", text: $comment, axis: .vertical)
              .lineLimit(1 ... 4)
              .padding(12)
              .background(TunedInDesign.raisedSurface, in: RoundedRectangle(cornerRadius: 14))

            Menu {
              ForEach([EventAudience.friends, .community], id: \.self) { option in
                Button(option.title) { audience = option }
              }
            } label: {
              Image(systemName: audience == .friends ? "person.2.fill" : "globe.americas.fill")
                .foregroundStyle(TunedInDesign.primaryText)
                .frame(width: 42, height: 42)
            }

            Button { Task { await post() } } label: {
              Image(systemName: "arrow.up.circle.fill")
                .font(.title2)
                .foregroundStyle(comment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                  ? TunedInDesign.mutedText : TunedInDesign.accent)
            }
            .disabled(isPosting || comment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
          }
        }

        if let errorMessage {
          Text(errorMessage).font(.caption).foregroundStyle(TunedInDesign.accent)
        }

        if detail.posts.isEmpty {
          Text("No comments yet. Start the conversation with your friends.")
            .font(.subheadline)
            .foregroundStyle(TunedInDesign.mutedText)
            .padding(.vertical, 12)
        } else {
          ForEach(detail.posts.sorted(by: { $0.createdAt > $1.createdAt })) { post in
            EventPostRow(post: post)
          }
        }
      }
    }
  }

  @MainActor
  private func post() async {
    isPosting = true
    defer { isPosting = false }
    do {
      _ = try await repository.addPost(
        eventID: detail.id,
        authorID: viewerID,
        body: comment,
        audience: audience
      )
      comment = ""
      errorMessage = nil
      onPostAdded()
    } catch {
      errorMessage = error.localizedDescription
    }
  }
}

private struct EventPeoplePage: View {
  let detail: CommunityEventDetail

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      Text(detail.summary.phase() == .memories ? "People who went" : "People going")
        .font(.headline)
        .foregroundStyle(TunedInDesign.primaryText)

      if detail.attendances.isEmpty {
        EventEmptyView(
          systemImage: "person.2",
          title: "No visible plans yet",
          message: "Private attendance stays private. Friends and community plans appear here."
        )
      } else {
        ForEach(detail.attendances) { attendance in
          HStack(spacing: 12) {
            ProfileAvatarView(profile: attendance.profile, size: 46)
            VStack(alignment: .leading, spacing: 3) {
              Text(attendance.profile.displayName)
                .font(.body.weight(.semibold))
                .foregroundStyle(TunedInDesign.primaryText)
              Text("@\(attendance.profile.username) · \(attendance.status.title)")
                .font(.caption)
                .foregroundStyle(TunedInDesign.mutedText)
            }
            Spacer()
            Image(systemName: attendance.audience.icon)
              .foregroundStyle(TunedInDesign.mutedText)
          }
          .padding(14)
          .background(TunedInDesign.cardBackground, in: RoundedRectangle(cornerRadius: 18))
        }
      }
    }
  }
}

private struct EventMemoriesPage: View {
  let detail: CommunityEventDetail
  let viewerID: UUID
  let repository: any EventRepository
  let onSaved: () -> Void

  @State private var isPresentingDiary = false

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      if detail.summary.phase() != .memories {
        EventEmptyView(
          systemImage: "lock.fill",
          title: "Memories unlock after the show",
          message: "For now, make plans and talk with friends. Ratings, diaries, photos, "
            + "and video belong to the post-show moment."
        )
      } else {
        HStack {
          VStack(alignment: .leading, spacing: 4) {
            Text("Concert memories")
              .font(.headline)
              .foregroundStyle(TunedInDesign.primaryText)
            Text("Each person owns their diary and its sharing settings.")
              .font(.caption)
              .foregroundStyle(TunedInDesign.mutedText)
          }
          Spacer()
          if detail.summary.canCreateDiary() {
            Button(detail.diaryPreviews.contains(where: { $0.author.id == viewerID }) ? "Edit mine" : "Add mine") {
              isPresentingDiary = true
            }
              .buttonStyle(.borderedProminent)
              .tint(TunedInDesign.accent)
          }
        }

        if detail.diaryPreviews.isEmpty {
          EventEmptyView(
            systemImage: "book.closed",
            title: "No shared diaries yet",
            message: "Going or Went still exists without a diary. Writing one is always optional."
          )
        } else {
          ForEach(detail.diaryPreviews.sorted(by: { $0.publishedAt > $1.publishedAt })) { diary in
            EventDiaryPreviewCard(diary: diary)
          }
        }
      }
    }
    .fullScreenCover(isPresented: $isPresentingDiary) {
      EventDiaryComposerView(
        eventID: detail.id,
        viewerID: viewerID,
        repository: repository,
        existing: detail.diaryPreviews.first(where: { $0.author.id == viewerID }),
        onSaved: {
          isPresentingDiary = false
          onSaved()
        },
        onDismiss: { isPresentingDiary = false }
      )
    }
  }
}

private struct EventDiaryComposerView: View {
  let eventID: UUID
  let viewerID: UUID
  let repository: any EventRepository
  let existing: EventDiaryPreview?
  let onSaved: () -> Void
  let onDismiss: () -> Void

  @State private var includesScore: Bool
  @State private var score: Double
  @State private var note: String
  @State private var audience: EventAudience
  @State private var isSaving = false
  @State private var errorMessage: String?

  init(
    eventID: UUID,
    viewerID: UUID,
    repository: any EventRepository,
    existing: EventDiaryPreview?,
    onSaved: @escaping () -> Void,
    onDismiss: @escaping () -> Void
  ) {
    self.eventID = eventID
    self.viewerID = viewerID
    self.repository = repository
    self.existing = existing
    self.onSaved = onSaved
    self.onDismiss = onDismiss
    _includesScore = State(initialValue: existing?.score != nil)
    _score = State(initialValue: existing?.score ?? 8)
    _note = State(initialValue: existing?.note ?? "")
    _audience = State(initialValue: existing?.audience ?? .friends)
  }

  var body: some View {
    ZStack {
      TunedInDesign.pageBackground.ignoresSafeArea()

      ScrollView {
        VStack(alignment: .leading, spacing: 18) {
          EventScreenHeader(
            eyebrow: "Your concert, your perspective",
            title: existing == nil ? "Add a diary" : "Edit your diary",
            subtitle: "This belongs to you even if the shared event changes later."
          )

          TunedInFormCard {
            Toggle("Add a score", isOn: $includesScore)
              .tint(TunedInDesign.accent)
            if includesScore {
              HStack {
                Text("Your score")
                  .font(.headline)
                Spacer()
                Text(score.formatted(.number.precision(.fractionLength(1))))
                  .font(.title2.weight(.bold))
                  .foregroundStyle(TunedInDesign.accent)
              }
              Slider(value: $score, in: 0 ... 10, step: 0.1)
                .tint(TunedInDesign.accent)
            }
          }

          TunedInFormCard {
            Text("What do you want to remember?")
              .font(.headline)
              .foregroundStyle(TunedInDesign.primaryText)
            TextEditor(text: $note)
              .frame(minHeight: 160)
              .scrollContentBackground(.hidden)
              .padding(10)
              .background(TunedInDesign.raisedSurface, in: RoundedRectangle(cornerRadius: 14))
            Text("\(note.count)/4000")
              .font(.caption.monospacedDigit())
              .foregroundStyle(note.count > 4_000 ? TunedInDesign.accent : TunedInDesign.mutedText)
              .frame(maxWidth: .infinity, alignment: .trailing)
          }

          TunedInFormCard {
            Text("Who can see this diary?")
              .font(.headline)
              .foregroundStyle(TunedInDesign.primaryText)
            Picker("Diary audience", selection: $audience) {
              ForEach(EventAudience.allCases, id: \.self) { option in
                Text(option.title).tag(option)
              }
            }
            .pickerStyle(.segmented)
            Label(
              "Photos and video will attach to this diary when persistent media support lands.",
              systemImage: "photo.on.rectangle.angled"
            )
            .font(.caption)
            .foregroundStyle(TunedInDesign.mutedText)
          }

          if let errorMessage {
            Text(errorMessage).font(.caption).foregroundStyle(TunedInDesign.accent)
          }

          Button { Task { await save() } } label: {
            Text(isSaving ? "Saving…" : "Save diary")
              .font(.headline)
              .foregroundStyle(TunedInDesign.actionForeground)
              .frame(maxWidth: .infinity)
              .padding(.vertical, 15)
              .background(TunedInDesign.accent, in: Capsule())
          }
          .buttonStyle(.plain)
          .disabled(isSaving || note.count > 4_000)
        }
        .padding(20)
        .padding(.bottom, 24)
      }
    }
    .safeAreaInset(edge: .bottom, spacing: 0) {
      TunedInPersistentControlRegion {
        TunedInSubscreenBackBar(title: "Diary", action: onDismiss)
          .padding(.horizontal, TunedInDesign.bottomControlHorizontalInset)
          .padding(.top, 8)
          .padding(.bottom, TunedInDesign.bottomControlInset)
      }
    }
  }

  @MainActor
  private func save() async {
    isSaving = true
    defer { isSaving = false }
    do {
      _ = try await repository.saveDiary(
        eventID: eventID,
        authorID: viewerID,
        input: EventDiaryInput(
          score: includesScore ? score : nil,
          note: note,
          audience: audience
        )
      )
      errorMessage = nil
      onSaved()
    } catch {
      errorMessage = error.localizedDescription
    }
  }
}

private struct EventInviteView: View {
  let eventID: UUID
  let viewerID: UUID
  let repository: any EventRepository

  @Environment(\.dismiss) private var dismiss
  @State private var candidates: [EventInviteCandidate] = []
  @State private var selection: Set<UUID> = []
  @State private var isLoading = true
  @State private var isSending = false
  @State private var errorMessage: String?

  var body: some View {
    NavigationStack {
      ZStack {
        TunedInDesign.pageBackground.ignoresSafeArea()
        ScrollView {
          VStack(alignment: .leading, spacing: 14) {
            EventScreenHeader(
              eyebrow: "Make a plan together",
              title: "Invite friends",
              subtitle: "Friends already going stay visible, but won’t receive a duplicate invite."
            )

            if isLoading {
              ProgressView("Finding friends…")
            } else if candidates.isEmpty {
              EventEmptyView(
                systemImage: "person.2",
                title: "No friends to invite",
                message: "Add friends first, then bring them into concert plans."
              )
            } else {
              ForEach(candidates) { candidate in
                Button { toggle(candidate) } label: {
                  HStack(spacing: 12) {
                    ProfileAvatarView(profile: candidate.profile, size: 44)
                    VStack(alignment: .leading, spacing: 3) {
                      Text(candidate.profile.displayName)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(TunedInDesign.primaryText)
                      Text(candidateStatus(candidate))
                        .font(.caption)
                        .foregroundStyle(TunedInDesign.mutedText)
                    }
                    Spacer()
                    Image(
                      systemName: selection.contains(candidate.id) ? "checkmark.circle.fill" : "circle"
                    )
                    .foregroundStyle(
                      selection.contains(candidate.id) ? TunedInDesign.accent : TunedInDesign.mutedText
                    )
                  }
                  .padding(12)
                  .background(TunedInDesign.cardBackground, in: RoundedRectangle(cornerRadius: 18))
                }
                .buttonStyle(.plain)
                .disabled(candidate.attendanceStatus != nil || candidate.isAlreadyInvited)
              }
            }

            if let errorMessage {
              Text(errorMessage).font(.caption).foregroundStyle(TunedInDesign.accent)
            }

            Button { Task { await send() } } label: {
              Text(isSending ? "Sending…" : "Send \(selection.count) invite\(selection.count == 1 ? "" : "s")")
                .font(.headline)
                .foregroundStyle(TunedInDesign.actionForeground)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(TunedInDesign.accent, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(selection.isEmpty || isSending)
          }
          .padding(20)
        }
      }
      .toolbar(.hidden, for: .navigationBar)
    }
    .task { await load() }
  }

  private func toggle(_ candidate: EventInviteCandidate) {
    if selection.contains(candidate.id) {
      selection.remove(candidate.id)
    } else {
      selection.insert(candidate.id)
    }
  }

  @MainActor
  private func load() async {
    do {
      candidates = try await repository.inviteCandidates(eventID: eventID, viewerID: viewerID)
      errorMessage = nil
    } catch {
      errorMessage = error.localizedDescription
    }
    isLoading = false
  }

  @MainActor
  private func send() async {
    isSending = true
    defer { isSending = false }
    do {
      try await repository.sendInvitations(
        eventID: eventID,
        senderID: viewerID,
        recipientIDs: Array(selection)
      )
      dismiss()
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  private func candidateStatus(_ candidate: EventInviteCandidate) -> String {
    if let attendanceStatus = candidate.attendanceStatus { return attendanceStatus.title }
    if candidate.isAlreadyInvited { return "Invited" }
    return "@\(candidate.profile.username)"
  }
}

struct CommunityEventRow: View {
  let event: CommunityEventSummary
  let showsSource: Bool

  var body: some View {
    HStack(spacing: 14) {
      EventDateTile(date: event.eventDate)
      VStack(alignment: .leading, spacing: 5) {
        Text(event.title)
          .font(.headline)
          .foregroundStyle(TunedInDesign.primaryText)
          .lineLimit(2)
        Text("\(event.venueName) · \(event.areaName)")
          .font(.subheadline)
          .foregroundStyle(TunedInDesign.mutedText)
          .lineLimit(2)
        eventStatusLine
        if showsSource {
          Text(event.sourceLabel)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(TunedInDesign.mutedText)
            .lineLimit(1)
        }
      }
      Spacer(minLength: 0)
      Image(systemName: "chevron.right")
        .font(.caption.weight(.bold))
        .foregroundStyle(TunedInDesign.mutedText)
    }
    .padding(14)
    .background(TunedInDesign.cardBackground, in: RoundedRectangle(cornerRadius: TunedInDesign.cornerRadius))
    .overlay {
      RoundedRectangle(cornerRadius: TunedInDesign.cornerRadius)
        .strokeBorder(TunedInDesign.cardBorder.opacity(0.55))
    }
    .contentShape(Rectangle())
  }

  private var eventStatusLine: some View {
    HStack(spacing: 8) {
      switch event.phase() {
      case .cancelled:
        Label("Cancelled", systemImage: "xmark.circle.fill")
      case .postponed:
        Label("Postponed", systemImage: "clock.badge.exclamationmark")
      case .upcoming, .memories:
        if event.currentUserAttendance != nil {
          Label(event.phase() == .memories ? "Went" : "Going", systemImage: "checkmark.circle.fill")
        }
      }
      if !event.friendPreviews.isEmpty {
        Label(
          "\(event.friendPreviews.count) friend\(event.friendPreviews.count == 1 ? "" : "s")",
          systemImage: "person.2.fill"
        )
      }
    }
    .font(.caption.weight(.semibold))
    .foregroundStyle(TunedInDesign.accent)
  }
}

private struct CommunityActivityCard: View {
  let activity: EventActivity

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack(spacing: 10) {
        ProfileAvatarView(profile: activity.actor, size: 42)
        VStack(alignment: .leading, spacing: 2) {
          Text(activity.actor.displayName)
            .font(.subheadline.weight(.bold))
            .foregroundStyle(TunedInDesign.primaryText)
          Text(activity.message)
            .font(.subheadline)
            .foregroundStyle(TunedInDesign.mutedText)
        }
        Spacer()
        Text(activity.occurredAt, style: .relative)
          .font(.caption2)
          .foregroundStyle(TunedInDesign.mutedText)
      }
      CommunityEventRow(event: activity.event, showsSource: false)
    }
    .padding(16)
    .background(TunedInDesign.cardBackground, in: RoundedRectangle(cornerRadius: TunedInDesign.largeCornerRadius))
    .overlay {
      RoundedRectangle(cornerRadius: TunedInDesign.largeCornerRadius)
        .strokeBorder(TunedInDesign.cardBorder.opacity(0.5))
    }
  }
}

private struct EventDiaryPreviewCard: View {
  let diary: EventDiaryPreview

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(spacing: 10) {
        ProfileAvatarView(profile: diary.author, size: 42)
        VStack(alignment: .leading, spacing: 2) {
          Text(diary.author.displayName)
            .font(.subheadline.weight(.bold))
            .foregroundStyle(TunedInDesign.primaryText)
          Text("@\(diary.author.username)")
            .font(.caption)
            .foregroundStyle(TunedInDesign.mutedText)
        }
        Spacer()
        if let score = diary.score {
          Text(score.formatted(.number.precision(.fractionLength(1))))
            .font(.title3.weight(.bold))
            .foregroundStyle(TunedInDesign.accent)
        }
      }
      if let note = diary.note {
        Text(note)
          .font(.body)
          .foregroundStyle(TunedInDesign.primaryText)
      }
      HStack(spacing: 14) {
        Label("\(diary.photoCount)", systemImage: "photo")
        Label("\(diary.videoCount)", systemImage: "video")
        Label(diary.audience.title, systemImage: diary.audience.icon)
      }
      .font(.caption.weight(.semibold))
      .foregroundStyle(TunedInDesign.mutedText)
    }
    .padding(16)
    .background(TunedInDesign.cardBackground, in: RoundedRectangle(cornerRadius: TunedInDesign.cornerRadius))
    .overlay {
      RoundedRectangle(cornerRadius: TunedInDesign.cornerRadius)
        .strokeBorder(TunedInDesign.cardBorder.opacity(0.55))
    }
  }
}

private struct EventPostRow: View {
  let post: EventPost

  var body: some View {
    HStack(alignment: .top, spacing: 10) {
      ProfileAvatarView(profile: post.author, size: 38)
      VStack(alignment: .leading, spacing: 4) {
        HStack {
          Text(post.author.displayName)
            .font(.subheadline.weight(.bold))
          Image(systemName: post.audience.icon)
            .font(.caption2)
            .foregroundStyle(TunedInDesign.mutedText)
          Spacer()
          Text(post.createdAt, style: .relative)
            .font(.caption2)
            .foregroundStyle(TunedInDesign.mutedText)
        }
        Text(post.body)
          .font(.subheadline)
          .foregroundStyle(TunedInDesign.primaryText)
      }
    }
    .padding(.vertical, 8)
  }
}

private struct EventDateTile: View {
  let date: Date

  var body: some View {
    VStack(spacing: 1) {
      Text(date.formatted(.dateTime.month(.abbreviated)))
        .font(.caption2.weight(.bold))
        .textCase(.uppercase)
        .foregroundStyle(TunedInDesign.accent)
      Text(date.formatted(.dateTime.day()))
        .font(.title2.weight(.bold))
        .foregroundStyle(TunedInDesign.primaryText)
      Text(date.formatted(.dateTime.weekday(.abbreviated)))
        .font(.caption2.weight(.semibold))
        .foregroundStyle(TunedInDesign.mutedText)
    }
    .frame(width: 58, height: 68)
    .background(TunedInDesign.raisedSurface, in: RoundedRectangle(cornerRadius: 16))
  }
}

private struct EventAvatarStack: View {
  let profiles: [SocialProfile]

  var body: some View {
    HStack(spacing: -9) {
      ForEach(profiles.prefix(3)) { profile in
        ProfileAvatarView(profile: profile, size: 34)
          .overlay(Circle().stroke(TunedInDesign.cardBackground, lineWidth: 2))
      }
    }
  }
}

private struct EventMetadataRow: View {
  let label: String
  let value: String

  var body: some View {
    HStack(alignment: .top) {
      Text(label)
        .font(.subheadline)
        .foregroundStyle(TunedInDesign.mutedText)
        .frame(width: 72, alignment: .leading)
      Text(value)
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(TunedInDesign.primaryText)
      Spacer(minLength: 0)
    }
  }
}

private struct EventScreenHeader: View {
  let eyebrow: String
  let title: String
  let subtitle: String

  var body: some View {
    VStack(alignment: .leading, spacing: 7) {
      Text(eyebrow)
        .font(.caption2.weight(.bold))
        .foregroundStyle(TunedInDesign.accent)
        .textCase(.uppercase)
        .tracking(1.2)
      Text(title)
        .font(.largeTitle.weight(.bold))
        .foregroundStyle(TunedInDesign.primaryText)
      Text(subtitle)
        .font(.subheadline)
        .foregroundStyle(TunedInDesign.mutedText)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

private struct EventEmptyView: View {
  let systemImage: String
  let title: String
  let message: String

  var body: some View {
    VStack(spacing: 12) {
      Image(systemName: systemImage)
        .font(.title2.weight(.semibold))
        .foregroundStyle(TunedInDesign.accent)
        .frame(width: 56, height: 56)
        .background(TunedInDesign.accentTint, in: Circle())
      Text(title)
        .font(.headline)
        .foregroundStyle(TunedInDesign.primaryText)
      Text(message)
        .font(.subheadline)
        .foregroundStyle(TunedInDesign.mutedText)
        .multilineTextAlignment(.center)
    }
    .frame(maxWidth: .infinity)
    .padding(24)
    .background(TunedInDesign.cardBackground, in: RoundedRectangle(cornerRadius: TunedInDesign.cornerRadius))
  }
}

private struct EventFailureView: View {
  let message: String
  let retry: () -> Void

  var body: some View {
    VStack(spacing: 12) {
      Label("Couldn’t load events", systemImage: "exclamationmark.triangle")
        .font(.headline)
        .foregroundStyle(TunedInDesign.primaryText)
      Text(message)
        .font(.subheadline)
        .foregroundStyle(TunedInDesign.mutedText)
        .multilineTextAlignment(.center)
      Button("Try again", action: retry)
        .buttonStyle(.borderedProminent)
        .tint(TunedInDesign.accent)
    }
    .frame(maxWidth: .infinity)
    .padding(24)
  }
}

private extension EventAttendanceStatus {
  var title: String {
    switch self {
    case .going: "Going"
    case .went: "Went"
    case .didNotGo: "Didn’t go"
    }
  }
}

private extension EventAudience {
  var icon: String {
    switch self {
    case .privateOnly: "lock.fill"
    case .friends: "person.2.fill"
    case .community: "globe.americas.fill"
    }
  }
}

extension CatalogEntityKind: Identifiable {
  var id: String { rawValue }
}
