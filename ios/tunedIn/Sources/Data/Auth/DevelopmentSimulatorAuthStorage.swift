import Foundation
import Supabase

/// Keeps normal hosted Development sessions available to an unsigned Simulator
/// build. Real devices continue to use the Keychain-backed default storage.
struct DevelopmentSimulatorAuthStorage: AuthLocalStorage, @unchecked Sendable {
  private let defaults = UserDefaults.standard
  private let prefix = "com.ethanherrera.tunedin.development-auth."

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
