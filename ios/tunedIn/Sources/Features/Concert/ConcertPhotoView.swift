import SwiftUI

struct ConcertPhotoView: View {
  let concert: Concert
  let artistName: String
  let repository: any ConcertRepository
  @State private var url: URL?
  @State private var isResolvingURL = false
  @State private var failed = false

  var body: some View {
    Group {
      if concert.photoObjectPath == nil || failed {
        ConcertArtworkImage(artistName: artistName)
      } else if let url {
        AsyncImage(url: url) { phase in
          switch phase {
          case let .success(image):
            image.resizable().scaledToFill()
          case .failure:
            TunedInImagePlaceholder(failed: true)
          case .empty:
            TunedInImagePlaceholder()
          @unknown default:
            TunedInImagePlaceholder()
          }
        }
      } else if isResolvingURL {
        TunedInImagePlaceholder()
      } else {
        ConcertArtworkImage(artistName: artistName)
      }
    }
    .clipped()
    .task(id: "\(concert.id)-\(concert.photoVersion)") {
      url = nil
      failed = false
      guard let path = concert.photoObjectPath else { return }
      isResolvingURL = true
      defer { isResolvingURL = false }
      do {
        url = try await repository.concertPhotoURL(
          concertID: concert.id, objectPath: path, version: concert.photoVersion
        )
      } catch {
        failed = true
      }
    }
  }
}
