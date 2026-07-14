import Foundation
@testable import tunedIn

enum ConcertCacheFixtures {
  static let viewerID = UUID(uuidString: "40000000-0000-0000-0000-000000000001")!
  static let otherViewerID = UUID(uuidString: "40000000-0000-0000-0000-000000000002")!
  static let concertID = UUID(uuidString: "41000000-0000-0000-0000-000000000001")!
  static let profileID = UUID(uuidString: "42000000-0000-0000-0000-000000000001")!
  static let commentID = UUID(uuidString: "43000000-0000-0000-0000-000000000001")!
  static let photoID = UUID(uuidString: "44000000-0000-0000-0000-000000000001")!

  static let query = ConcertHistoryQuery(
    searchText: "mitski",
    year: nil,
    visibility: nil,
    sort: .newest
  )

  static func concert(version: Int64 = 1) -> Concert {
    Concert(
      id: concertID,
      ownerID: viewerID,
      venueName: version == 1 ? "The Greek" : "The Greek Theatre",
      city: "Los Angeles",
      concertDate: "2026-06-01",
      startsAt: nil,
      venueTimeZone: "America/Los_Angeles",
      tour: nil,
      visibility: .friends,
      createdAt: Date(timeIntervalSince1970: 100),
      updatedAt: Date(timeIntervalSince1970: TimeInterval(100 + version)),
      lastActivityAt: Date(timeIntervalSince1970: TimeInterval(100 + version)),
      version: version
    )
  }

  static func detail(version: Int64 = 1) -> ConcertDetail {
    ConcertDetail(
      concert: concert(version: version),
      artists: [
        ConcertArtist(
          id: UUID(uuidString: "45000000-0000-0000-0000-000000000001")!,
          name: "Mitski",
          lineupPosition: 0,
          isPrimary: true
        )
      ],
      setlist: [],
      history: [],
      collaborators: []
    )
  }

  static func preview(version: Int64 = 1) -> ConcertPreview {
    ConcertPreview(concert: concert(version: version), primaryArtistName: "Mitski")
  }

  static func comment(
    id: UUID = commentID,
    body: String = "Perfect night"
  ) -> ConcertComment {
    ConcertComment(
      id: id,
      concertID: concertID,
      authorID: viewerID,
      username: "listener",
      displayName: "Listener",
      body: body,
      createdAt: Date(timeIntervalSince1970: 200),
      updatedAt: Date(timeIntervalSince1970: 200),
      deletedAt: nil
    )
  }

  static func photo(
    id: UUID = photoID,
    caption: String? = "Encore",
    version: Int64 = 1
  ) -> ConcertAlbumPhoto {
    ConcertAlbumPhoto(
      id: id,
      concertID: concertID,
      uploaderID: viewerID,
      username: "listener",
      displayName: "Listener",
      objectPath: "concerts/album/\(id.uuidString.lowercased()).jpg",
      caption: caption,
      version: version,
      attachedAt: Date(timeIntervalSince1970: 300)
    )
  }

  static let policy = ConcertAlbumPolicy(
    policyVersion: 1,
    concertPhotoLimit: 100,
    contributorPhotoLimit: 30,
    reservationLimit24Hours: 10,
    pickerBatchLimit: 10,
    captionCharacterLimit: 300,
    attachedFileByteLimit: 2_097_152,
    pendingReservationLifetimeSeconds: 3_600
  )

  static func activity(version: Int = 1) -> FriendActivity {
    FriendActivity(
      id: UUID(uuidString: "46000000-0000-0000-0000-00000000000\(version)")!,
      concertID: concertID,
      actorID: profileID,
      actorUsername: "friend",
      actorDisplayName: "A Friend",
      eventKind: .concertUpdated,
      occurredAt: Date(timeIntervalSince1970: TimeInterval(400 + version)),
      primaryArtistName: "Mitski",
      venueName: "The Greek",
      concertDate: "2026-06-01"
    )
  }

  static let creationInput = ConcertCreationInput(
    artists: [ConcertArtistInput(name: "Mitski", isPrimary: true)],
    venueName: "The Greek",
    concertDate: "2026-06-01",
    city: "Los Angeles",
    tour: nil,
    startsAt: nil,
    venueTimeZone: "America/Los_Angeles",
    setlist: []
  )

  static let updateInput = ConcertUpdateInput(
    concertID: concertID,
    expectedVersion: 1,
    artists: [ConcertArtistInput(name: "Mitski", isPrimary: true)],
    venueName: "The Greek Theatre",
    concertDate: "2026-06-01",
    city: "Los Angeles",
    tour: nil,
    startsAt: nil,
    venueTimeZone: "America/Los_Angeles",
    setlist: [],
    visibility: .friends
  )
}
