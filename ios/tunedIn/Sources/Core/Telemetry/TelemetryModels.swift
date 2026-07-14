import Foundation

enum TelemetryEvent: String, CaseIterable, Sendable {
  case appBecameUsable = "app_became_usable"
  case authenticationCompleted = "authentication_completed"
  case profileSetupCompleted = "profile_setup_completed"
  case friendRequestSent = "friend_request_sent"
  case friendRequestAccepted = "friend_request_accepted"
  case collaboratorAdded = "collaborator_added"
  case concertCreated = "concert_created"
  case concertUpdated = "concert_updated"
  case commentCreated = "comment_created"
  case photoUploadCompleted = "photo_upload_completed"
  case ownershipTransferred = "ownership_transferred"
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
  case changeKind = "change_kind"
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
  case concertLoadFailed = "concert_load_failed"
  case albumLoadFailed = "album_load_failed"
  case mutationFailed = "mutation_failed"
  case feedbackSubmissionFailed = "feedback_submission_failed"
  case nativeAuthenticationFailed = "native_authentication_failed"
}

enum TelemetryOperation: String, CaseIterable, Sendable {
  case authenticate
  case loadProfile = "load_profile"
  case createConcert = "create_concert"
  case updateConcert = "update_concert"
  case sendFriendRequest = "send_friend_request"
  case acceptFriendRequest = "accept_friend_request"
  case addCollaborator = "add_collaborator"
  case createComment = "create_comment"
  case uploadPhotos = "upload_photos"
  case transferOwnership = "transfer_ownership"
  case submitFeedback = "submit_feedback"
}

enum TelemetryScreen: String, CaseIterable, Sendable {
  case feed
  case concertDetail = "concert_detail"
  case archive
  case album
  case friends
  case profile
}

enum TelemetryChangeKind: String, CaseIterable, Sendable {
  case details
  case setlist
  case sharing
  case membership
  case mainPhoto = "main_photo"
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
