import Foundation
import OSLog

enum AppCacheOutcome: String, CaseIterable, Sendable {
  case hit
  case miss
  case stale
  case invalidated
  case coalesced
  case network
  case eviction
  case decodeFailure = "decode-failure"
}

struct AppCacheDiagnosticsSnapshot: Equatable, Sendable {
  private let counts: [AppCacheOutcome: Int]

  init(counts: [AppCacheOutcome: Int]) {
    self.counts = counts
  }

  subscript(_ outcome: AppCacheOutcome) -> Int {
    counts[outcome, default: 0]
  }
}

actor AppCacheDiagnostics {
  #if DEBUG
    private static let logger = Logger(
      subsystem: "com.ethanherrera.tunedin",
      category: "cache"
    )
    private var counts: [AppCacheOutcome: Int] = [:]
  #endif

  func record(_ outcome: AppCacheOutcome, count: Int = 1) {
    #if DEBUG
      guard count > 0 else { return }
      counts[outcome, default: 0] += count
      Self.logger.debug("Cache outcome: \(outcome.rawValue, privacy: .public)")
    #endif
  }

  #if DEBUG
    func snapshot() -> AppCacheDiagnosticsSnapshot {
      AppCacheDiagnosticsSnapshot(counts: counts)
    }

    func reset() {
      counts.removeAll()
    }
  #endif
}
