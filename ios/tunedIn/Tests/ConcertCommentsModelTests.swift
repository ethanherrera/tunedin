import Foundation
import Testing
@testable import tunedIn

@MainActor
struct ConcertCommentsModelTests {
  @Test
  func optimisticCommentPreservesBodyAcrossFailureAndRetry() throws {
    let model = ConcertCommentsModel(
      concertID: UUID(),
      concertRepository: DevelopmentConcertRepository()
    )

    let id = model.enqueueOptimisticComment(body: "The encore changed everything.")
    let posting = try #require(model.optimisticComments.first)
    #expect(posting.id == id)
    #expect(posting.body == "The encore changed everything.")
    #expect(posting.status == .posting)

    model.markOptimisticCommentFailed(id: id)
    #expect(model.optimisticComments.first?.status == .failed)
    #expect(model.optimisticComments.first?.body == posting.body)

    model.markOptimisticCommentPosting(id: id)
    #expect(model.optimisticComments.first?.status == .posting)
    #expect(model.optimisticComments.first?.body == posting.body)
  }
}
