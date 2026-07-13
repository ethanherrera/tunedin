import Foundation
import Observation

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
  private let authenticationRepository: any AuthenticationRepository
  private let profileRepository: any ProfileRepository
  private let feedbackRepository: any FeedbackRepository
  private var authStateTask: Task<Void, Never>?
  private var profileLoadTask: Task<Void, Never>?
  private var currentUser: AuthenticatedUser?
  private var profileLoadGeneration = 0
  private let clock = ContinuousClock()

  let authEmailDeliveryMode: AuthEmailDeliveryMode
  let allowsLocalSeededSignIn: Bool
  let telemetry: AppTelemetryClient
  private(set) var phase: AppSessionPhase = .restoring
  private(set) var authCallbackError: String?
  var profileRepositoryForViews: any ProfileRepository {
    profileRepository
  }

  init(
    authenticationRepository: any AuthenticationRepository,
    profileRepository: any ProfileRepository,
    feedbackRepository: any FeedbackRepository = DevelopmentFeedbackRepository(),
    authEmailDeliveryMode: AuthEmailDeliveryMode = .oneTimeCode,
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
    self.profileRepository = profileRepository
    self.feedbackRepository = feedbackRepository
    self.authEmailDeliveryMode = authEmailDeliveryMode
    self.allowsLocalSeededSignIn = allowsLocalSeededSignIn
    self.telemetry = telemetry

    authStateTask = Task { [weak self, authenticationRepository] in
      for await user in authenticationRepository.authenticationStateChanges {
        guard !Task.isCancelled else { return }
        self?.receiveAuthenticationChange(user)
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
    try await authenticationRepository.signInWithPassword(
      email: localAccount.email,
      password: LocalSeededAccount.password
    )
    captureAuthenticationSuccess(startedAt: startedAt)
  }

  func verifyEmailOTP(email: String, code: String) async throws {
    let startedAt = clock.now
    try await authenticationRepository.verifyEmailOTP(email: email, code: code)
    captureAuthenticationSuccess(startedAt: startedAt)
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

    let startedAt = clock.now
    let profile = try await profileRepository.completeOnboarding(
      username: username,
      displayName: displayName
    )
    phase = .signedIn(currentUser, profile)
    telemetry.capture(
      .profileSetupCompleted,
      properties: [.durationMilliseconds: .integer(startedAt.duration(to: clock.now).millisecondsValue)]
    )
  }

  func setAvatar(jpegData: Data) async throws {
    guard let currentUser else { throw AppSessionError.missingAuthenticatedUser }
    let profile = try await profileRepository.setAvatar(jpegData: jpegData, for: currentUser.id)
    phase = .signedIn(currentUser, profile)
  }

  func removeAvatar() async throws {
    guard let currentUser else { throw AppSessionError.missingAuthenticatedUser }
    do {
      let profile = try await profileRepository.removeAvatar(for: currentUser.id)
      phase = .signedIn(currentUser, profile)
    } catch let error as AvatarRemovalError {
      phase = .signedIn(currentUser, error.profile)
      throw error
    }
  }

  func retryProfileLoad() {
    guard let currentUser else { return }
    loadProfile(for: currentUser)
  }

  func signOut() async {
    do {
      try await authenticationRepository.signOut()
      receiveAuthenticationChange(nil)
    } catch {
      if currentUser == nil {
        phase = .signedOut
      }
    }
  }

  func handleAuthCallback(_ url: URL) {
    authCallbackError = nil
    let startedAt = clock.now
    Task { [weak self, authenticationRepository] in
      do {
        try await authenticationRepository.handleAuthCallback(url)
        self?.captureAuthenticationSuccess(startedAt: startedAt)
      } catch {
        self?.authCallbackError = error.localizedDescription
      }
    }
  }

  private func captureAuthenticationSuccess(startedAt: ContinuousClock.Instant) {
    telemetry.capture(
      .authenticationCompleted,
      properties: [
        .method: .string("email"),
        .outcome: .string(TelemetryOutcome.succeeded.rawValue),
        .durationMilliseconds: .integer(startedAt.duration(to: clock.now).millisecondsValue)
      ]
    )
  }

  func dismissAuthCallbackError() {
    authCallbackError = nil
  }

  private func receiveAuthenticationChange(_ user: AuthenticatedUser?) {
    profileLoadTask?.cancel()
    profileLoadGeneration += 1
    currentUser = user

    guard let user else {
      telemetry.reset()
      phase = .signedOut
      return
    }

    telemetry.identify(userID: user.id)
    loadProfile(for: user)
  }

  private func loadProfile(for user: AuthenticatedUser) {
    profileLoadTask?.cancel()
    profileLoadGeneration += 1
    let generation = profileLoadGeneration
    let startedAt = clock.now
    phase = .loadingProfile(user)

    profileLoadTask = Task { [weak self, profileRepository] in
      do {
        let profile = try await profileRepository.fetchProfile(for: user.id)
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
    guard generation == profileLoadGeneration, currentUser == user else { return }
    phase = profile.hasCompletedOnboarding ? .signedIn(user, profile) : .needsOnboarding(user)
  }

  private func showProfileLoadFailure(
    for user: AuthenticatedUser,
    generation: Int,
    error: Error
  ) {
    guard generation == profileLoadGeneration, currentUser == user else { return }
    phase = .profileUnavailable(user, error.localizedDescription)
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

  var errorDescription: String? {
    switch self {
    case .missingAuthenticatedUser:
      "Your sign-in session is no longer available. Please sign in again."
    case .localSeededSignInUnavailable:
      "Seeded account sign-in is available only for the disposable Local Supabase stack."
    }
  }
}
