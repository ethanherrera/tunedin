import Foundation

protocol AuthenticationRepository: Sendable {
  var authenticationStateChanges: AsyncStream<AuthenticatedUser?> { get }

  func sendEmailOTP(to email: String) async throws
  func signInWithPassword(email: String, password: String) async throws
  func verifyEmailOTP(email: String, code: String) async throws
  func signIn(with credentials: NativeAuthCredentials) async throws -> AuthenticatedUser
  /// Ends only this installation's current session. It must not sign the account out on other devices.
  func signOut() async throws
  func handleAuthCallback(_ url: URL) async throws
}
