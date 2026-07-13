import Foundation

struct ProductFeedbackSubmission: Equatable, Sendable {
  let category: TelemetryFeedbackCategory
  let message: String
  let originatingScreen: String
}

protocol FeedbackRepository: Sendable {
  func submit(_ feedback: ProductFeedbackSubmission) async throws -> UUID
}

struct DevelopmentFeedbackRepository: FeedbackRepository {
  func submit(_: ProductFeedbackSubmission) async throws -> UUID {
    UUID()
  }
}
