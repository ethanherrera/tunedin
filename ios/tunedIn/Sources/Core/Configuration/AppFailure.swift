import Foundation

enum AppFailure: Error, Equatable, LocalizedError, Sendable {
  case conflict
  case permissionDenied
  case rateLimited
  case offline
  case retryable
  case validation
  case unavailable
  case unexpected

  init(_ error: any Error) {
    if let failure = error as? AppFailure {
      self = failure
      return
    }

    let cocoaError = error as NSError
    if let networkFailure = Self.networkFailure(for: cocoaError) {
      self = networkFailure
      return
    }

    self = Self.failure(for: error.localizedDescription.lowercased())
  }

  var errorDescription: String? {
    switch self {
    case .conflict:
      "This changed somewhere else. Refresh it, then try again."
    case .permissionDenied:
      "You no longer have permission to do that."
    case .rateLimited:
      "Take a beat before trying that again."
    case .offline:
      "You’re offline. Reconnect, then try again."
    case .retryable:
      "The server didn’t respond. Please try again."
    case .validation:
      "A few details need another look."
    case .unavailable:
      "That is no longer available."
    case .unexpected:
      "Something didn’t load cleanly. Please try again."
    }
  }

  var allowsRetry: Bool {
    self == .offline || self == .retryable
  }

  private static func networkFailure(for error: NSError) -> AppFailure? {
    guard error.domain == NSURLErrorDomain else { return nil }

    switch URLError.Code(rawValue: error.code) {
    case .notConnectedToInternet, .dataNotAllowed, .internationalRoamingOff:
      return .offline
    case .timedOut, .networkConnectionLost, .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
      return .retryable
    default:
      return .unexpected
    }
  }

  private static func failure(for description: String) -> AppFailure {
    if description.contains(anyOf: ["40001", "changed elsewhere", "changed somewhere else", "stale"]) {
      return .conflict
    }
    if description.contains(anyOf: ["42501", "permission", "no longer have access"]) {
      return .permissionDenied
    }
    if description.contains(anyOf: ["429", "rate limit", "too many requests", "take a beat", "wait a moment"]) {
      return .rateLimited
    }
    if description.contains(anyOf: ["offline", "not connected to the internet"]) {
      return .offline
    }
    if description.contains(anyOf: ["timed out", "temporarily unavailable", "service unavailable", "bad gateway"]) {
      return .retryable
    }
    if description.contains(anyOf: ["22023", "required", "must be", "invalid"]) {
      return .validation
    }
    if description.contains(anyOf: ["no longer available", "not found", "404"]) {
      return .unavailable
    }
    return .unexpected
  }
}

extension Error {
  var appFailure: AppFailure {
    AppFailure(self)
  }
}

func withAppFailure<Value>(_ operation: () async throws -> Value) async throws -> Value {
  do {
    return try await operation()
  } catch {
    throw AppFailure(error)
  }
}

private extension String {
  func contains(anyOf candidates: [String]) -> Bool {
    candidates.contains(where: contains)
  }
}
