import Foundation
import Observation
import OSLog

enum AppSessionPhase {
  case restoring
  case signedOut
  case loadingProfile(AuthenticatedUser)
  case profileUnavailable(AuthenticatedUser, String)
  case needsOnboarding(AuthenticatedUser)
  case signedIn(AuthenticatedUser, Profile)
}

@MainActor
@Observable
final class AppSession {
  private static let logger = Logger(subsystem: "com.ethanherrera.tunedin", category: "authentication")

  private let authenticationRepository: any AuthenticationRepository
  private let googleAuthenticationClient: any GoogleAuthenticationClient
  private let profileRepository: any ProfileRepository
  private let dataCache: AppDataCache?
  private let feedbackRepository: any FeedbackRepository
  private var authStateTask: Task<Void, Never>?
  private var profileLoadTask: Task<Void, Never>?
  private var signOutTask: Task<AppFailure?, Never>?
  private var currentUser: AuthenticatedUser?
  private var profileLoadGeneration = 0
  private var authenticationOperationGeneration = 0
  private var blocksAuthEventsAfterSignOut = false
  private var blockedSignedOutUserID: UUID?
  private var requiresInteractiveGoogleSignIn = false
  private let clock = ContinuousClock()

  let authEmailDeliveryMode: AuthEmailDeliveryMode
  let nativeSocialAuthConfiguration: NativeSocialAuthConfiguration?
  let allowsLocalSeededSignIn: Bool
  let telemetry: AppTelemetryClient
  private(set) var phase: AppSessionPhase = .restoring
  private(set) var authCallbackError: String?
  private(set) var lastSignOutFailure: AppFailure?
  var profileRepositoryForViews: any ProfileRepository {
    profileRepository
  }

  init(
    authenticationRepository: any AuthenticationRepository,
    googleAuthenticationClient: any GoogleAuthenticationClient = UnavailableGoogleAuthenticationClient(),
    profileRepository: any ProfileRepository,
    dataCache: AppDataCache? = nil,
    feedbackRepository: any FeedbackRepository = DevelopmentFeedbackRepository(),
    authEmailDeliveryMode: AuthEmailDeliveryMode = .oneTimeCode,
    nativeSocialAuthConfiguration: NativeSocialAuthConfiguration? = nil,
    allowsLocalSeededSignIn: Bool = false,
    telemetry: AppTelemetryClient = AppTelemetryClient(
      configuration: .recording,
      release: ReleaseMetadata(
        version: "test",
        build: "test",
        gitSHA: "test",
        environment: .development
      )
    )
  ) {
    self.authenticationRepository = authenticationRepository
    self.googleAuthenticationClient = googleAuthenticationClient
    self.profileRepository = profileRepository
    self.dataCache = dataCache
    self.feedbackRepository = feedbackRepository
    self.authEmailDeliveryMode = authEmailDeliveryMode
    self.nativeSocialAuthConfiguration = nativeSocialAuthConfiguration
    self.allowsLocalSeededSignIn = allowsLocalSeededSignIn
    self.telemetry = telemetry

    authStateTask = Task { [weak self, authenticationRepository] in
      for await user in authenticationRepository.authenticationStateChanges {
        guard !Task.isCancelled else { return }
        await self?.receiveAuthenticationChange(user)
      }
    }
  }

  func sendEmailOTP(to email: String) async throws {
    try await authenticationRepository.sendEmailOTP(to: email)
  }

  func signIn(to localAccount: LocalSeededAccount) async throws {
    guard allowsLocalSeededSignIn else {
      throw AppSessionError.localSeededSignInUnavailable
    }

    let startedAt = clock.now
    let attempt = await beginUserInitiatedAuthentication()
    do {
      try await authenticationRepository.signInWithPassword(
        email: localAccount.email,
        password: LocalSeededAccount.password
      )
    } catch {
      restoreAuthenticationBlockAfterFailedAttempt(attempt)
      throw error
    }
    try ensureCurrentAuthenticationOperation(attempt.generation)
    captureAuthenticationSuccess(method: "local_seed", startedAt: startedAt)
  }

  func verifyEmailOTP(email: String, code: String) async throws {
    let startedAt = clock.now
    let attempt = await beginUserInitiatedAuthentication()
    do {
      try await authenticationRepository.verifyEmailOTP(email: email, code: code)
    } catch {
      restoreAuthenticationBlockAfterFailedAttempt(attempt)
      throw error
    }
    try ensureCurrentAuthenticationOperation(attempt.generation)
    captureAuthenticationSuccess(method: "email", startedAt: startedAt)
  }

  func googleCredentials() async throws -> NativeAuthCredentials {
    guard let configuration = nativeSocialAuthConfiguration else {
      throw AppSessionError.nativeSocialSignInUnavailable
    }

    await waitForPendingSignOut()
    return try await googleAuthenticationClient.credentials(
      configuration: configuration,
      allowsPreviousSignInRestore: !requiresInteractiveGoogleSignIn
    )
  }

  func signIn(with credentials: NativeAuthCredentials) async throws {
    guard nativeSocialAuthConfiguration != nil else {
      throw AppSessionError.nativeSocialSignInUnavailable
    }

    let startedAt = clock.now
    await waitForPendingSignOut()
    authenticationOperationGeneration += 1
    let operationGeneration = authenticationOperationGeneration
    let wasBlockingAuthenticatedEvents = blocksAuthEventsAfterSignOut
    do {
      let user = try await authenticationRepository.signIn(with: credentials)
      try ensureCurrentAuthenticationOperation(operationGeneration)
      blocksAuthEventsAfterSignOut = false
      if blockedSignedOutUserID == user.id {
        blockedSignedOutUserID = nil
      }
      await receiveAuthenticationChange(user)
      if credentials.provider == .google {
        requiresInteractiveGoogleSignIn = false
      }
      captureAuthenticationSuccess(method: credentials.provider.rawValue, startedAt: startedAt)
    } catch {
      guard operationGeneration == authenticationOperationGeneration else {
        throw CancellationError()
      }
      if error is CancellationError {
        throw error
      }
      if wasBlockingAuthenticatedEvents {
        blocksAuthEventsAfterSignOut = true
      }
      let failure = AppFailure(error)
      recordNativeAuthenticationFailure(
        provider: credentials.provider,
        error: failure,
        statusClass: "backend_exchange",
        startedAt: startedAt
      )
      throw failure
    }
  }

  func checkUsernameAvailability(_ username: String) async throws -> Bool {
    try await profileRepository.isUsernameAvailable(username)
  }

  func submitFeedback(
    category: TelemetryFeedbackCategory,
    message: String,
    originatingScreen: String = "settings"
  ) async throws {
    let startedAt = clock.now
    do {
      _ = try await feedbackRepository.submit(
        ProductFeedbackSubmission(
          category: category,
          message: message,
          originatingScreen: originatingScreen
        )
      )
      telemetry.capture(
        .feedbackSubmitted,
        properties: [
          .category: .string(category.rawValue),
          .outcome: .string(TelemetryOutcome.succeeded.rawValue),
          .durationMilliseconds: .integer(startedAt.duration(to: clock.now).millisecondsValue)
        ]
      )
    } catch {
      let failure = AppFailure(error)
      if failure.shouldReportToTelemetry {
        telemetry.capture(
          .feedbackSubmitted,
          properties: [
            .category: .string(category.rawValue),
            .outcome: .string(TelemetryOutcome.failed.rawValue),
            .failureCategory: .string(TelemetryFailureCategory(failure).rawValue),
            .durationMilliseconds: .integer(startedAt.duration(to: clock.now).millisecondsValue)
          ]
        )
        telemetry.log(
          .error,
          message: .feedbackSubmissionFailed,
          properties: [
            .operation: .string(TelemetryOperation.submitFeedback.rawValue),
            .failureCategory: .string(TelemetryFailureCategory(failure).rawValue),
            .retryable: .boolean(failure.allowsRetry)
          ]
        )
      }
      throw failure
    }
  }

  func completeOnboarding(username: String, displayName: String) async throws {
    guard let currentUser else {
      throw AppSessionError.missingAuthenticatedUser
    }
    let operationGeneration = authenticationOperationGeneration

    let startedAt = clock.now
    let profile = try await profileRepository.completeOnboarding(
      username: username,
      displayName: displayName
    )
    let authenticatedUser = try authenticatedUser(
      matching: currentUser,
      operationGeneration: operationGeneration
    )
    phase = .signedIn(authenticatedUser, profile)
    telemetry.capture(
      .profileSetupCompleted,
      properties: [.durationMilliseconds: .integer(startedAt.duration(to: clock.now).millisecondsValue)]
    )
  }

  func setAvatar(jpegData: Data) async throws {
    guard let currentUser else { throw AppSessionError.missingAuthenticatedUser }
    let operationGeneration = authenticationOperationGeneration
    let profile = try await profileRepository.setAvatar(jpegData: jpegData, for: currentUser.id)
    let authenticatedUser = try authenticatedUser(
      matching: currentUser,
      operationGeneration: operationGeneration
    )
    phase = .signedIn(authenticatedUser, profile)
  }

  func removeAvatar() async throws {
    guard let currentUser else { throw AppSessionError.missingAuthenticatedUser }
    let operationGeneration = authenticationOperationGeneration
    do {
      let profile = try await profileRepository.removeAvatar(for: currentUser.id)
      let authenticatedUser = try authenticatedUser(
        matching: currentUser,
        operationGeneration: operationGeneration
      )
      phase = .signedIn(authenticatedUser, profile)
    } catch let error as AvatarRemovalError {
      let authenticatedUser = try authenticatedUser(
        matching: currentUser,
        operationGeneration: operationGeneration
      )
      phase = .signedIn(authenticatedUser, error.profile)
      throw error
    }
  }

  private func authenticatedUser(
    matching expectedUser: AuthenticatedUser,
    operationGeneration: Int
  ) throws -> AuthenticatedUser {
    try Task.checkCancellation()
    try ensureCurrentAuthenticationOperation(operationGeneration)
    guard let currentUser, currentUser.id == expectedUser.id else {
      throw CancellationError()
    }
    return currentUser
  }

  func retryProfileLoad() {
    guard let currentUser else { return }
    loadProfile(for: currentUser, policy: .refresh)
  }

  func refreshProfile() async throws {
    guard let user = currentUser else {
      throw AppSessionError.missingAuthenticatedUser
    }

    let profile = try await profileRepository.fetchProfile(for: user.id, policy: .refresh)
    guard let currentUser, currentUser.id == user.id else { return }
    phase = profile.hasCompletedOnboarding ? .signedIn(currentUser, profile) : .needsOnboarding(currentUser)
  }

  private func loadProfile(for user: AuthenticatedUser, policy: CacheReadPolicy = .automatic) {
    profileLoadTask?.cancel()
    profileLoadGeneration += 1
    let generation = profileLoadGeneration
    let startedAt = clock.now
    phase = .loadingProfile(user)

    profileLoadTask = Task { [weak self, profileRepository] in
      do {
        let profile = try await profileRepository.fetchProfile(for: user.id, policy: policy)
        guard !Task.isCancelled else { return }
        self?.telemetry.captureOperation(
          .loadProfile,
          outcome: .succeeded,
          duration: startedAt.duration(to: self?.clock.now ?? startedAt)
        )
        self?.apply(profile: profile, for: user, generation: generation)
      } catch {
        guard !Task.isCancelled else { return }
        let failure = AppFailure(error)
        if failure.shouldReportToTelemetry {
          self?.telemetry.captureOperation(
            .loadProfile,
            outcome: .failed,
            duration: startedAt.duration(to: self?.clock.now ?? startedAt),
            failure: failure
          )
          self?.telemetry.log(
            .error,
            message: .profileLoadFailed,
            properties: [
              .operation: .string(TelemetryOperation.loadProfile.rawValue),
              .failureCategory: .string(TelemetryFailureCategory(failure).rawValue),
              .retryable: .boolean(failure.allowsRetry)
            ]
          )
        }
        self?.showProfileLoadFailure(for: user, generation: generation, error: error)
      }
    }
  }

  private func apply(profile: Profile, for user: AuthenticatedUser, generation: Int) {
    guard generation == profileLoadGeneration, let currentUser, currentUser.id == user.id else { return }
    phase = profile.hasCompletedOnboarding ? .signedIn(currentUser, profile) : .needsOnboarding(currentUser)
  }

  private func showProfileLoadFailure(for user: AuthenticatedUser, generation: Int, error: Error) {
    guard generation == profileLoadGeneration, let currentUser, currentUser.id == user.id else { return }
    phase = .profileUnavailable(currentUser, error.localizedDescription)
  }
}

extension AppSession {
  func signOut() async {
    if let signOutTask {
      _ = await signOutTask.value
      return
    }

    authenticationOperationGeneration += 1
    blocksAuthEventsAfterSignOut = true
    blockedSignedOutUserID = currentUser?.id
    requiresInteractiveGoogleSignIn = true
    lastSignOutFailure = nil
    googleAuthenticationClient.signOut()
    applyImmediateSignedOutState()

    let authenticationRepository = authenticationRepository
    let dataCache = dataCache
    let cleanupTask = Task<AppFailure?, Never> {
      let cacheTask = Task<Void, Never> {
        guard let dataCache else { return }
        await dataCache.transition(to: nil)
      }

      let failure: AppFailure?
      do {
        try await authenticationRepository.signOut()
        failure = nil
      } catch {
        failure = AppFailure(error)
      }

      await cacheTask.value
      return failure
    }
    signOutTask = cleanupTask

    let failure = await cleanupTask.value
    lastSignOutFailure = failure
    if let failure {
      Self.logger.warning(
        "Remote current-session sign-out cleanup failed: \(String(describing: failure), privacy: .public)"
      )
    }
    signOutTask = nil
  }

  func handleAuthCallback(_ url: URL) {
    authCallbackError = nil
    let startedAt = clock.now
    Task { [weak self, authenticationRepository] in
      guard let self else { return }
      let attempt = await beginUserInitiatedAuthentication()
      do {
        try await authenticationRepository.handleAuthCallback(url)
        try ensureCurrentAuthenticationOperation(attempt.generation)
        captureAuthenticationSuccess(method: "email", startedAt: startedAt)
      } catch {
        guard attempt.generation == authenticationOperationGeneration else { return }
        restoreAuthenticationBlockAfterFailedAttempt(attempt)
        authCallbackError = error.localizedDescription
      }
    }
  }

  func dismissAuthCallbackError() {
    authCallbackError = nil
  }

  private func captureAuthenticationSuccess(method: String, startedAt: ContinuousClock.Instant) {
    telemetry.capture(
      .authenticationCompleted,
      properties: [
        .method: .string(method),
        .outcome: .string(TelemetryOutcome.succeeded.rawValue),
        .durationMilliseconds: .integer(startedAt.duration(to: clock.now).millisecondsValue)
      ]
    )
  }

  private func receiveAuthenticationChange(_ user: AuthenticatedUser?) async {
    if let user, user.id == blockedSignedOutUserID {
      return
    }
    if user != nil, blocksAuthEventsAfterSignOut {
      return
    }
    if user == nil, currentUser == nil, case .signedOut = phase {
      return
    }

    let previousUserID = currentUser?.id
    if let user, previousUserID == user.id {
      currentUser = user
      phase = phase.replacingAuthenticatedUser(with: user)
      return
    }

    profileLoadTask?.cancel()
    profileLoadGeneration += 1
    currentUser = user
    await dataCache?.transition(to: user?.id)

    guard let user else {
      telemetry.reset()
      phase = .signedOut
      return
    }

    telemetry.identify(userID: user.id)
    loadProfile(for: user)
  }

  private func applyImmediateSignedOutState() {
    profileLoadTask?.cancel()
    profileLoadGeneration += 1
    currentUser = nil
    telemetry.reset()
    phase = .signedOut
  }

  private func waitForPendingSignOut() async {
    if let signOutTask {
      _ = await signOutTask.value
    }
  }

  private struct AuthenticationAttempt {
    let generation: Int
    let wasBlockingAuthenticatedEvents: Bool
  }

  private func beginUserInitiatedAuthentication() async -> AuthenticationAttempt {
    await waitForPendingSignOut()
    authenticationOperationGeneration += 1
    let wasBlockingAuthenticatedEvents = blocksAuthEventsAfterSignOut
    blocksAuthEventsAfterSignOut = false
    blockedSignedOutUserID = nil
    return AuthenticationAttempt(
      generation: authenticationOperationGeneration,
      wasBlockingAuthenticatedEvents: wasBlockingAuthenticatedEvents
    )
  }

  private func restoreAuthenticationBlockAfterFailedAttempt(_ attempt: AuthenticationAttempt) {
    guard attempt.generation == authenticationOperationGeneration else { return }
    if attempt.wasBlockingAuthenticatedEvents {
      blocksAuthEventsAfterSignOut = true
    }
  }

  private func ensureCurrentAuthenticationOperation(_ generation: Int) throws {
    guard generation == authenticationOperationGeneration else {
      throw CancellationError()
    }
  }

  func recordNativeAuthenticationFailure(
    provider: NativeAuthProvider,
    error: any Error,
    statusClass: String,
    startedAt: ContinuousClock.Instant? = nil
  ) {
    let failure = AppFailure(error)
    guard failure.shouldReportToTelemetry else { return }

    var properties: [TelemetryProperty: TelemetryValue] = [
      .method: .string(provider.rawValue),
      .outcome: .string(TelemetryOutcome.failed.rawValue),
      .failureCategory: .string(TelemetryFailureCategory(failure).rawValue),
      .retryable: .boolean(failure.allowsRetry),
      .statusClass: .string(statusClass)
    ]
    if let startedAt {
      properties[.durationMilliseconds] = .integer(startedAt.duration(to: clock.now).millisecondsValue)
    }
    telemetry.capture(.authenticationCompleted, properties: properties)
    telemetry.log(
      .error,
      message: .nativeAuthenticationFailed,
      properties: [
        .operation: .string(TelemetryOperation.authenticate.rawValue),
        .method: .string(provider.rawValue),
        .failureCategory: .string(TelemetryFailureCategory(failure).rawValue),
        .retryable: .boolean(failure.allowsRetry),
        .statusClass: .string(statusClass)
      ]
    )
  }
}

private extension Duration {
  var millisecondsValue: Int {
    let components = components
    return Int(components.seconds * 1000 + components.attoseconds / 1_000_000_000_000_000)
  }
}

extension AppFailure {
  var shouldReportToTelemetry: Bool {
    switch self {
    case .conflict, .rateLimited, .retryable, .unavailable, .unexpected:
      true
    case .permissionDenied, .offline, .validation:
      false
    }
  }
}

enum AppSessionError: LocalizedError {
  case missingAuthenticatedUser
  case localSeededSignInUnavailable
  case nativeSocialSignInUnavailable

  var errorDescription: String? {
    switch self {
    case .missingAuthenticatedUser:
      "Your sign-in session is no longer available. Please sign in again."
    case .localSeededSignInUnavailable:
      "Seeded account sign-in is available only for the disposable Local Supabase stack."
    case .nativeSocialSignInUnavailable:
      "Apple and Google sign-in are unavailable in this build."
    }
  }
}
