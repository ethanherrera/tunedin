import Foundation
import Supabase

@MainActor
final class AppContainer {
  let appSession: AppSession

  private init(appSession: AppSession) {
    self.appSession = appSession
  }

  init(configuration: AppConfiguration) {
    let client = SupabaseClient(
      supabaseURL: configuration.supabaseURL,
      supabaseKey: configuration.supabasePublishableKey,
      options: .init(
        auth: .init(
          redirectToURL: AppConfiguration.authCallbackURL,
          storageKey: "com.ethanherrera.tunedin.auth.session"
        )
      )
    )

    appSession = AppSession(
      authenticationRepository: SupabaseAuthenticationRepository(client: client),
      profileRepository: SupabaseProfileRepository(client: client),
      authEmailDeliveryMode: configuration.authEmailDeliveryMode
    )
  }

  static func live() -> AppContainer {
    do {
      let configuration = try AppConfiguration.load()

      #if DEBUG
        if configuration.environment == .development,
           let scenario = DevelopmentScenario.requested(),
           scenario != .live {
          return AppContainer(
            appSession: scenario.makeAppSession(
              authEmailDeliveryMode: configuration.authEmailDeliveryMode
            )
          )
        }
      #endif

      return AppContainer(configuration: configuration)
    } catch {
      fatalError(error.localizedDescription)
    }
  }
}
