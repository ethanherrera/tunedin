import Foundation
import Supabase

@MainActor
final class AppContainer {
  let appSession: AppSession

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
      return try AppContainer(configuration: .load())
    } catch {
      fatalError(error.localizedDescription)
    }
  }
}
