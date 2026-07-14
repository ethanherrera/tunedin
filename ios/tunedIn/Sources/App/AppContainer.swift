import Foundation
import Supabase

@MainActor
final class AppContainer {
  let appSession: AppSession
  let concertRepository: any ConcertRepository
  let socialRepository: any SocialRepository
  let profileRepository: any ProfileRepository
  let telemetry: AppTelemetryClient

  private init(
    appSession: AppSession,
    concertRepository: any ConcertRepository,
    socialRepository: any SocialRepository
  ) {
    self.appSession = appSession
    self.concertRepository = concertRepository
    self.socialRepository = socialRepository
    telemetry = appSession.telemetry
    profileRepository = appSession.profileRepositoryForViews
  }

  init(configuration: AppConfiguration) throws {
    let telemetry = AppTelemetryClient(
      configuration: configuration.telemetry,
      release: configuration.release
    )
    let authStorage: any AuthLocalStorage = configuration.usesLocalSimulatorAuthStorage
      ? LocalSimulatorAuthStorage()
      : AuthClient.Configuration.defaultLocalStorage

    let client = SupabaseClient(
      supabaseURL: configuration.supabaseURL,
      supabaseKey: configuration.supabasePublishableKey,
      options: .init(
        auth: .init(
          storage: authStorage,
          redirectToURL: configuration.authCallbackURL,
          storageKey: configuration.authSessionStorageKey
        ),
        global: .init(session: AppNetworkSession.makeSession())
      )
    )

    let dataCache = try AppDataCache.live(environment: configuration.environment)
    let profileRepository = CachingProfileRepository(
      remote: SupabaseProfileRepository(client: client),
      cache: dataCache
    )
    let feedbackRepository = SupabaseFeedbackRepository(client: client, release: configuration.release)
    appSession = AppSession(
      authenticationRepository: SupabaseAuthenticationRepository(
        client: client,
        authCallbackURL: configuration.authCallbackURL
      ),
      profileRepository: profileRepository,
      dataCache: dataCache,
      feedbackRepository: feedbackRepository,
      authEmailDeliveryMode: configuration.authEmailDeliveryMode,
      nativeSocialAuthConfiguration: configuration.nativeSocialAuthConfiguration,
      allowsLocalSeededSignIn: configuration.usesLocalSimulatorAuthStorage,
      telemetry: telemetry
    )
    concertRepository = CachingConcertRepository(
      remote: SupabaseConcertRepository(client: client),
      cache: dataCache
    )
    socialRepository = CachingSocialRepository(
      remote: SupabaseSocialRepository(client: client),
      cache: dataCache
    )
    self.profileRepository = profileRepository
    self.telemetry = telemetry
  }

  static func live() -> AppContainer {
    do {
      let configuration = try AppConfiguration.load()

      #if DEBUG
        if configuration.environment == .development {
          if let scenario = DevelopmentScenario.requested(), scenario != .live {
            return AppContainer(
              appSession: scenario.makeAppSession(
                authEmailDeliveryMode: configuration.authEmailDeliveryMode,
                telemetry: AppTelemetryClient(
                  configuration: .recording,
                  release: configuration.release
                )
              ),
              concertRepository: DevelopmentConcertRepository(),
              socialRepository: DevelopmentSocialRepository()
            )
          }
        }
      #endif

      return try AppContainer(configuration: configuration)
    } catch {
      fatalError(error.localizedDescription)
    }
  }
}
