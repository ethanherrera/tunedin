import SwiftUI

@main
@MainActor
struct TunedInApp: App {
  @State private var container = AppContainer.live()

  var body: some Scene {
    WindowGroup {
      RootView(
        session: container.appSession,
        concertRepository: container.concertRepository
      )
      .onOpenURL { url in
        container.appSession.handleAuthCallback(url)
      }
    }
  }
}
