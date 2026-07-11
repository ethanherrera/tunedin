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
  private var authStateTask: Task<Void, Never>?
  private var profileLoadTask: Task<Void, Never>?
  private var currentUser: AuthenticatedUser?
  private var profileLoadGeneration = 0

  let authEmailDeliveryMode: AuthEmailDeliveryMode
  private(set) var phase: AppSessionPhase = .restoring

  init(
    authenticationRepository: any AuthenticationRepository,
    profileRepository: any ProfileRepository,
    authEmailDeliveryMode: AuthEmailDeliveryMode = .oneTimeCode
  ) {
    self.authenticationRepository = authenticationRepository
    self.profileRepository = profileRepository
    self.authEmailDeliveryMode = authEmailDeliveryMode

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

  func verifyEmailOTP(email: String, code: String) async throws {
    try await authenticationRepository.verifyEmailOTP(email: email, code: code)
  }

  func checkUsernameAvailability(_ username: String) async throws -> Bool {
    try await profileRepository.isUsernameAvailable(username)
  }

  func completeOnboarding(username: String, displayName: String) async throws {
    guard let currentUser else {
      throw AppSessionError.missingAuthenticatedUser
    }

    let profile = try await profileRepository.completeOnboarding(
      username: username,
      displayName: displayName
    )
    phase = .signedIn(currentUser, profile)
  }

  func retryProfileLoad() {
    guard let currentUser else { return }
    loadProfile(for: currentUser)
  }

  func signOut() async {
    do {
      try await authenticationRepository.signOut()
    } catch {
      if currentUser == nil {
        phase = .signedOut
      }
    }
  }

  func handleAuthCallback(_ url: URL) {
    authenticationRepository.handleAuthCallback(url)
  }

  private func receiveAuthenticationChange(_ user: AuthenticatedUser?) {
    profileLoadTask?.cancel()
    profileLoadGeneration += 1
    currentUser = user

    guard let user else {
      phase = .signedOut
      return
    }

    loadProfile(for: user)
  }

  private func loadProfile(for user: AuthenticatedUser) {
    profileLoadTask?.cancel()
    profileLoadGeneration += 1
    let generation = profileLoadGeneration
    phase = .loadingProfile(user)

    profileLoadTask = Task { [weak self, profileRepository] in
      do {
        let profile = try await profileRepository.fetchProfile(for: user.id)
        guard !Task.isCancelled else { return }
        self?.apply(profile: profile, for: user, generation: generation)
      } catch {
        guard !Task.isCancelled else { return }
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

enum AppSessionError: LocalizedError {
  case missingAuthenticatedUser

  var errorDescription: String? {
    switch self {
    case .missingAuthenticatedUser:
      "Your sign-in session is no longer available. Please sign in again."
    }
  }
}
