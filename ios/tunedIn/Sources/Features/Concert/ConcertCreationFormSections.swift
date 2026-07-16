import SwiftUI

struct ConcertCreationSetlistView: View {
  @Binding var draft: ConcertDraft

  @Environment(\.dismiss) private var dismiss
  @Environment(\.musicCatalogRepository) private var musicCatalogRepository
  @State private var catalogPickerTarget: ConcertCatalogPickerTarget?

  var body: some View {
    NavigationStack {
      ZStack {
        TunedInDesign.pageBackground
          .ignoresSafeArea()

        VStack(spacing: 0) {
          header
          setlist
        }
      }
      .toolbar(.hidden, for: .navigationBar)
      .safeAreaInset(edge: .bottom, spacing: 0) {
        TunedInPersistentControlRegion {
          TunedInSubscreenBackBar(title: setlistSummary) {
            dismiss()
          }
          .padding(.horizontal, TunedInDesign.bottomControlHorizontalInset)
          .padding(.top, 8)
          .padding(.bottom, TunedInDesign.bottomControlInset)
        }
      }
    }
    .tint(TunedInDesign.accent)
    .tunedInKeyboardManaged()
    .fullScreenCover(item: $catalogPickerTarget) { target in
      catalogPicker(for: target)
    }
  }

  private var header: some View {
    HStack(alignment: .firstTextBaseline) {
      Text("Setlist")
        .font(.system(size: 30, weight: .bold, design: .rounded))
        .foregroundStyle(TunedInDesign.primaryText)
      Spacer()
      Text("\(draft.setlist.count)/50")
        .font(.caption.weight(.bold))
        .foregroundStyle(TunedInDesign.mutedText)
    }
    .padding(.horizontal, 20)
    .padding(.top, 16)
    .padding(.bottom, 8)
  }

  private var setlist: some View {
    List {
      ForEach(draft.setlist) { item in
        Button {
          catalogPickerTarget = .song(item.id)
        } label: {
          HStack(spacing: 12) {
            Image(systemName: "music.note")
              .foregroundStyle(TunedInDesign.accent)
              .frame(width: 22)
            Text(item.title)
              .font(.body.weight(.semibold))
              .foregroundStyle(TunedInDesign.primaryText)
              .lineLimit(2)
            Spacer()
            Image(systemName: "magnifyingglass")
              .font(.caption.weight(.semibold))
              .foregroundStyle(TunedInDesign.accent)
          }
          .padding(.vertical, 6)
          .contentShape(.interaction, Rectangle())
        }
        .buttonStyle(.plain)
        .swipeActions {
          Button(role: .destructive) {
            draft.removeSetlistItem(item.id)
          } label: {
            Label("Remove", systemImage: "trash")
          }
        }
        .listRowBackground(Color.clear)
      }
      .onMove { source, destination in
        draft.moveSetlist(from: source, to: destination)
      }

      if draft.setlist.count < 50 {
        Button {
          catalogPickerTarget = .song(nil)
        } label: {
          Label(
            draft.setlist.isEmpty ? "Search for the first song" : "Add another song",
            systemImage: "plus"
          )
          .font(.headline)
          .foregroundStyle(TunedInDesign.accent)
          .padding(.vertical, 8)
        }
        .listRowBackground(Color.clear)
      }
    }
    .listStyle(.plain)
    .contentMargins(.horizontal, 20, for: .scrollContent)
    .scrollContentBackground(.hidden)
    .background(TunedInDesign.pageBackground)
    .environment(\.editMode, .constant(.active))
  }

  private var setlistSummary: String {
    draft.setlist.isEmpty
      ? "Setlist"
      : "\(draft.setlist.count) \(draft.setlist.count == 1 ? "song" : "songs")"
  }

  @ViewBuilder
  private func catalogPicker(for target: ConcertCatalogPickerTarget) -> some View {
    switch target {
    case let .song(id):
      CatalogPickerView(
        repository: musicCatalogRepository,
        configuration: CatalogPickerConfiguration(
          kind: .song,
          title: id == nil ? "Add song" : "Replace song",
          artistContext: draft.selectedCatalogArtists,
          currentSelectionName: id.flatMap { selectedID in
            draft.setlist.first(where: { $0.id == selectedID })?.title
          },
          showsGuidance: false
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
    case .artist, .place, .tour:
      EmptyView()
    }
  }
}
