import SwiftUI

struct FeedPlaceholderView: View {
  var body: some View {
    ContentUnavailableView {
      Label("Your feed is on its way", systemImage: "music.note.house")
    } description: {
      Text("Friend activity will appear here once shared concerts are available.")
    }
    .navigationTitle("Feed")
  }
}
