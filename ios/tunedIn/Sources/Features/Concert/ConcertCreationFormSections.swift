import SwiftUI

struct ConcertCreationDetailsView: View {
  private enum DetailPage: Int, CaseIterable, Identifiable {
    case lineup
    case context
    case setlist

    var id: Int {
      rawValue
    }

    var title: String {
      switch self {
      case .lineup: "Lineup"
      case .context: "Context"
      case .setlist: "Setlist"
      }
    }

    var icon: String {
      switch self {
      case .lineup: "person.2.fill"
      case .context: "sparkles"
      case .setlist: "music.note.list"
      }
    }
  }

  @Binding var draft: ConcertDraft
  @Environment(\.dismiss) private var dismiss
  @State private var page: DetailPage = .lineup
  @Namespace private var detailSelectionNamespace

  var body: some View {
    NavigationStack {
      ZStack {
        TunedInDesign.pageBackground
          .ignoresSafeArea()

        TabView(selection: $page) {
          lineupPage.tag(DetailPage.lineup)
          contextPage.tag(DetailPage.context)
          setlistPage.tag(DetailPage.setlist)
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
      }
      .toolbar {
        ToolbarItem(placement: .principal) {
          Text("Concert details")
            .font(.headline)
            .foregroundStyle(TunedInDesign.primaryText)
        }
      }
      .safeAreaInset(edge: .bottom, spacing: 0) {
        TunedInPersistentControlRegion {
          detailsBar
        }
      }
    }
    .tint(TunedInDesign.accent)
    .tunedInKeyboardManaged()
  }

  private var detailsBar: some View {
    TunedInGlassTraversalLayout {
      TunedInGlassIconButton(
        systemImage: "chevron.backward",
        accessibilityLabel: "Back to new concert"
      ) {
        dismiss()
      }
    } center: {
      TunedInGlassBottomBar {
        HStack(spacing: 2) {
          ForEach(DetailPage.allCases) { item in
            Button {
              withAnimation(.smooth(duration: 0.24, extraBounce: 0)) { page = item }
            } label: {
              VStack(spacing: 2) {
                Image(systemName: item.icon)
                  .font(.subheadline.weight(.bold))
                Text(item.title)
                  .font(.caption2.weight(.bold))
                  .lineLimit(1)
                  .minimumScaleFactor(0.7)
              }
              .foregroundStyle(page == item ? TunedInDesign.actionForeground : TunedInDesign.primaryText)
              .frame(maxWidth: .infinity)
              .frame(height: 48)
              .background {
                if page == item {
                  Capsule()
                    .fill(TunedInDesign.accent)
                    .matchedGeometryEffect(id: "detail-page", in: detailSelectionNamespace)
                }
              }
              .contentShape(.interaction, Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Show \(item.title.lowercased())")
          }
        }
      }
      .frame(maxWidth: 252)
    } trailing: {
      EmptyView()
    }
    .padding(.horizontal, TunedInDesign.bottomControlHorizontalInset)
    .padding(.top, 8)
    .padding(.bottom, TunedInDesign.bottomControlInset)
  }

  private var lineupPage: some View {
    VStack(alignment: .leading, spacing: 16) {
      pageHeading(
        title: "Who shared the stage?",
        subtitle: "The first artist is the headliner. Add the rest only if it matters."
      )

      List {
        ForEach(draft.artists) { artist in
          HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
              TextField(artist.isPrimary ? "Headliner" : "Artist", text: artistBinding(for: artist.id))
                .textInputAutocapitalization(.words)
              if artist.isPrimary {
                Text("HEADLINER")
                  .font(.caption2.weight(.black))
                  .foregroundStyle(TunedInDesign.accent)
              }
            }
            Spacer()
            if !artist.isPrimary {
              Menu {
                Button("Make headliner") { draft.makePrimary(artist.id) }
                Button("Remove", role: .destructive) { draft.removeArtist(artist.id) }
              } label: {
                Image(systemName: "ellipsis.circle")
                  .font(.title3)
                  .foregroundStyle(TunedInDesign.mutedText)
              }
            }
          }
          .padding(.vertical, 6)
          .listRowBackground(Color.clear)
        }
        .onMove { source, destination in
          draft.moveArtists(from: source, to: destination)
        }

        Button {
          draft.addArtist()
        } label: {
          Label("Add another artist", systemImage: "plus")
            .font(.headline)
            .foregroundStyle(TunedInDesign.accent)
        }
        .disabled(draft.artists.count == 10)
        .padding(.vertical, 8)
        .listRowBackground(Color.clear)
      }
      .listStyle(.plain)
      .contentMargins(.horizontal, 20, for: .scrollContent)
      .scrollContentBackground(.hidden)
      .background(TunedInDesign.pageBackground)
    }
  }

  private var contextPage: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 18) {
        pageHeading(
          title: "More details",
          subtitle: "Optional."
        )

        TunedInFormCard {
          Text("Place and tour")
            .font(.headline)
            .foregroundStyle(TunedInDesign.primaryText)
          TextField("City", text: $draft.city)
            .textContentType(.addressCity)
            .textInputAutocapitalization(.words)
          TextField("Tour", text: $draft.tour)
            .textInputAutocapitalization(.words)
        }

        TunedInFormCard {
          Toggle("Remember the start time", isOn: $draft.hasStartTime)
            .font(.headline)
            .foregroundStyle(TunedInDesign.primaryText)

          if draft.hasStartTime {
            DatePicker("Start time", selection: $draft.startTime, displayedComponents: .hourAndMinute)
            Picker("Venue time zone", selection: $draft.venueTimeZoneIdentifier) {
              ForEach(TimeZone.knownTimeZoneIdentifiers.sorted(), id: \.self) { identifier in
                Text(identifier).tag(identifier)
              }
            }
            Text("The time is anchored to the venue, not your current location.")
              .font(.caption)
              .foregroundStyle(TunedInDesign.mutedText)
          }
        }
      }
      .padding(.horizontal, 20)
      .padding(.top, 10)
      .padding(.bottom, 28)
    }
  }

  private var setlistPage: some View {
    VStack(alignment: .leading, spacing: 16) {
      pageHeading(
        title: "Setlist",
        subtitle: "Add songs in the order you remember."
      )

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
          .padding(.vertical, 6)
          .listRowBackground(Color.clear)
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
        .padding(.vertical, 8)
        .listRowBackground(Color.clear)
      }
      .listStyle(.plain)
      .contentMargins(.horizontal, 20, for: .scrollContent)
      .scrollContentBackground(.hidden)
      .background(TunedInDesign.pageBackground)
      .environment(\.editMode, .constant(.active))
    }
  }

  private func pageHeading(title: String, subtitle: String) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(title)
        .font(.system(size: 30, weight: .bold, design: .rounded))
        .foregroundStyle(TunedInDesign.primaryText)
      Text(subtitle)
        .font(.subheadline)
        .foregroundStyle(TunedInDesign.mutedText)
    }
    .padding(.horizontal, 20)
    .padding(.top, 10)
  }

  private func artistBinding(for id: UUID) -> Binding<String> {
    Binding(
      get: { draft.artists.first(where: { $0.id == id })?.name ?? "" },
      set: { value in
        guard let index = draft.artists.firstIndex(where: { $0.id == id }) else { return }
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
}
