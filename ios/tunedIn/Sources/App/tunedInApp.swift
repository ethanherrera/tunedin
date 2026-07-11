import SwiftUI

@main
@MainActor
struct TunedInApp: App {
  @State private var session = AppContainer.live().appSession

  var body: some Scene {
    WindowGroup {
      RootView(session: session)
        .onOpenURL { url in
          session.handleAuthCallback(url)
        }
    }
  }
}
