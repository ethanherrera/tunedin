extension AppSessionPhase {
  func replacingAuthenticatedUser(with user: AuthenticatedUser) -> AppSessionPhase {
    switch self {
    case .restoring, .signedOut:
      self
    case .loadingProfile:
      .loadingProfile(user)
    case let .profileUnavailable(_, message):
      .profileUnavailable(user, message)
    case .needsOnboarding:
      .needsOnboarding(user)
    case let .signedIn(_, profile):
      .signedIn(user, profile)
    }
  }
}
