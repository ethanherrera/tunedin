import Foundation
import Supabase

/// Used only by the disposable Local configuration. Command-line Simulator
/// builds are unsigned, so they cannot claim a Keychain access group.
// UserDefaults serializes its own access; this small adapter holds no mutable
// state beyond that system-owned store.
struct LocalSimulatorAuthStorage: AuthLocalStorage, @unchecked Sendable {
  private let defaults = UserDefaults.standard
  private let prefix = "com.ethanherrera.tunedin.local-auth."

  func store(key: String, value: Data) throws {
    defaults.set(value, forKey: namespaced(key))
  }

  func retrieve(key: String) throws -> Data? {
    defaults.data(forKey: namespaced(key))
  }

  func remove(key: String) throws {
    defaults.removeObject(forKey: namespaced(key))
  }

  private func namespaced(_ key: String) -> String {
    prefix + key
  }
}
