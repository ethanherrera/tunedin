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
  let allowsLocalSeededSignIn: Bool
  private(set) var phase: AppSessionPhase = .restoring
  var profileRepositoryForViews: any ProfileRepository {
    profileRepository
  }

  init(
    authenticationRepository: any AuthenticationRepository,
    profileRepository: any ProfileRepository,
    authEmailDeliveryMode: AuthEmailDeliveryMode = .oneTimeCode,
    allowsLocalSeededSignIn: Bool = false
  ) {
    self.authenticationRepository = authenticationRepository
    self.profileRepository = profileRepository
    self.authEmailDeliveryMode = authEmailDeliveryMode
    self.allowsLocalSeededSignIn = allowsLocalSeededSignIn

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

    try await authenticationRepository.signInWithPassword(
      email: localAccount.email,
      password: LocalSeededAccount.password
    )
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
