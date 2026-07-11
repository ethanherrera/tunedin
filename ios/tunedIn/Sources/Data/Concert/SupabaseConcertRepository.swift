import Foundation
import Supabase

struct SupabaseConcertRepository: ConcertRepository {
  let client: SupabaseClient

  func createPrivateConcert(_ input: ConcertCreationInput) async throws -> Concert {
    let response: PostgrestResponse<PublicSchema.ConcertsSelect> = try await client
      .rpc("create_private_concert", params: CreatePrivateConcertParameters(input: input))
      .single()
      .execute()

    return try Concert(databaseRecord: response.value)
  }
}

private struct CreatePrivateConcertParameters: Encodable {
  private let artists: [CreatePrivateConcertArtist]
  private let venueName: String
  private let concertDate: String
  private let city: String?
  private let tour: String?
  private let startsAt: String?
  private let venueTimeZone: String?
  private let setlist: [String]

  init(input: ConcertCreationInput) {
    artists = input.artists.map { CreatePrivateConcertArtist(name: $0.name, isPrimary: $0.isPrimary) }
    venueName = input.venueName
    concertDate = input.concertDate
    city = input.city
    tour = input.tour
    startsAt = input.startsAt.map(Self.dateTimeString)
    venueTimeZone = input.venueTimeZone
    setlist = input.setlist
  }

  enum CodingKeys: String, CodingKey {
    case artists = "p_artists"
    case venueName = "p_venue_name"
    case concertDate = "p_concert_date"
    case city = "p_city"
    case tour = "p_tour"
    case startsAt = "p_starts_at"
    case venueTimeZone = "p_venue_time_zone"
    case setlist = "p_setlist"
  }

  private static func dateTimeString(from date: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.string(from: date)
  }
}

private struct CreatePrivateConcertArtist: Encodable {
  private let name: String
  private let isPrimary: Bool

  init(name: String, isPrimary: Bool) {
    self.name = name
    self.isPrimary = isPrimary
  }

  enum CodingKeys: String, CodingKey {
    case name
    case isPrimary = "is_primary"
  }
}

private extension Concert {
  init(databaseRecord: PublicSchema.ConcertsSelect) throws {
    guard
      let visibility = ConcertVisibility(rawValue: databaseRecord.visibility.rawValue),
      let createdAt = SupabaseConcertDateParser.dateTime(from: databaseRecord.createdAt),
      let updatedAt = SupabaseConcertDateParser.dateTime(from: databaseRecord.updatedAt),
      let lastActivityAt = SupabaseConcertDateParser.dateTime(from: databaseRecord.lastActivityAt)
    else {
      throw ConcertRepositoryError.invalidDatabaseRecord
    }

    let startsAt = try databaseRecord.startsAt.map {
      guard let date = SupabaseConcertDateParser.dateTime(from: $0) else {
        throw ConcertRepositoryError.invalidDatabaseRecord
      }
      return date
    }

    self.init(
      id: databaseRecord.id,
      ownerID: databaseRecord.ownerId,
      venueName: databaseRecord.venueName,
      city: databaseRecord.city,
      concertDate: databaseRecord.concertDate,
      startsAt: startsAt,
      venueTimeZone: databaseRecord.venueTimeZone,
      tour: databaseRecord.tour,
      visibility: visibility,
      createdAt: createdAt,
      updatedAt: updatedAt,
      lastActivityAt: lastActivityAt
    )
  }
}

private enum ConcertRepositoryError: LocalizedError {
  case invalidDatabaseRecord

  var errorDescription: String? {
    switch self {
    case .invalidDatabaseRecord:
      "The saved concert could not be read. Please refresh and try again."
    }
  }
}

private enum SupabaseConcertDateParser {
  static func dateTime(from value: String) -> Date? {
    let fractionalSecondsFormatter = ISO8601DateFormatter()
    fractionalSecondsFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

    if let date = fractionalSecondsFormatter.date(from: value) {
      return date
    }

    return ISO8601DateFormatter().date(from: value)
  }
}
