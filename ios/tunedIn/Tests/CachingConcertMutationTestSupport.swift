import Foundation
import Testing
@testable import tunedIn

enum ConcertMutationTestHarness {
  static func perform(
    _ scenario: ConcertMutationScenario,
    repository: CachingConcertRepository
  ) async throws {
    switch scenario {
    case .createConcert, .updateConcert, .setConcertPhoto, .removeConcertPhoto, .deleteConcert:
      try await performConcertMutation(scenario, repository: repository)
    case .reserveAlbumPhoto, .uploadAlbumPhoto, .updateAlbumCaption, .deleteAlbumPhoto:
      try await performAlbumMutation(scenario, repository: repository)
    case .tagCollaborator, .removeCollaborator, .transferOwnership:
      try await performCollaborationMutation(scenario, repository: repository)
    case .createComment, .updateComment, .deleteComment:
      try await performCommentMutation(scenario, repository: repository)
    }
  }

  static func assertReconciliation(
    _ scenario: ConcertMutationScenario,
    context: ConcertCacheTestContext
  ) async throws {
    switch scenario {
    case .createConcert, .updateConcert, .setConcertPhoto, .removeConcertPhoto,
         .tagCollaborator, .removeCollaborator, .transferOwnership, .deleteConcert:
      try await assertConcertMutation(scenario, context: context)
    case .reserveAlbumPhoto, .uploadAlbumPhoto, .updateAlbumCaption, .deleteAlbumPhoto:
      try await assertAlbumMutation(scenario, context: context)
    case .createComment, .updateComment, .deleteComment:
      try await assertCommentMutation(scenario, context: context)
    }
  }
}

extension ConcertMutationTestHarness {
  static func performConcertMutation(
    _ scenario: ConcertMutationScenario,
    repository: CachingConcertRepository
  ) async throws {
    switch scenario {
    case .createConcert:
      _ = try await repository.createPrivateConcert(ConcertCacheFixtures.creationInput)
    case .updateConcert:
      _ = try await repository.updateConcert(ConcertCacheFixtures.updateInput)
    case .setConcertPhoto:
      _ = try await repository.setConcertPhoto(Data(), concertID: ConcertCacheFixtures.concertID)
    case .removeConcertPhoto:
      _ = try await repository.removeConcertPhoto(concertID: ConcertCacheFixtures.concertID)
    case .deleteConcert:
      try await repository.deleteConcert(id: ConcertCacheFixtures.concertID)
    default:
      preconditionFailure("Expected a concert mutation")
    }
  }

  static func performAlbumMutation(
    _ scenario: ConcertMutationScenario,
    repository: CachingConcertRepository
  ) async throws {
    switch scenario {
    case .reserveAlbumPhoto:
      _ = try await repository.reserveAlbumPhoto(
        concertID: ConcertCacheFixtures.concertID,
        photoID: reservation.photoID
      )
    case .uploadAlbumPhoto:
      _ = try await repository.uploadReservedAlbumPhoto(Data(), reservation: reservation)
    case .updateAlbumCaption:
      _ = try await repository.updateAlbumPhotoCaption(
        photoID: ConcertCacheFixtures.photoID,
        caption: "Changed caption"
      )
    case .deleteAlbumPhoto:
      try await repository.deleteAlbumPhoto(
        photoID: ConcertCacheFixtures.photoID,
        concertID: ConcertCacheFixtures.concertID
      )
    default:
      preconditionFailure("Expected an album mutation")
    }
  }

  static func performCollaborationMutation(
    _ scenario: ConcertMutationScenario,
    repository: CachingConcertRepository
  ) async throws {
    switch scenario {
    case .tagCollaborator:
      _ = try await repository.tagCollaborator(
        concertID: ConcertCacheFixtures.concertID,
        profileID: ConcertCacheFixtures.profileID,
        expectedVersion: 1
      )
    case .removeCollaborator:
      _ = try await repository.removeCollaborator(
        concertID: ConcertCacheFixtures.concertID,
        profileID: ConcertCacheFixtures.profileID,
        expectedVersion: 1
      )
    case .transferOwnership:
      _ = try await repository.transferOwnership(
        concertID: ConcertCacheFixtures.concertID,
        newOwnerID: ConcertCacheFixtures.profileID,
        expectedVersion: 1
      )
    default:
      preconditionFailure("Expected a collaboration mutation")
    }
  }

  static func performCommentMutation(
    _ scenario: ConcertMutationScenario,
    repository: CachingConcertRepository
  ) async throws {
    switch scenario {
    case .createComment:
      _ = try await repository.createComment(
        concertID: ConcertCacheFixtures.concertID,
        body: "New comment"
      )
    case .updateComment:
      _ = try await repository.updateComment(
        commentID: ConcertCacheFixtures.commentID,
        body: "Changed comment"
      )
    case .deleteComment:
      try await repository.deleteComment(
        commentID: ConcertCacheFixtures.commentID,
        concertID: ConcertCacheFixtures.concertID
      )
    default:
      preconditionFailure("Expected a comment mutation")
    }
  }

  static var reservation: ConcertPhotoReservation {
    ConcertPhotoReservation(
      photoID: UUID(uuidString: "44000000-0000-0000-0000-000000000002")!,
      concertID: ConcertCacheFixtures.concertID,
      objectPath: "concerts/album/reserved.jpg",
      expiresAt: Date(timeIntervalSince1970: 1_000)
    )
  }
}

extension ConcertMutationTestHarness {
  static func assertConcertMutation(
    _ scenario: ConcertMutationScenario,
    context: ConcertCacheTestContext
  ) async throws {
    switch scenario {
    case .createConcert:
      await expectStates(context.cache, expected: .createdConcert)
    case .updateConcert, .setConcertPhoto, .removeConcertPhoto,
         .tagCollaborator, .removeCollaborator, .transferOwnership:
      await expectStates(context.cache, expected: .dependentReadsInvalidated)
      #expect(
        try await context.repository.fetchConcertDetail(
          id: ConcertCacheFixtures.concertID,
          viewerID: ConcertCacheFixtures.viewerID
        ).concert.version == 2
      )
      #expect(await context.remote.readCount(.detail) == 1)
    case .deleteConcert:
      await expectStates(context.cache, expected: .deletedConcert)
    default:
      preconditionFailure("Expected a concert mutation")
    }
  }

  static func assertAlbumMutation(
    _ scenario: ConcertMutationScenario,
    context: ConcertCacheTestContext
  ) async throws {
    switch scenario {
    case .reserveAlbumPhoto:
      await expectStates(context.cache, expected: .allFresh)
    case .uploadAlbumPhoto:
      try await assertUploadedAlbumPhoto(context)
    case .updateAlbumCaption:
      try await assertUpdatedAlbumCaption(context)
    case .deleteAlbumPhoto:
      try await assertDeletedAlbumPhoto(context)
    default:
      preconditionFailure("Expected an album mutation")
    }
  }

  static func assertUploadedAlbumPhoto(_ context: ConcertCacheTestContext) async throws {
    await expectStates(context.cache, expected: .dependentReadsInvalidated)
    let photos = try await context.repository.albumPhotos(
      concertID: ConcertCacheFixtures.concertID,
      cursor: nil
    )
    #expect(photos.first?.caption == "New photo")
    #expect(await context.remote.readCount(.album) == 1)
  }

  static func assertUpdatedAlbumCaption(_ context: ConcertCacheTestContext) async throws {
    await expectStates(context.cache, expected: .allFresh)
    let photos = try await context.repository.albumPhotos(
      concertID: ConcertCacheFixtures.concertID,
      cursor: nil
    )
    #expect(photos.first?.caption == "Changed caption")
    #expect(await context.remote.readCount(.album) == 1)
  }

  static func assertDeletedAlbumPhoto(_ context: ConcertCacheTestContext) async throws {
    await expectStates(context.cache, expected: .deletedAlbumPhoto)
    #expect(
      try await context.repository.albumPhotos(
        concertID: ConcertCacheFixtures.concertID,
        cursor: nil
      ).isEmpty
    )
    #expect(await context.remote.readCount(.album) == 1)
  }

  static func assertCommentMutation(
    _ scenario: ConcertMutationScenario,
    context: ConcertCacheTestContext
  ) async throws {
    await expectStates(context.cache, expected: .dependentReadsInvalidated)
    let comments = try await context.repository.comments(
      concertID: ConcertCacheFixtures.concertID,
      cursor: nil
    )
    switch scenario {
    case .createComment:
      #expect(comments.first?.body == "New comment")
    case .updateComment:
      #expect(comments.first?.body == "Changed comment")
    case .deleteComment:
      #expect(comments.first?.isDeleted == true)
      #expect(comments.first?.body == nil)
    default:
      preconditionFailure("Expected a comment mutation")
    }
    #expect(await context.remote.readCount(.comments) == 1)
  }
}

extension ConcertMutationTestHarness {
  static func expectStates(
    _ cache: AppDataCache,
    expected: ConcertCacheExpectedStates
  ) async {
    #expect(await ConcertCacheTestHarness.state(.activity, cache: cache) == expected.activity)
    #expect(await ConcertCacheTestHarness.state(.archive, cache: cache) == expected.archive)
    #expect(await ConcertCacheTestHarness.state(.detail, cache: cache) == expected.detail)
    #expect(await ConcertCacheTestHarness.state(.comments, cache: cache) == expected.comments)
    #expect(await ConcertCacheTestHarness.state(.album, cache: cache) == expected.album)
  }
}

struct ConcertCacheExpectedStates {
  let activity: AppCacheEntryState
  let archive: AppCacheEntryState
  let detail: AppCacheEntryState
  let comments: AppCacheEntryState
  let album: AppCacheEntryState

  static let allFresh = Self(
    activity: .fresh,
    archive: .fresh,
    detail: .fresh,
    comments: .fresh,
    album: .fresh
  )
  static let createdConcert = Self(
    activity: .invalidated,
    archive: .invalidated,
    detail: .fresh,
    comments: .fresh,
    album: .fresh
  )
  static let dependentReadsInvalidated = Self(
    activity: .invalidated,
    archive: .invalidated,
    detail: .invalidated,
    comments: .fresh,
    album: .fresh
  )
  static let deletedAlbumPhoto = Self(
    activity: .invalidated,
    archive: .fresh,
    detail: .fresh,
    comments: .fresh,
    album: .fresh
  )
  static let deletedConcert = Self(
    activity: .invalidated,
    archive: .invalidated,
    detail: .missing,
    comments: .missing,
    album: .missing
  )
}
