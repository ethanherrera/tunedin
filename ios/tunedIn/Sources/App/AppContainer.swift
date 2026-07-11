import Foundation
import Supabase

@MainActor
final class AppContainer {
  let appSession: AppSession
  let concertRepository: any ConcertRepository

  private init(appSession: AppSession, concertRepository: any ConcertRepository) {
    self.appSession = appSession
    self.concertRepository = concertRepository
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
    concertRepository = SupabaseConcertRepository(client: client)
  }

  static func live() -> AppContainer {
    do {
      let configuration = try AppConfiguration.load()

      #if DEBUG
        if configuration.environment == .development {
          if let scenario = DevelopmentScenario.requested(), scenario != .live {
            return AppContainer(
              appSession: scenario.makeAppSession(
                authEmailDeliveryMode: configuration.authEmailDeliveryMode
              ),
              concertRepository: DevelopmentConcertRepository()
            )
          }
        }
      #endif

      return AppContainer(configuration: configuration)
    } catch {
      fatalError(error.localizedDescription)
    }
  }
}
