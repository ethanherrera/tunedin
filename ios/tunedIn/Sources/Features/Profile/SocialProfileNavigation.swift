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

private struct OpenSocialProfileKey: EnvironmentKey {
  static let defaultValue = OpenSocialProfileAction()
}

extension EnvironmentValues {
  var openSocialProfile: OpenSocialProfileAction {
    get { self[OpenSocialProfileKey.self] }
    set { self[OpenSocialProfileKey.self] = newValue }
  }
}

struct SocialProfileButton<Label: View>: View {
  let profile: SocialProfile
  @ViewBuilder let label: Label

  @Environment(\.openSocialProfile) private var openSocialProfile

  init(profile: SocialProfile, @ViewBuilder label: () -> Label) {
    self.profile = profile
    self.label = label()
  }

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

extension ConcertComment {
  var socialProfile: SocialProfile {
    SocialProfile(
      id: authorID,
      username: username,
      displayName: displayName,
      relationship: .friends
    )
  }
}
