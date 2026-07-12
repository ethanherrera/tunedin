import Testing
@testable import tunedIn
import UIKit

struct AvatarImageProcessorTests {
  @Test
  func cropsAndEncodesBoundedSquareJPEG() async throws {
    let image = UIGraphicsImageRenderer(size: CGSize(width: 900, height: 600)).image { context in
      UIColor.systemBlue.setFill()
      context.fill(CGRect(x: 0, y: 0, width: 900, height: 600))
    }
    let source = try #require(image.pngData())
    let result = try await AvatarImageProcessor.process(source)
    let decoded = try #require(UIImage(data: result))

    #expect(decoded.size == CGSize(width: 512, height: 512))
    #expect(result.count <= 1_048_576)
  }

  @Test
  func rejectsMalformedImageData() async {
    await #expect(throws: AvatarImageProcessor.ProcessingError.self) {
      try await AvatarImageProcessor.process(Data("not an image".utf8))
    }
  }

  @Test
  func concertPhotoUsesFourByThreeOutput() async throws {
    let image = UIGraphicsImageRenderer(size: CGSize(width: 900, height: 1600)).image { context in
      UIColor.systemPurple.setFill()
      context.cgContext.fill(CGRect(x: 0, y: 0, width: 900, height: 1600))
    }
    let result = try await AvatarImageProcessor.processConcertPhoto(#require(image.pngData()))
    let decoded = try #require(UIImage(data: result))
    #expect(decoded.size == CGSize(width: 1200, height: 1600))
    #expect(result.count <= 3_145_728)
  }
}

struct AvatarURLCacheTests {
  @Test
  func versionsInvalidateCachedURLs() async throws {
    let cache = AvatarURLCache()
    let profileID = UUID()
    let url = try #require(URL(string: "https://example.test/avatar.jpg?v=1"))
    let now = Date(timeIntervalSince1970: 1000)
    await cache.insert(url, profileID: profileID, version: 1, now: now)

    #expect(await cache.value(profileID: profileID, version: 1, now: now) == url)
    #expect(await cache.value(profileID: profileID, version: 2, now: now) == nil)
  }
}
