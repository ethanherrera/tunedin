import Foundation

struct AlbumUploadBatchResult<Item: Sendable, Output> {
  let successes: [Output]
  let failures: [(item: Item, error: any Error)]
}

enum AlbumUploadBatchExecutor {
  @MainActor
  static func run<Item: Sendable, Output>(
    _ items: [Item],
    attempt: @MainActor (Item) async -> Result<Output, AlbumUploadAttemptError<Item>>,
    progress: @MainActor (_ completed: Int, _ total: Int) -> Void
  ) async -> AlbumUploadBatchResult<Item, Output> {
    var successes: [Output] = []
    var failures: [(item: Item, error: any Error)] = []

    for (index, item) in items.enumerated() {
      switch await attempt(item) {
      case let .success(output):
        successes.append(output)
      case let .failure(failure):
        failures.append((failure.item, failure.underlying))
      }
      progress(index + 1, items.count)
    }

    return AlbumUploadBatchResult(successes: successes, failures: failures)
  }
}

struct AlbumUploadAttemptError<Item: Sendable>: Error {
  let item: Item
  let underlying: any Error
}
