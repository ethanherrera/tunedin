import GoogleSignIn
import SwiftUI

@main
@MainActor
struct TunedInApp: App {
  @State private var container = AppContainer.live()
  @AppStorage(TunedInAppearance.storageKey) private var appearanceRawValue = TunedInAppearance.defaultAppearance.rawValue

  private var appearance: TunedInAppearance {
    TunedInAppearance(rawValue: appearanceRawValue) ?? TunedInAppearance.defaultAppearance
  }

  var body: some Scene {
    WindowGroup {
      RootView(
        session: container.appSession,
        concertRepository: container.concertRepository,
        socialRepository: container.socialRepository
      )
      .environment(\.profileRepository, container.profileRepository)
      .environment(\.telemetry, container.telemetry)
      .tint(TunedInDesign.accent)
      .preferredColorScheme(appearance.colorScheme)
      .onOpenURL { url in
        if !GIDSignIn.sharedInstance.handle(url) {
          container.appSession.handleAuthCallback(url)
        }
      }
    }
  }
}
