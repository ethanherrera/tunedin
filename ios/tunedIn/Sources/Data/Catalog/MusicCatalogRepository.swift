import Foundation
import SwiftUI

protocol MusicCatalogRepository: Sendable {
  func search(
    kind: CatalogEntityKind,
    query: String,
    offset: Int,
    artistContextIDs: [UUID],
    concertContextID: UUID?
  ) async throws -> CatalogSearchPage

  func resolve(_ candidate: CatalogResult) async throws -> CatalogEntity

  func createCustomArtist(_ input: CustomCatalogArtistInput) async throws -> CatalogArtist
  func createCustomArea(_ input: CustomCatalogAreaInput) async throws -> CatalogArea
  func createCustomPlace(_ input: CustomCatalogPlaceInput) async throws -> CatalogPlace
  func createCustomSong(_ input: CustomCatalogSongInput) async throws -> CatalogSong
  func createCustomTour(_ input: CustomCatalogTourInput) async throws -> CatalogTour
}

enum CatalogInput {
  static func normalizedText(_ value: String) -> String {
    value.split(whereSeparator: \.isWhitespace).joined(separator: " ")
  }

  static func optionalNormalizedText(_ value: String) -> String? {
    let normalized = normalizedText(value)
    return normalized.isEmpty ? nil : normalized
  }

  static func isValidName(_ value: String, maximumLength: Int = 160) -> Bool {
    let normalized = normalizedText(value)
    return !normalized.isEmpty
      && normalized.count <= maximumLength
      && normalized.rangeOfCharacter(from: .controlCharacters) == nil
  }
}

extension EnvironmentValues {
  @Entry var musicCatalogRepository: any MusicCatalogRepository = UnavailableMusicCatalogRepository()
}

private struct UnavailableMusicCatalogRepository: MusicCatalogRepository {
  private var error: MusicCatalogError {
    .rejected(message: "Music search is unavailable in this view.", retryable: false)
  }

  func search(
    kind _: CatalogEntityKind,
    query _: String,
    offset _: Int,
    artistContextIDs _: [UUID],
    concertContextID _: UUID?
  ) async throws -> CatalogSearchPage {
    throw error
  }

  func resolve(_: CatalogResult) async throws -> CatalogEntity {
    throw error
  }

  func createCustomArtist(_: CustomCatalogArtistInput) async throws -> CatalogArtist {
    throw error
  }

  func createCustomArea(_: CustomCatalogAreaInput) async throws -> CatalogArea {
    throw error
  }

  func createCustomPlace(_: CustomCatalogPlaceInput) async throws -> CatalogPlace {
    throw error
  }

  func createCustomSong(_: CustomCatalogSongInput) async throws -> CatalogSong {
    throw error
  }

  func createCustomTour(_: CustomCatalogTourInput) async throws -> CatalogTour {
    throw error
  }
}
