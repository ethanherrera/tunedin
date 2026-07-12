import Foundation

/// Synthetic Local-only users that sign in through regular Supabase password auth.
///
/// The shared password is intentionally not a secret: the accounts and Local
/// Supabase stack are disposable, and this type is reachable only when the app
/// configuration is constrained to a loopback Local stack.
enum LocalSeededAccount: String, CaseIterable, Identifiable, Sendable {
  case listener
  case morgan
  case ava
  case jules
  case riley
  case casey
  case sasha
  case theo
  case june
  case noah
  case blair
  case elena
  case quinn
  case marin
  case parker
  case newcomer

  static let password = "tunedIn-local-seeded-account"

  var id: String { rawValue }

  var email: String {
    "\(rawValue)@tunedin.local"
  }

  var displayName: String {
    switch self {
    case .listener: "Local Listener"
    case .morgan: "Morgan Moon"
    case .ava: "Ava Park"
    case .jules: "Jules River"
    case .riley: "Riley Santos"
    case .casey: "Casey Chen"
    case .sasha: "Sasha Lane"
    case .theo: "Theo Gray"
    case .june: "June Lee"
    case .noah: "Noah King"
    case .blair: "Blair Song"
    case .elena: "Elena Rose"
    case .quinn: "Quinn West"
    case .marin: "Marin Haze"
    case .parker: "Parker June"
    case .newcomer: "Newcomer"
    }
  }
}
