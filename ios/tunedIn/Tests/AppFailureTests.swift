import Foundation
import Testing
@testable import tunedIn

struct AppFailureTests {
  @Test
  func mapsNetworkAndDatabaseFailuresToStableCategories() {
    #expect(AppFailure(URLError(.notConnectedToInternet)) == .offline)
    #expect(AppFailure(URLError(.timedOut)) == .retryable)
    #expect(AppFailure(TestError("SQLSTATE 40001 changed elsewhere")) == .conflict)
    #expect(AppFailure(TestError("SQLSTATE 42501 permission denied")) == .permissionDenied)
    #expect(AppFailure(TestError("HTTP 429 too many requests")) == .rateLimited)
  }

  @Test
  func onlyTransientConnectivityFailuresOfferTheSameActionAgain() {
    #expect(AppFailure.offline.allowsRetry)
    #expect(AppFailure.retryable.allowsRetry)
    #expect(!AppFailure.permissionDenied.allowsRetry)
    #expect(!AppFailure.validation.allowsRetry)
  }
}

private struct TestError: LocalizedError {
  let message: String

  init(_ message: String) {
    self.message = message
  }

  var errorDescription: String? {
    message
  }
}
