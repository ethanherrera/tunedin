import SwiftUI

struct FoundationView: View {
  var body: some View {
    VStack(spacing: 12) {
      Image(systemName: "music.note.list")
        .font(.system(size: 40, weight: .semibold))
        .accessibilityHidden(true)

      Text(AppFoundation.title)
        .font(.largeTitle.bold())

      Text(AppFoundation.message)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
    }
    .padding(24)
    .accessibilityElement(children: .combine)
  }
}
