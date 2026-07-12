import SwiftUI

struct ConcertPhotoView: View {
  let concert: Concert
  let artistName: String
  let repository: any ConcertRepository
  @State private var url: URL?

  var body: some View {
    ZStack {
      ConcertArtworkImage(artistName: artistName)
      if let url {
        AsyncImage(url: url) { phase in
          if case let .success(image) = phase {
            image.resizable().scaledToFill()
          }
        }
      }
    }
    .clipped()
    .task(id: "\(concert.id)-\(concert.photoVersion)") {
      url = nil
      guard let path = concert.photoObjectPath else { return }
      url = try? await repository.concertPhotoURL(
        concertID: concert.id, objectPath: path, version: concert.photoVersion
      )
    }
  }
}
