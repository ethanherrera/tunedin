#if DEBUG
  import Foundation

  actor DevelopmentPostRepository: PostRepository {
    private var mediaByPost: [UUID: [PostMedia]] = [:]
    private var commentsByPost: [UUID: [PostComment]] = [:]

    func reserveMedia(postID: UUID, mediaID: UUID) async throws -> PostMediaReservation {
      PostMediaReservation(
        mediaID: mediaID,
        postID: postID,
        objectPath: "posts/\(postID.uuidString.lowercased())/media/\(mediaID.uuidString.lowercased()).jpg",
        expiresAt: .now.addingTimeInterval(3600)
      )
    }

    func uploadReservedMedia(
      _: Data,
      reservation: PostMediaReservation
    ) async throws -> PostMedia {
      let item = PostMedia(
        id: reservation.mediaID,
        postID: reservation.postID,
        uploaderID: DevelopmentSocialFixture.currentUserID,
        username: DevelopmentSocialFixture.currentProfile.username,
        displayName: DevelopmentSocialFixture.currentProfile.displayName,
        objectPath: reservation.objectPath,
        caption: nil,
        version: 1,
        attachedAt: .now
      )
      mediaByPost[reservation.postID, default: []].insert(item, at: 0)
      return item
    }

    func media(postID: UUID, cursor: PostMediaCursor?) async throws -> [PostMedia] {
      let items = mediaByPost[postID] ?? []
      guard let cursor else { return Array(items.prefix(30)) }
      return Array(items.drop(while: { $0.id != cursor.mediaID }).dropFirst().prefix(30))
    }

    nonisolated func mediaURL(
      mediaID _: UUID,
      objectPath _: String,
      version _: Int64
    ) async throws -> URL {
      throw AppFailure.unexpected
    }

    func comments(postID: UUID, cursor: PostCommentCursor?) async throws -> [PostComment] {
      let items = (commentsByPost[postID] ?? []).sorted {
        ($0.createdAt, $0.id.uuidString) > ($1.createdAt, $1.id.uuidString)
      }
      guard let cursor else { return Array(items.prefix(30)) }
      return Array(items.drop(while: { $0.id != cursor.commentID }).dropFirst().prefix(30))
    }

    func createComment(postID: UUID, body: String) async throws -> PostComment {
      guard let normalized = CatalogInput.optionalNormalizedText(body), normalized.count <= 1000 else {
        throw AppFailure.unexpected
      }
      let item = PostComment(
        id: UUID(),
        postID: postID,
        authorID: DevelopmentSocialFixture.currentUserID,
        username: DevelopmentSocialFixture.currentProfile.username,
        displayName: DevelopmentSocialFixture.currentProfile.displayName,
        body: normalized,
        createdAt: .now,
        updatedAt: .now,
        deletedAt: nil
      )
      commentsByPost[postID, default: []].insert(item, at: 0)
      return item
    }
  }
#endif
