import SwiftUI

@main
@MainActor
struct TunedInApp: App {
  @State private var container = AppContainer.live()
  @AppStorage(TunedInAppearance.storageKey) private var appearanceRawValue = TunedInAppearance.light.rawValue

  private var appearance: TunedInAppearance {
    TunedInAppearance(rawValue: appearanceRawValue) ?? .system
  }

  var body: some Scene {
    WindowGroup {
      RootView(
        session: container.appSession,
        concertRepository: container.concertRepository,
        socialRepository: container.socialRepository
      )
      .environment(\.profileRepository, container.profileRepository)
      .tint(TunedInDesign.accent)
      .preferredColorScheme(appearance.colorScheme)
      .onOpenURL { url in
        container.appSession.handleAuthCallback(url)
      }
    }
  }
}
