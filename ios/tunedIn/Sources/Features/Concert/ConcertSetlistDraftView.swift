import SwiftUI

struct ConcertSetlistDraftView: View {
  @Binding var draft: ConcertDraft
  let idleSubtitle: String
  let onSelectSong: (UUID?) -> Void

  @State private var editMode: EditMode = .inactive

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      heading
      List {
        ForEach(Array(draft.setlist.enumerated()), id: \.element.id) { index, item in
          setlistRow(item, position: index + 1)
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
          onSelectSong(nil)
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
      .environment(\.editMode, $editMode)
    }
  }

  private var heading: some View {
    HStack(alignment: .top) {
      VStack(alignment: .leading, spacing: 4) {
        Text("Setlist")
          .font(.system(size: 30, weight: .bold, design: .rounded))
          .foregroundStyle(TunedInDesign.primaryText)
        Text(editMode.isEditing ? "Drag songs into the right order." : idleSubtitle)
          .font(.subheadline)
          .foregroundStyle(TunedInDesign.mutedText)
      }
      Spacer(minLength: 12)
      Button(editMode.isEditing ? "Done" : "Reorder") {
        withAnimation(.smooth(duration: 0.22, extraBounce: 0)) {
          editMode = editMode.isEditing ? .inactive : .active
        }
      }
      .font(.subheadline.weight(.bold))
      .disabled(draft.setlist.count < 2)
    }
    .padding(.horizontal, 20)
    .padding(.top, 10)
  }

  private func setlistRow(_ item: ConcertDraft.SetlistItem, position: Int) -> some View {
    HStack(spacing: 12) {
      Text("\(position)")
        .font(.caption.weight(.bold).monospacedDigit())
        .foregroundStyle(TunedInDesign.accent)
        .frame(width: 24, alignment: .leading)
      Button {
        onSelectSong(item.id)
      } label: {
        HStack {
          Text(item.title)
            .font(.body.weight(.medium))
            .foregroundStyle(TunedInDesign.primaryText)
          Spacer()
          if !editMode.isEditing {
            Image(systemName: "ellipsis")
              .foregroundStyle(TunedInDesign.mutedText)
          }
        }
        .contentShape(.interaction, Rectangle())
      }
      .buttonStyle(.plain)
      .disabled(editMode.isEditing)
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel("Track \(position), \(item.title)")
  }
}
