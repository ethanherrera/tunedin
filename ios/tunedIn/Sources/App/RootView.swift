import SwiftUI

struct RootView: View {
  @Bindable var session: AppSession
  let concertRepository: any ConcertRepository

  var body: some View {
    switch session.phase {
    case .restoring, .loadingProfile:
      ProgressView("Restoring your session…")
        .frame(maxWidth: .infinity, maxHeight: .infinity)

    case .signedOut:
      EmailSignInView(session: session)

    case let .profileUnavailable(_, message):
      ProfileLoadFailureView(session: session, message: message)

    case let .needsOnboarding(user):
      OnboardingView(session: session, user: user)

    case let .signedIn(user, profile):
      MainTabView(
        session: session,
        user: user,
        profile: profile,
        concertRepository: concertRepository
      )
    }
  }
}

private struct ProfileLoadFailureView: View {
  let session: AppSession
  let message: String

  var body: some View {
    ContentUnavailableView {
      Label("We couldn’t load your profile", systemImage: "person.crop.circle.badge.exclamationmark")
    } description: {
      Text(message)
    } actions: {
      Button("Try Again") {
        session.retryProfileLoad()
      }

      Button("Sign Out", role: .destructive) {
        Task {
          await session.signOut()
        }
      }
    }
  }
}
