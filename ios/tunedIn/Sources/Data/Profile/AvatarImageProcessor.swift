import UIKit

enum AvatarImageProcessor {
  enum ProcessingError: LocalizedError {
    case invalidImage
    case cannotMeetSizeLimit

    var errorDescription: String? {
      switch self {
      case .invalidImage: "That photo could not be read. Please choose another."
      case .cannotMeetSizeLimit: "That photo could not be optimized below 1 MB."
      }
    }
  }

  static func process(_ sourceData: Data) async throws -> Data {
    try await process(sourceData, outputSize: CGSize(width: 512, height: 512), maximumBytes: 1_048_576)
  }

  static func processConcertPhoto(_ sourceData: Data) async throws -> Data {
    try await process(sourceData, outputSize: CGSize(width: 1200, height: 1600), maximumBytes: 3_145_728)
  }

  private static func process(_ sourceData: Data, outputSize: CGSize, maximumBytes: Int) async throws -> Data {
    try await Task.detached(priority: .userInitiated) {
      guard let image = UIImage(data: sourceData), image.size.width > 0, image.size.height > 0 else {
        throw ProcessingError.invalidImage
      }
      let targetRatio = outputSize.width / outputSize.height
      let sourceRatio = image.size.width / image.size.height
      let cropWidth = sourceRatio > targetRatio ? image.size.height * targetRatio : image.size.width
      let cropHeight = sourceRatio > targetRatio ? image.size.height : image.size.width / targetRatio
      let crop = CGRect(
        x: (image.size.width - cropWidth) / 2,
        y: (image.size.height - cropHeight) / 2,
        width: cropWidth,
        height: cropHeight
      )
      let format = UIGraphicsImageRendererFormat()
      format.scale = 1
      format.opaque = true
      let renderer = UIGraphicsImageRenderer(size: outputSize, format: format)
      let normalized = renderer.image { _ in
        image.draw(
          in: CGRect(
            x: -crop.minX * outputSize.width / crop.width,
            y: -crop.minY * outputSize.height / crop.height,
            width: image.size.width * outputSize.width / crop.width,
            height: image.size.height * outputSize.height / crop.height
          )
        )
      }
      for quality in stride(from: 0.88, through: 0.45, by: -0.08) {
        if let data = normalized.jpegData(compressionQuality: quality), data.count <= maximumBytes {
          return data
        }
      }
      throw ProcessingError.cannotMeetSizeLimit
    }.value
  }
}
