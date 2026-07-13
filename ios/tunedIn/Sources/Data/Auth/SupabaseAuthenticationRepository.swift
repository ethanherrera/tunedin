import Foundation
import Supabase

struct SupabaseAuthenticationRepository: AuthenticationRepository {
  let client: SupabaseClient

  var authenticationStateChanges: AsyncStream<AuthenticatedUser?> {
    AsyncStream { continuation in
      let task = Task {
        for await (event, session) in client.auth.authStateChanges {
          switch event {
          case .initialSession, .signedIn, .signedOut, .tokenRefreshed:
            continuation.yield(session.map(Self.authenticatedUser))
          default:
            break
          }
        }

        continuation.finish()
      }

      continuation.onTermination = { _ in
        task.cancel()
      }
    }
  }

  func sendEmailOTP(to email: String) async throws {
    try await client.auth.signInWithOTP(
      email: email,
      redirectTo: AppConfiguration.authCallbackURL
    )
  }

  func signInWithPassword(email: String, password: String) async throws {
    _ = try await client.auth.signIn(email: email, password: password)
  }

  func verifyEmailOTP(email: String, code: String) async throws {
    _ = try await client.auth.verifyOTP(email: email, token: code, type: .magiclink)
  }

  func signOut() async throws {
    try await client.auth.signOut()
  }

  func handleAuthCallback(_ url: URL) async throws {
    let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
    let tokenHash = components?.queryItems?.first(where: { $0.name == "token_hash" })?.value
    let type = components?.queryItems?.first(where: { $0.name == "type" })?.value

    if let tokenHash, type == "magiclink" {
      _ = try await client.auth.verifyOTP(tokenHash: tokenHash, type: .magiclink)
      return
    }

    _ = try await client.auth.session(from: url)
  }

  private static func authenticatedUser(from session: Session) -> AuthenticatedUser {
    AuthenticatedUser(id: session.user.id, email: session.user.email)
  }
}
