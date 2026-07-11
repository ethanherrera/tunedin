import SwiftUI

struct FeedPlaceholderView: View {
  let onCreateConcert: () -> Void

  var body: some View {
    ContentUnavailableView {
      Label("Your feed is on its way", systemImage: "music.note.house")
    } description: {
      Text("Friend activity will appear here once shared concerts are available.")
    } actions: {
      Button("Log your first concert", action: onCreateConcert)
        .buttonStyle(.borderedProminent)
    }
    .navigationTitle("Feed")
  }
}
