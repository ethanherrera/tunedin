import ImageIO
import UIKit

enum ConcertAlbumImageProcessor {
  enum ProcessingError: LocalizedError {
    case invalidImage
    case cannotMeetSizeLimit

    var errorDescription: String? {
      switch self {
      case .invalidImage: "That photo could not be read."
      case .cannotMeetSizeLimit: "That photo could not be optimized below 2 MB."
      }
    }
  }

  static func process(_ sourceData: Data, maximumEdge: CGFloat = 2048, maximumBytes: Int = 2_097_152) async throws -> Data {
    try await Task.detached(priority: .userInitiated) {
      guard let source = CGImageSourceCreateWithData(sourceData as CFData, nil) else {
        throw ProcessingError.invalidImage
      }
      let options: [CFString: Any] = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceThumbnailMaxPixelSize: Int(maximumEdge),
        kCGImageSourceShouldCacheImmediately: true
      ]
      guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
        throw ProcessingError.invalidImage
      }
      let size = CGSize(width: image.width, height: image.height)
      let format = UIGraphicsImageRendererFormat()
      format.scale = 1
      format.opaque = true
      let normalized = UIGraphicsImageRenderer(size: size, format: format).image { context in
        UIColor.black.setFill()
        context.fill(CGRect(origin: .zero, size: size))
        UIImage(cgImage: image).draw(in: CGRect(origin: .zero, size: size))
      }
      for quality in stride(from: 0.9, through: 0.35, by: -0.05) {
        if let data = normalized.jpegData(compressionQuality: quality), !data.isEmpty, data.count <= maximumBytes {
          return data
        }
      }
      throw ProcessingError.cannotMeetSizeLimit
    }.value
  }
}
