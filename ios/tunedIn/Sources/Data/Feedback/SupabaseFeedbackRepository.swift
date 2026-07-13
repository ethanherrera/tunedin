import Foundation
import Supabase

struct SupabaseFeedbackRepository: FeedbackRepository {
  let client: SupabaseClient
  let release: ReleaseMetadata

  func submit(_ feedback: ProductFeedbackSubmission) async throws -> UUID {
    try await withAppFailure {
      let response: PostgrestResponse<UUID> = try await client
        .rpc(
          "submit_product_feedback",
          params: SubmitProductFeedbackParameters(
            category: feedback.category.rawValue,
            message: feedback.message,
            originatingScreen: feedback.originatingScreen,
            appEnvironment: release.environment.rawValue.lowercased(),
            releaseVersion: release.version,
            buildNumber: release.build,
            gitSHA: String(release.gitSHA.prefix(40)).lowercased()
          )
        )
        .execute()
      return response.value
    }
  }
}

private struct SubmitProductFeedbackParameters: Encodable, Sendable {
  let category: String
  let message: String
  let originatingScreen: String
  let appEnvironment: String
  let releaseVersion: String
  let buildNumber: String
  let gitSHA: String

  enum CodingKeys: String, CodingKey {
    case category = "p_category"
    case message = "p_message"
    case originatingScreen = "p_originating_screen"
    case appEnvironment = "p_app_environment"
    case releaseVersion = "p_release_version"
    case buildNumber = "p_build_number"
    case gitSHA = "p_git_sha"
  }
}
