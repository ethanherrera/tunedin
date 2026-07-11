#if DEBUG
  import Foundation

  struct DevelopmentConcertRepository: ConcertRepository {
    func createPrivateConcert(_ input: ConcertCreationInput) async throws -> Concert {
      let now = Date()

      return Concert(
        id: UUID(),
        ownerID: UUID(uuidString: "D0000000-0000-0000-0000-000000000001")!,
        venueName: input.venueName,
        city: input.city,
        concertDate: input.concertDate,
        startsAt: input.startsAt,
        venueTimeZone: input.venueTimeZone,
        tour: input.tour,
        visibility: .private,
        createdAt: now,
        updatedAt: now,
        lastActivityAt: now
      )
    }
  }
#endif
