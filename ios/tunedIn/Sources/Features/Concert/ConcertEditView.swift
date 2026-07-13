// The three focused editing pages share one draft and save boundary.
// swiftlint:disable type_body_length
import PhotosUI
import SwiftUI

struct ConcertEditView: View {
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
  let viewerRole: ConcertViewerRole
  let viewerUsername: String
  let socialRepository: any SocialRepository
  let concertRepository: any ConcertRepository
  let loadLatestDetail: @Sendable () async throws -> ConcertDetail
  let onSaved: (Concert) -> Void

  @Environment(\.dismiss) private var dismiss
  @State private var draft: ConcertDraft
  @State private var visibility: ConcertVisibility
  @State private var expectedVersion: Int64
  @State private var page: EditPage = .night
  @State private var isSaving = false
  @State private var isReloadingAfterConflict = false
  @State private var errorMessage: String?
  @State private var conflictMessage: String?
  @State private var pendingVisibilityNarrowing: ConcertVisibility?
  @State private var selectedPhoto: PhotosPickerItem?
  @State private var isChangingPhoto = false
  @State private var isConfirmingPhotoRemoval = false
  @State private var workingDetail: ConcertDetail
  @Namespace private var editSelectionNamespace

  init(
    detail: ConcertDetail,
    canMakePrivate: Bool,
    viewerRole: ConcertViewerRole,
    viewerUsername: String,
    socialRepository: any SocialRepository,
    concertRepository: any ConcertRepository,
    loadLatestDetail: @escaping @Sendable () async throws -> ConcertDetail,
    onSaved: @escaping (Concert) -> Void
  ) {
    self.detail = detail
    self.canMakePrivate = canMakePrivate
    self.viewerRole = viewerRole
    self.viewerUsername = viewerUsername
    self.socialRepository = socialRepository
    self.concertRepository = concertRepository
    self.loadLatestDetail = loadLatestDetail
    self.onSaved = onSaved
    _draft = State(initialValue: ConcertDraft(detail: detail))
    _visibility = State(initialValue: detail.concert.visibility)
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
      .overlay(alignment: .bottom) {
        saveBar
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
        Button("Remove", role: .destructive) { Task { await removePhoto() } }
      } message: { Text("The generated concert artwork will be shown instead.") }
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
    .onChange(of: selectedPhoto) { _, item in
      guard let item else { return }
      Task { await uploadPhoto(item) }
    }
  }

  private var nightPage: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 18) {
        concertPhotoEditor

        TunedInTicketCard {
          Text("HEADLINER")
            .font(.caption.weight(.bold))
            .foregroundStyle(.white.opacity(0.78))
          TextField(
            "Artist",
            text: artistBinding(for: draft.artists.first?.id)
          )
          .font(.title2.weight(.bold))
          .foregroundStyle(.white)
          .tint(.white)
          .textInputAutocapitalization(.words)

          Divider().overlay(.white.opacity(0.24))

          TextField("Venue", text: $draft.venueName)
            .font(.title3.weight(.semibold))
            .foregroundStyle(.white)
            .tint(.white)
            .textInputAutocapitalization(.words)

          HStack {
            Label("Date", systemImage: "calendar")
              .foregroundStyle(.white.opacity(0.84))
            Spacer()
            DatePicker("Concert date", selection: $draft.concertDate, displayedComponents: .date)
              .labelsHidden()
              .tint(.white)
          }
        }

        TunedInFormCard {
          Text("Details")
            .font(.headline)
            .foregroundStyle(TunedInDesign.primaryText)
          TextField("City", text: $draft.city)
            .textInputAutocapitalization(.words)
          TextField("Tour", text: $draft.tour)
            .textInputAutocapitalization(.words)
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
          TunedInFormCard {
            Text("On the bill")
              .font(.headline)
              .foregroundStyle(TunedInDesign.primaryText)
            ForEach(draft.artists.dropFirst()) { artist in
              HStack {
                TextField("Another artist", text: artistBinding(for: artist.id))
                Button("Headliner") { draft.makePrimary(artist.id) }
                  .font(.caption.weight(.bold))
                  .foregroundStyle(TunedInDesign.accent)
              }
            }
          }
        }
      }
      .padding(.horizontal, 20)
      .padding(.bottom, 104)
    }
  }

  private var concertPhotoEditor: some View {
    HStack(spacing: 14) {
      ConcertPhotoView(
        concert: detail.concert,
        artistName: detail.artists.first(where: \.isPrimary)?.name ?? "Concert",
        repository: concertRepository
      )
      .frame(width: 104, height: 138)
      .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

      VStack(alignment: .leading, spacing: 9) {
        Text("Main photo").font(.headline).foregroundStyle(TunedInDesign.primaryText)
        Text("Portrait 3:4").font(.caption).foregroundStyle(TunedInDesign.mutedText)
        PhotosPicker(selection: $selectedPhoto, matching: .images) {
          Label(detail.concert.photoObjectPath == nil ? "Add photo" : "Change photo", systemImage: "photo")
            .font(.subheadline.weight(.semibold))
        }
        if detail.concert.photoObjectPath != nil {
          Button("Remove", role: .destructive) { isConfirmingPhotoRemoval = true }
            .font(.subheadline.weight(.semibold))
        }
        if isChangingPhoto {
          ProgressView().controlSize(.small)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .disabled(isChangingPhoto)
    }
    .padding(14)
    .background(TunedInDesign.raisedSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
  }

  private func uploadPhoto(_ item: PhotosPickerItem) async {
    isChangingPhoto = true
    defer { isChangingPhoto = false }
    do {
      guard let data = try await item.loadTransferable(type: Data.self) else { return }
      let jpeg = try await AvatarImageProcessor.processConcertPhoto(data)
      let updated = try await concertRepository.setConcertPhoto(jpeg, concertID: detail.concert.id)
      onSaved(updated)
      dismiss()
    } catch { errorMessage = error.localizedDescription }
  }

  private func removePhoto() async {
    isChangingPhoto = true
    defer { isChangingPhoto = false }
    do {
      let updated = try await concertRepository.removeConcertPhoto(concertID: detail.concert.id)
      onSaved(updated)
      dismiss()
    } catch { errorMessage = error.localizedDescription }
  }

  private var songsPage: some View {
    VStack(alignment: .leading, spacing: 16) {
      VStack(alignment: .leading, spacing: 4) {
        Text("Setlist")
          .font(.system(size: 30, weight: .bold, design: .serif))
          .foregroundStyle(TunedInDesign.primaryText)
        Text("Drag to reorder.")
          .font(.subheadline)
          .foregroundStyle(TunedInDesign.mutedText)
      }
      .padding(.horizontal, 20)
      .padding(.top, 8)

      List {
        ForEach(draft.setlist) { item in
          HStack {
            TextField("Song title", text: setlistBinding(for: item.id))
              .textInputAutocapitalization(.words)
          }
          .swipeActions {
            Button(role: .destructive) { draft.removeSetlistItem(item.id) } label: {
              Label("Remove", systemImage: "trash")
            }
          }
          .listRowBackground(TunedInDesign.cardBackground)
        }
        .onMove { source, destination in
          draft.moveSetlist(from: source, to: destination)
        }

        Button {
          draft.addSetlistItem()
        } label: {
          Label("Add a song", systemImage: "plus")
            .font(.headline)
            .foregroundStyle(TunedInDesign.accent)
        }
        .disabled(draft.setlist.count == 50)
        .listRowBackground(TunedInDesign.raisedSurface)
      }
      .listStyle(.insetGrouped)
      .scrollContentBackground(.hidden)
      .background(TunedInDesign.pageBackground)
      .environment(\.editMode, .constant(.active))
    }
  }

  private var sharingPage: some View {
    ConcertPeopleView(
      detail: workingDetail,
      viewerRole: viewerRole,
      viewerUsername: viewerUsername,
      socialRepository: socialRepository,
      concertRepository: concertRepository,
      onChanged: { Task { await refreshSharingDetail() } },
      pageHeader: AnyView(EmptyView())
    )
    .padding(.bottom, 76)
  }

  private func refreshSharingDetail() async {
    do {
      let latest = try await loadLatestDetail()
      workingDetail = latest
      visibility = latest.concert.visibility
      expectedVersion = latest.concert.version
      errorMessage = nil
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  private var availableVisibility: [ConcertVisibility] {
    canMakePrivate ? ConcertVisibility.allCases : [.collaborators, .friends]
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
        dismiss()
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
              .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Show \(item.title.lowercased())")
          }
        }
      }
      .frame(maxWidth: 252)
    } trailing: {
      TunedInFloatingAction(
        systemImage: isSaving ? "ellipsis" : "checkmark",
        accessibilityLabel: isSaving ? "Saving concert" : "Save concert",
        accessibilityHint: "Saves this version and returns to the concert",
        action: save
      )
      .disabled(isSaving)
    }
    .padding(.horizontal, TunedInDesign.bottomControlHorizontalInset)
    .padding(.top, 8)
    .padding(.bottom, TunedInDesign.bottomControlInset)
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
      ? "Everyone you tagged will lose access immediately. You will be the only person who can see this concert."
      : "Friends who are not tagged editors will lose access. Tagged editors keep their role."
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

  private func artistBinding(for id: UUID?) -> Binding<String> {
    Binding(
      get: { draft.artists.first(where: { $0.id == id })?.name ?? "" },
      set: { value in
        guard let id, let index = draft.artists.firstIndex(where: { $0.id == id }) else { return }
        draft.artists[index].name = value
      }
    )
  }

  private func setlistBinding(for id: UUID) -> Binding<String> {
    Binding(
      get: { draft.setlist.first(where: { $0.id == id })?.title ?? "" },
      set: { value in
        guard let index = draft.setlist.firstIndex(where: { $0.id == id }) else { return }
        draft.setlist[index].title = value
      }
    )
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
    guard let input = draft.updateInput(
      concertID: detail.concert.id,
      expectedVersion: expectedVersion,
      visibility: visibility
    ) else { return }
    isSaving = true
    Task {
      do {
        let updated = try await concertRepository.updateConcert(input)
        onSaved(updated)
        dismiss()
      } catch {
        if isConcertConflict(error) {
          conflictMessage = error.localizedDescription
        } else {
          errorMessage = error.localizedDescription
        }
      }
      isSaving = false
    }
  }

  private func reloadAfterConflict() async {
    isReloadingAfterConflict = true
    defer { isReloadingAfterConflict = false }

    do {
      let latest = try await loadLatestDetail()
      draft = ConcertDraft(detail: latest)
      visibility = latest.concert.visibility
      expectedVersion = latest.concert.version
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

// swiftlint:enable type_body_length
