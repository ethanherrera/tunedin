import SwiftUI

struct RootView: View {
  @Bindable var session: AppSession
  let postRepository: any PostRepository
  let eventRepository: any EventRepository
  let socialRepository: any SocialRepository

  var body: some View {
    Group {
      switch session.phase {
      case .restoring, .loadingProfile:
        ProgressView("Restoring your session…")
          .frame(maxWidth: .infinity, maxHeight: .infinity)

      case .signedOut:
        if session.nativeSocialAuthConfiguration != nil {
          NativeSocialSignInView(session: session)
        } else {
          EmailSignInView(session: session)
        }

      case let .profileUnavailable(_, message):
        ProfileLoadFailureView(session: session, message: message)

      case let .needsOnboarding(user):
        OnboardingView(session: session, user: user)

      case let .signedIn(user, profile):
        MainTabView(
          session: session,
          user: user,
          profile: profile,
          postRepository: postRepository,
          eventRepository: eventRepository,
          socialRepository: socialRepository
        )
      }
    }
    .alert(
      "Couldn’t sign in",
      isPresented: Binding(
        get: { session.authCallbackError != nil },
        set: { isPresented in
          if !isPresented {
            session.dismissAuthCallbackError()
          }
        }
      )
    ) {
      Button("OK") {
        session.dismissAuthCallbackError()
      }
    } message: {
      Text(session.authCallbackError ?? "The login link could not be verified.")
    }
    .tunedInKeyboardManaged()
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
