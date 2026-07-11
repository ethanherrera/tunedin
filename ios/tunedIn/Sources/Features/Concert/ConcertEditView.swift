// The three focused editing pages share one draft and save boundary.
// swiftlint:disable type_body_length
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
      case .night: "The night"
      case .songs: "Songs"
      case .sharing: "Sharing"
      }
    }

    var icon: String {
      switch self {
      case .night: "sparkles"
      case .songs: "music.note.list"
      case .sharing: "person.2.fill"
      }
    }
  }

  let detail: ConcertDetail
  let concertRepository: any ConcertRepository
  let onSaved: (Concert) -> Void

  @Environment(\.dismiss) private var dismiss
  @State private var draft: ConcertDraft
  @State private var visibility: ConcertVisibility
  @State private var page: EditPage = .night
  @State private var isSaving = false
  @State private var errorMessage: String?

  init(
    detail: ConcertDetail,
    concertRepository: any ConcertRepository,
    onSaved: @escaping (Concert) -> Void
  ) {
    self.detail = detail
    self.concertRepository = concertRepository
    self.onSaved = onSaved
    _draft = State(initialValue: ConcertDraft(detail: detail))
    _visibility = State(initialValue: detail.concert.visibility)
  }

  var body: some View {
    NavigationStack {
      ZStack {
        TunedInDesign.pageBackground
          .ignoresSafeArea()

        VStack(spacing: 0) {
          pagePicker
          TabView(selection: $page) {
            nightPage.tag(EditPage.night)
            songsPage.tag(EditPage.songs)
            sharingPage.tag(EditPage.sharing)
          }
          .tabViewStyle(.page(indexDisplayMode: .never))
        }
      }
      .safeAreaInset(edge: .bottom, spacing: 0) {
        saveBar
      }
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button("Cancel") { dismiss() }
            .disabled(isSaving)
        }
        ToolbarItem(placement: .principal) {
          Text("Shape the night")
            .font(.headline)
            .foregroundStyle(TunedInDesign.primaryText)
        }
      }
      .alert("Couldn’t save your changes", isPresented: isShowingError) {
        Button("OK", role: .cancel) {}
      } message: {
        Text(errorMessage ?? "Please try again.")
      }
    }
    .tint(TunedInDesign.accent)
  }

  private var pagePicker: some View {
    HStack(spacing: 8) {
      ForEach(EditPage.allCases) { item in
        Button {
          withAnimation(.snappy) { page = item }
        } label: {
          Label(item.title, systemImage: item.icon)
            .font(.caption.weight(.bold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .foregroundStyle(page == item ? TunedInDesign.actionForeground : TunedInDesign.primaryText)
            .background(
              page == item ? TunedInDesign.accent : TunedInDesign.raisedSurface,
              in: Capsule()
            )
        }
        .buttonStyle(.plain)
      }
    }
    .padding(.horizontal, 20)
    .padding(.vertical, 12)
  }

  private var nightPage: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 18) {
        Text("What made it this night?")
          .font(.system(size: 32, weight: .bold, design: .serif))
          .foregroundStyle(TunedInDesign.primaryText)
          .padding(.top, 8)

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
          Text("A little context")
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

  private var songsPage: some View {
    VStack(alignment: .leading, spacing: 16) {
      VStack(alignment: .leading, spacing: 4) {
        Text("The songs that stayed")
          .font(.system(size: 30, weight: .bold, design: .serif))
          .foregroundStyle(TunedInDesign.primaryText)
        Text("Drag them into the order you remember.")
          .font(.subheadline)
          .foregroundStyle(TunedInDesign.mutedText)
      }
      .padding(.horizontal, 20)
      .padding(.top, 8)

      List {
        ForEach(draft.setlist) { item in
          HStack(spacing: 12) {
            Image(systemName: "line.3.horizontal")
              .foregroundStyle(TunedInDesign.mutedText)
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
    }
  }

  private var sharingPage: some View {
    VStack(alignment: .leading, spacing: 18) {
      VStack(alignment: .leading, spacing: 5) {
        Text("Who gets the feeling?")
          .font(.system(size: 30, weight: .bold, design: .serif))
          .foregroundStyle(TunedInDesign.primaryText)
        Text("People are added from the concert after you save this choice.")
          .font(.subheadline)
          .foregroundStyle(TunedInDesign.mutedText)
      }

      VStack(spacing: 10) {
        ForEach(availableVisibility, id: \.rawValue) { option in
          visibilityChoice(option)
        }
      }

      TunedInGlassSection {
        Image(systemName: visibility == .private ? "lock.fill" : "person.2.fill")
          .font(.title3)
          .foregroundStyle(TunedInDesign.accent)
        Text(sharingTitle)
          .font(.headline)
          .foregroundStyle(TunedInDesign.primaryText)
        Text(sharingDescription)
          .font(.subheadline)
          .foregroundStyle(TunedInDesign.mutedText)
      }

      Spacer()
    }
    .padding(20)
    .padding(.bottom, 88)
  }

  private var availableVisibility: [ConcertVisibility] {
    ConcertVisibility.allCases
  }

  private func visibilityChoice(_ option: ConcertVisibility) -> some View {
    Button {
      withAnimation(.snappy) { visibility = option }
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
            .foregroundStyle(visibility == option ? TunedInDesign.actionForeground.opacity(0.8) : TunedInDesign.mutedText)
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
    case .collaborators: "Tagged people can shape it with you."
    case .friends: "Friends can see the night and leave a note."
    }
  }

  private var sharingDescription: String {
    switch visibility {
    case .private: "You can broaden it later, whenever it feels right."
    case .collaborators: "Editors can update the details and setlist."
    case .friends: "Editors keep editing rights; friends cannot change the night."
    }
  }

  private var saveBar: some View {
    Button(action: save) {
      HStack(spacing: 8) {
        if isSaving {
          ProgressView().tint(TunedInDesign.actionForeground)
        }
        Text(isSaving ? "Saving…" : "Save this version")
          .font(.headline)
      }
      .foregroundStyle(TunedInDesign.actionForeground)
      .frame(maxWidth: .infinity)
      .padding(.vertical, 16)
      .background(TunedInDesign.accent, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
    .buttonStyle(.plain)
    .disabled(isSaving)
    .padding(.horizontal, 20)
    .padding(.top, 12)
    .padding(.bottom, 8)
    .background(TunedInDesign.pageBackground.opacity(0.96))
  }

  private var isShowingError: Binding<Bool> {
    Binding(get: { errorMessage != nil }, set: {
      if !$0 {
        errorMessage = nil
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
      expectedVersion: detail.concert.version,
      visibility: visibility
    ) else { return }
    isSaving = true
    Task {
      do {
        let updated = try await concertRepository.updateConcert(input)
        onSaved(updated)
        dismiss()
      } catch {
        errorMessage = error.localizedDescription
      }
      isSaving = false
    }
  }
}
// swiftlint:enable type_body_length
