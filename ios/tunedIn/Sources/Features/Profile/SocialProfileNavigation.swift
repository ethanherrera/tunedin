import SwiftUI

struct OpenSocialProfileAction {
  private let action: @MainActor (SocialProfile) -> Void

  init(action: @escaping @MainActor (SocialProfile) -> Void = { _ in }) {
    self.action = action
  }

  @MainActor
  func callAsFunction(_ profile: SocialProfile) {
    action(profile)
  }
}

extension EnvironmentValues {
  @Entry var openSocialProfile: OpenSocialProfileAction = .init()
}

struct SocialProfileButton<Label: View>: View {
  let profile: SocialProfile
  @ViewBuilder let label: Label

  @Environment(\.openSocialProfile) private var openSocialProfile

  var body: some View {
    Button {
      openSocialProfile(profile)
    } label: {
      label
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel("Open \(profile.displayName)’s profile")
  }
}

extension PostComment {
  var socialProfile: SocialProfile {
    SocialProfile(
      id: authorID,
      username: username,
      displayName: displayName,
      relationship: .friends
    )
  }
}
