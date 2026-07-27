import Foundation
import Supabase

@MainActor
final class AppContainer {
  let appSession: AppSession
  let postRepository: any PostRepository
  let eventRepository: any EventRepository
  let musicCatalogRepository: any MusicCatalogRepository
  let ticketmasterDiscoveryRepository: any TicketmasterDiscoveryRepository
  let socialRepository: any SocialRepository
  let profileRepository: any ProfileRepository
  let telemetry: AppTelemetryClient
  let imageLoader: AppMediaCache

  private init(
    appSession: AppSession,
    postRepository: any PostRepository,
    eventRepository: any EventRepository,
    musicCatalogRepository: any MusicCatalogRepository,
    ticketmasterDiscoveryRepository: any TicketmasterDiscoveryRepository,
    socialRepository: any SocialRepository
  ) {
    self.appSession = appSession
    self.postRepository = postRepository
    self.eventRepository = eventRepository
    self.musicCatalogRepository = musicCatalogRepository
    self.ticketmasterDiscoveryRepository = ticketmasterDiscoveryRepository
    self.socialRepository = socialRepository
    telemetry = appSession.telemetry
    profileRepository = appSession.profileRepositoryForViews
    imageLoader = .ephemeral()
  }

  init(configuration: AppConfiguration) throws {
    let telemetry = AppTelemetryClient(
      configuration: configuration.telemetry,
      release: configuration.release
    )
    let client = Self.makeSupabaseClient(configuration: configuration)
    let caches = try Self.makeCaches(environment: configuration.environment)
    let mediaCache = caches.media
    let dataCache = caches.data
    let profileRepository = CachingProfileRepository(
      remote: SupabaseProfileRepository(
        client: client,
        signedURLs: mediaCache.signedURLs
      ),
      cache: dataCache
    )
    let feedbackRepository = SupabaseFeedbackRepository(client: client, release: configuration.release)
    appSession = AppSession(
      authenticationRepository: SupabaseAuthenticationRepository(
        client: client,
        authCallbackURL: configuration.authCallbackURL
      ),
      googleAuthenticationClient: LiveGoogleAuthenticationClient(),
      profileRepository: profileRepository,
      dataCache: dataCache,
      feedbackRepository: feedbackRepository,
      authEmailDeliveryMode: configuration.authEmailDeliveryMode,
      nativeSocialAuthConfiguration: configuration.nativeSocialAuthConfiguration,
      allowsLocalSeededSignIn: configuration.usesLocalSimulatorAuthStorage,
      telemetry: telemetry
    )
    postRepository = SupabasePostRepository(
      client: client,
      signedURLs: mediaCache.signedURLs
    )
    eventRepository = SupabaseEventRepository(client: client, signedURLs: mediaCache.signedURLs)
    musicCatalogRepository = SupabaseMusicCatalogRepository(client: client)
    ticketmasterDiscoveryRepository = SupabaseTicketmasterDiscoveryRepository(client: client)
    socialRepository = CachingSocialRepository(
      remote: SupabaseSocialRepository(client: client),
      cache: dataCache
    )
    self.profileRepository = profileRepository
    self.telemetry = telemetry
    imageLoader = mediaCache
  }

  private static func makeSupabaseClient(configuration: AppConfiguration) -> SupabaseClient {
    let authStorage: any AuthLocalStorage
    if configuration.usesLocalSimulatorAuthStorage {
      authStorage = LocalSimulatorAuthStorage()
    } else {
      #if targetEnvironment(simulator)
        if configuration.environment == .development {
          authStorage = DevelopmentSimulatorAuthStorage()
        } else {
          authStorage = AuthClient.Configuration.defaultLocalStorage
        }
      #else
        authStorage = AuthClient.Configuration.defaultLocalStorage
      #endif
    }
    return SupabaseClient(
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
  }

  private static func makeCaches(
    environment: AppEnvironment
  ) throws -> (data: AppDataCache, media: AppMediaCache) {
    let diagnostics = AppCacheDiagnostics()
    let mediaCache = try AppMediaCache.live(
      environment: environment,
      diagnostics: diagnostics
    )
    let dataCache = try AppDataCache.live(
      environment: environment,
      diagnostics: diagnostics,
      mediaCache: mediaCache
    )
    return (dataCache, mediaCache)
  }

  static func live() -> AppContainer {
    do {
      let configuration = try AppConfiguration.load()

      #if DEBUG
        if configuration.environment == .development {
          if let scenario = DevelopmentScenario.requested(), scenario != .live {
            let catalogRepository = DevelopmentMusicCatalogRepository()
            return AppContainer(
              appSession: scenario.makeAppSession(
                authEmailDeliveryMode: configuration.authEmailDeliveryMode,
                telemetry: AppTelemetryClient(
                  configuration: .recording,
                  release: configuration.release
                )
              ),
              postRepository: DevelopmentPostRepository(),
              eventRepository: DevelopmentEventRepository(),
              musicCatalogRepository: catalogRepository,
              ticketmasterDiscoveryRepository: DevelopmentTicketmasterDiscoveryRepository(),
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
