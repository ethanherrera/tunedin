import SwiftUI

extension EnvironmentValues {
  @Entry var imageLoader: AppMediaCache = .ephemeral()
}

struct CachedRemoteImage<Content: View>: View {
  let url: URL
  let resource: AppMediaResource
  @ViewBuilder let content: (AsyncImagePhase) -> Content

  @Environment(\.imageLoader) private var imageLoader
  @State private var phase = AsyncImagePhase.empty

  var body: some View {
    content(phase)
      .task(id: LoadID(url: url, resource: resource)) {
        phase = .empty
        do {
          let data = try await imageLoader.data(from: url, for: resource)
          guard let image = UIImage(data: data) else {
            await imageLoader.remove(resource)
            throw AppMediaCacheError.invalidImage
          }
          guard !Task.isCancelled else { return }
          phase = .success(Image(uiImage: image))
        } catch is CancellationError {
          return
        } catch {
          guard !Task.isCancelled else { return }
          phase = .failure(error)
        }
      }
  }

  private struct LoadID: Hashable {
    let url: URL
    let resource: AppMediaResource
  }
}
