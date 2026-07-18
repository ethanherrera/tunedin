import Foundation

enum TelemetryEvent: String, CaseIterable, Sendable {
  case appBecameUsable = "app_became_usable"
  case authenticationCompleted = "authentication_completed"
  case profileSetupCompleted = "profile_setup_completed"
  case friendRequestSent = "friend_request_sent"
  case friendRequestAccepted = "friend_request_accepted"
  case eventCreated = "event_created"
  case eventUpdated = "event_updated"
  case eventCommentCreated = "event_comment_created"
  case postCommentCreated = "post_comment_created"
  case photoUploadCompleted = "photo_upload_completed"
  case feedbackSubmitted = "feedback_submitted"
  case screenLoadCompleted = "screen_load_completed"
  case coreOperationCompleted = "core_operation_completed"
}

enum TelemetryProperty: String, CaseIterable, Sendable {
  case environment
  case releaseVersion = "release_version"
  case buildNumber = "build_number"
  case gitSHA = "git_sha"
  case osMajor = "os_major"
  case deviceClass = "device_class"
  case destination
  case method
  case firstSession = "first_session"
  case screen
  case operation
  case outcome
  case durationMilliseconds = "duration_ms"
  case failureCategory = "failure_category"
  case retryable
  case statusClass = "status_class"
  case attemptedCount = "attempted_count"
  case succeededCount = "succeeded_count"
  case partialSuccess = "partial_success"
  case retryUsed = "retry_used"
  case category
}

enum TelemetryValue: Equatable, Sendable {
  case string(String)
  case integer(Int)
  case double(Double)
  case boolean(Bool)

  var foundationValue: Any {
    switch self {
    case let .string(value): value
    case let .integer(value): value
    case let .double(value): value
    case let .boolean(value): value
    }
  }
}

enum TelemetryOutcome: String, Sendable {
  case succeeded
  case failed
  case partial
}

enum TelemetryLogLevel: String, Sendable {
  case warning
  case error
  case fatal
}

enum TelemetryLogMessage: String, CaseIterable, Sendable {
  case profileLoadFailed = "profile_load_failed"
  case eventLoadFailed = "event_load_failed"
  case postLoadFailed = "post_load_failed"
  case mutationFailed = "mutation_failed"
  case feedbackSubmissionFailed = "feedback_submission_failed"
  case nativeAuthenticationFailed = "native_authentication_failed"
}

enum TelemetryOperation: String, CaseIterable, Sendable {
  case authenticate
  case loadProfile = "load_profile"
  case createEvent = "create_event"
  case updateEvent = "update_event"
  case sendFriendRequest = "send_friend_request"
  case acceptFriendRequest = "accept_friend_request"
  case createEventComment = "create_event_comment"
  case createPostComment = "create_post_comment"
  case uploadPostMedia = "upload_post_media"
  case submitFeedback = "submit_feedback"
}

enum TelemetryScreen: String, CaseIterable, Sendable {
  case feed
  case eventDetail = "event_detail"
  case postDetail = "post_detail"
  case friends
  case profile
}

enum TelemetryFeedbackCategory: String, CaseIterable, Identifiable, Sendable {
  case bug
  case idea
  case other

  var id: String {
    rawValue
  }

  var title: String {
    switch self {
    case .bug: "Something is broken"
    case .idea: "I have an idea"
    case .other: "Something else"
    }
  }
}

enum TelemetryFailureCategory: String, Sendable {
  case conflict
  case permissionDenied = "permission_denied"
  case rateLimited = "rate_limited"
  case offline
  case retryable
  case validation
  case unavailable
  case unexpected

  init(_ failure: AppFailure) {
    switch failure {
    case .conflict: self = .conflict
    case .permissionDenied: self = .permissionDenied
    case .rateLimited: self = .rateLimited
    case .offline: self = .offline
    case .retryable: self = .retryable
    case .validation: self = .validation
    case .unavailable: self = .unavailable
    case .unexpected: self = .unexpected
    }
  }
}

struct TelemetryRecord: Identifiable, Equatable, Sendable {
  enum Kind: String, Sendable {
    case event
    case log
    case identity
    case consent
  }

  let id: UUID
  let date: Date
  let kind: Kind
  let name: String
  let properties: [TelemetryProperty: TelemetryValue]
}
