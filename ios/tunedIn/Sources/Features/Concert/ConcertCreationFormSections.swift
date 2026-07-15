import SwiftUI

private enum ConcertCreationDetailPage: Int, CaseIterable, Identifiable {
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

struct ConcertCreationDetailsView: View {
  @Binding var draft: ConcertDraft
  @Environment(\.dismiss) private var dismiss
  @Environment(\.musicCatalogRepository) private var musicCatalogRepository
  @State private var page: ConcertCreationDetailPage = .lineup
  @Namespace private var detailSelectionNamespace
  @State private var catalogPickerTarget: ConcertCatalogPickerTarget?

  var body: some View {
    NavigationStack {
      ZStack {
        TunedInDesign.pageBackground
          .ignoresSafeArea()

        TabView(selection: $page) {
          lineupPage.tag(ConcertCreationDetailPage.lineup)
          contextPage.tag(ConcertCreationDetailPage.context)
          setlistPage.tag(ConcertCreationDetailPage.setlist)
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
    .fullScreenCover(item: $catalogPickerTarget) { target in
      catalogPicker(for: target)
    }
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
          ForEach(ConcertCreationDetailPage.allCases) { item in
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
              Button {
                catalogPickerTarget = .artist(artist.id)
              } label: {
                HStack {
                  Text(artist.name.isEmpty ? "Choose artist" : artist.name)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(artist.name.isEmpty ? TunedInDesign.mutedText : TunedInDesign.primaryText)
                  Spacer()
                  Image(systemName: "magnifyingglass")
                    .foregroundStyle(TunedInDesign.accent)
                }
                .contentShape(.interaction, Rectangle())
              }
              .buttonStyle(.plain)
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
          catalogPickerTarget = .artist(UUID())
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
          HStack {
            VStack(alignment: .leading, spacing: 2) {
              Text("City or area")
                .font(.caption)
                .foregroundStyle(TunedInDesign.mutedText)
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
                Text("Tour (optional)")
                  .font(.caption)
                  .foregroundStyle(TunedInDesign.mutedText)
                Text(draft.tour?.displayName ?? "Choose tour")
                  .foregroundStyle(draft.tour == nil ? TunedInDesign.mutedText : TunedInDesign.primaryText)
              }
              Spacer()
              Image(systemName: "magnifyingglass")
                .foregroundStyle(TunedInDesign.accent)
            }
            .contentShape(.interaction, Rectangle())
          }
          .buttonStyle(.plain)
          if draft.tour != nil {
            Button("Remove tour", role: .destructive) { draft.tour = nil }
              .font(.caption.weight(.semibold))
          }
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
            Button {
              catalogPickerTarget = .song(item.id)
            } label: {
              HStack {
                Text(item.title)
                  .foregroundStyle(TunedInDesign.primaryText)
                Spacer()
                Image(systemName: "magnifyingglass")
                  .foregroundStyle(TunedInDesign.accent)
              }
              .contentShape(.interaction, Rectangle())
            }
            .buttonStyle(.plain)
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
          catalogPickerTarget = .song(nil)
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

  @ViewBuilder
  private func catalogPicker(for target: ConcertCatalogPickerTarget) -> some View {
    switch target {
    case let .artist(id):
      CatalogPickerView(
        repository: musicCatalogRepository,
        configuration: CatalogPickerConfiguration(
          kind: .artist,
          title: draft.artists.contains(where: { $0.id == id }) ? "Replace artist" : "Add artist",
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
      EmptyView()
    case let .song(id):
      CatalogPickerView(
        repository: musicCatalogRepository,
        configuration: CatalogPickerConfiguration(
          kind: .song,
          title: id == nil ? "Add song" : "Replace song",
          artistContext: draft.selectedCatalogArtists,
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
          currentSelectionName: draft.tour?.displayName
        )
      ) { entity in
        guard case let .tour(tour) = entity else { return }
        draft.tour = tour
        catalogPickerTarget = nil
      }
    }
  }
}
