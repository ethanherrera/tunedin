import Foundation
import Testing
@testable import tunedIn
import UIKit

struct AlbumReadinessTests {
  @Test
  func networkSessionUsesBoundedRequestAndResourceTimeouts() {
    let configuration = AppNetworkSession.makeConfiguration()

    #expect(configuration.timeoutIntervalForRequest == 30)
    #expect(configuration.timeoutIntervalForResource == 60)
    #expect(configuration.waitsForConnectivity == false)
    #expect(configuration.requestCachePolicy == .reloadIgnoringLocalCacheData)
    #expect(configuration.urlCache == nil)

    let mediaConfiguration = AppNetworkSession.makeMediaConfiguration()
    #expect(mediaConfiguration.urlCache == nil)
    #expect(mediaConfiguration.httpCookieStorage == nil)
    #expect(mediaConfiguration.httpShouldSetCookies == false)
  }

  @MainActor
  @Test
  func pickerLimitComesFromAlbumPolicy() {
    let controls = ConcertFloatingControls()
    let policy = ConcertAlbumPolicy(
      policyVersion: 2,
      concertPhotoLimit: 80,
      contributorPhotoLimit: 20,
      reservationLimit24Hours: 8,
      pickerBatchLimit: 7,
      captionCharacterLimit: 240,
      attachedFileByteLimit: 1_500_000,
      pendingReservationLifetimeSeconds: 1_800
    )

    #expect(controls.albumPickerLimit == nil)
    controls.setAlbumPolicy(policy)
    #expect(controls.albumPickerLimit == 7)
  }

  @Test
  func albumProcessorPreservesAspectRatioWithinEdgeAndByteLimits() async throws {
    let image = UIGraphicsImageRenderer(size: CGSize(width: 4_000, height: 2_000)).image { context in
      UIColor.systemOrange.setFill()
      context.fill(CGRect(x: 0, y: 0, width: 4_000, height: 2_000))
    }

    let encoded = try await ConcertAlbumImageProcessor.process(#require(image.pngData()))
    let decoded = try #require(UIImage(data: encoded))

    #expect(decoded.size == CGSize(width: 2_048, height: 1_024))
    #expect(encoded.count <= 2_097_152)
  }

  @MainActor
  @Test
  func batchExecutorIsSequentialAndKeepsPartialSuccess() async {
    var order: [String] = []
    var progress: [Int] = []

    let result: AlbumUploadBatchResult<Int, String> = await AlbumUploadBatchExecutor.run([1, 2, 3]) { item in
      order.append("start-\(item)")
      await Task.yield()
      order.append("finish-\(item)")
      if item == 2 {
        return .failure(AlbumUploadAttemptError(item: item, underlying: TestUploadError.failed))
      }
      return .success("photo-\(item)")
    } progress: { completed, _ in
      progress.append(completed)
    }

    #expect(order == ["start-1", "finish-1", "start-2", "finish-2", "start-3", "finish-3"])
    #expect(result.successes == ["photo-1", "photo-3"])
    #expect(result.failures.map { $0.item } == [2])
    #expect(progress == [1, 2, 3])
  }

  @Test
  func uploadPhaseKeepsFailureRetryableAtTheThumbnail() {
    let preparing = AlbumUploadPhase.preparing
    let uploading = AlbumUploadPhase.uploading
    let failed = AlbumUploadPhase.failed("Your photo is still here.")

    #expect(preparing.isActive)
    #expect(uploading.isActive)
    #expect(!failed.isActive)
    #expect(failed.canRetry)
    #expect(!uploading.canRetry)
  }
}

private enum TestUploadError: Error {
  case failed
}
