import Foundation

protocol ConcertRepository: Sendable {
  func createPrivateConcert(_ input: ConcertCreationInput) async throws -> Concert
}
