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
  func eventCoverUsesLandscapeOutput() async throws {
    let image = UIGraphicsImageRenderer(size: CGSize(width: 900, height: 1600)).image { context in
      UIColor.systemTeal.setFill()
      context.cgContext.fill(CGRect(x: 0, y: 0, width: 900, height: 1600))
    }
    let result = try await AvatarImageProcessor.processEventCover(#require(image.pngData()))
    let decoded = try #require(UIImage(data: result))
    #expect(decoded.size == CGSize(width: 1600, height: 1000))
    #expect(result.count <= 3_145_728)
  }
}
