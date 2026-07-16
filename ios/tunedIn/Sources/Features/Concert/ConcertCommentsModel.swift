import Foundation
import Observation

struct OptimisticConcertComment: Equatable, Identifiable {
  enum Status: Equatable {
    case posting
    case failed
  }

  let id: UUID
  let body: String
  let createdAt: Date
  var status: Status
}

@MainActor
@Observable
final class ConcertCommentsModel {
  var comments: [ConcertComment] = []
  private(set) var optimisticComments: [OptimisticConcertComment] = []
  private(set) var isLoading = true
  private(set) var isLoadingOlder = false
  private(set) var canLoadOlder = false
  private(set) var loadErrorMessage: String?

  private let concertID: UUID
  private let concertRepository: any ConcertRepository

  init(concertID: UUID, concertRepository: any ConcertRepository) {
    self.concertID = concertID
    self.concertRepository = concertRepository
  }

  func loadComments(policy: CacheReadPolicy = .automatic) async {
    loadErrorMessage = nil
    do {
      let loaded = try await concertRepository.comments(
        concertID: concertID,
        cursor: nil,
        policy: policy
      )
      comments = loaded
      canLoadOlder = loaded.count == 30
    } catch {
      let failure = AppFailure(error)
      if failure == .permissionDenied || failure == .unavailable {
        comments = []
        canLoadOlder = false
      }
      loadErrorMessage = error.localizedDescription
    }
    isLoading = false
  }

  func retryLoadComments() async {
    isLoading = true
    await loadComments(policy: .refresh)
  }

  func loadOlderComments() async {
    guard let oldestComment = comments.min(by: isOlderComment), !isLoadingOlder else { return }
    isLoadingOlder = true

    do {
      let loaded = try await concertRepository.comments(
        concertID: concertID,
        cursor: ConcertCommentCursor(createdAt: oldestComment.createdAt, commentID: oldestComment.id),
        policy: .networkOnly
      )
      let existingIDs = Set(comments.map(\.id))
      comments.append(contentsOf: loaded.filter { !existingIDs.contains($0.id) })
      canLoadOlder = loaded.count == 30
      loadErrorMessage = nil
    } catch {
      loadErrorMessage = error.localizedDescription
    }

    isLoadingOlder = false
  }

  @discardableResult
  func enqueueOptimisticComment(body: String) -> UUID {
    let id = UUID()
    optimisticComments.append(
      OptimisticConcertComment(
        id: id,
        body: body,
        createdAt: .now,
        status: .posting
      )
    )
    return id
  }

  func markOptimisticCommentPosting(id: UUID) {
    guard let index = optimisticComments.firstIndex(where: { $0.id == id }) else { return }
    optimisticComments[index].status = .posting
  }

  func markOptimisticCommentFailed(id: UUID) {
    guard let index = optimisticComments.firstIndex(where: { $0.id == id }) else { return }
    optimisticComments[index].status = .failed
  }

  func postOptimisticComment(id: UUID) async throws {
    guard let pending = optimisticComments.first(where: { $0.id == id }) else { return }

    do {
      let comment = try await concertRepository.createComment(
        concertID: concertID,
        body: pending.body
      )
      optimisticComments.removeAll { $0.id == id }
      comments.append(comment)
    } catch {
      markOptimisticCommentFailed(id: id)
      throw error
    }
  }

  private func isOlderComment(_ lhs: ConcertComment, _ rhs: ConcertComment) -> Bool {
    if lhs.createdAt == rhs.createdAt {
      return lhs.id.uuidString < rhs.id.uuidString
    }
    return lhs.createdAt < rhs.createdAt
  }
}
