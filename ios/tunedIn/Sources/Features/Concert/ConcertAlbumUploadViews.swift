import PhotosUI
import SwiftUI
import UIKit

struct PendingAlbumUpload: Identifiable {
  let id: UUID
  let item: PhotosPickerItem
  var previewData: Data?
  var processedData: Data?
  var reservation: ConcertPhotoReservation?
  var phase: AlbumUploadPhase
}

enum AlbumUploadPhase: Equatable {
  case preparing
  case uploading
  case saved(ConcertAlbumPhoto)
  case failed(String)

  var isActive: Bool {
    self == .preparing || self == .uploading
  }

  var canRetry: Bool {
    if case .failed = self { return true }
    return false
  }
}

struct ConcertAlbumEmptyState: View {
  let detail: ConcertDetail
  let viewerCanAddPhotos: Bool

  private var artistName: String {
    detail.artists.first(where: \.isPrimary)?.name ?? "this show"
  }

  var body: some View {
    ZStack(alignment: .bottomLeading) {
      LinearGradient(
        colors: [TunedInDesign.ticketViolet, TunedInDesign.ticketRose, TunedInDesign.ink],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
      )
      .frame(maxWidth: .infinity)
      .frame(height: 310)
      .overlay(alignment: .top) {
        AlbumMemoryCollage(artistName: artistName)
          .padding(.top, 22)
      }
      .overlay {
        LinearGradient(
          colors: [.clear, .black.opacity(0.88)],
          startPoint: .center,
          endPoint: .bottom
        )
      }

      VStack(alignment: .leading, spacing: 9) {
        Image(systemName: "photo.stack.fill")
          .font(.title3.weight(.bold))
          .foregroundStyle(.white)
          .frame(width: 44, height: 44)
          .background(.white.opacity(0.16), in: Circle())

        Text("The night is still developing.")
          .font(.system(.title2, design: .rounded).weight(.bold))
          .foregroundStyle(.white)

        Text(emptyCopy)
          .font(.subheadline)
          .foregroundStyle(.white.opacity(0.84))
          .fixedSize(horizontal: false, vertical: true)
      }
      .padding(20)
    }
    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 24, style: .continuous)
        .strokeBorder(.white.opacity(0.14))
    }
    .accessibilityElement(children: .combine)
  }

  private var emptyCopy: String {
    if viewerCanAddPhotos {
      return "Add the first photo from \(artistName) at \(detail.concert.venueName) with the photo control below."
    }
    return "When the editors share photos from \(artistName), they’ll gather here."
  }
}

private struct AlbumMemoryCollage: View {
  let artistName: String

  var body: some View {
    HStack(spacing: -28) {
      memoryCard(assetName: "afterglow-stage")
        .rotationEffect(.degrees(-8))
        .offset(y: 8)
      monogramCard
        .zIndex(1)
      memoryCard(assetName: "midnight-theatre")
        .rotationEffect(.degrees(8))
        .offset(y: 8)
    }
    .shadow(color: .black.opacity(0.34), radius: 16, y: 9)
    .accessibilityHidden(true)
  }

  private func memoryCard(assetName: String) -> some View {
    Group {
      if let image = UIImage(named: assetName) {
        Image(uiImage: image)
          .resizable()
          .scaledToFill()
      } else {
        TunedInDesign.raisedSurface
      }
    }
    .frame(width: 94, height: 126)
      .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
      .overlay {
        RoundedRectangle(cornerRadius: 13, style: .continuous)
          .strokeBorder(.white.opacity(0.5))
      }
  }

  private var monogramCard: some View {
    LinearGradient(
      colors: [TunedInDesign.accentWash, TunedInDesign.ticketRose],
      startPoint: .topLeading,
      endPoint: .bottomTrailing
    )
    .overlay {
      Text(artistName.prefix(1).uppercased())
        .font(.system(size: 54, weight: .black, design: .serif))
        .foregroundStyle(.white.opacity(0.82))
    }
    .frame(width: 104, height: 142)
    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 14, style: .continuous)
        .strokeBorder(.white.opacity(0.62))
    }
  }
}

struct PendingAlbumUploadTile: View {
  let upload: PendingAlbumUpload
  let retry: () -> Void

  var body: some View {
    ZStack {
      preview
      LinearGradient(
        colors: [.clear, .black.opacity(0.84)],
        startPoint: .center,
        endPoint: .bottom
      )
      status
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
    }
    .aspectRatio(CGSize(width: 4, height: 5), contentMode: .fit)
    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 14, style: .continuous)
        .strokeBorder(borderColor, lineWidth: upload.phase.canRetry ? 2 : 1)
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel(accessibilityLabel)
  }

  @ViewBuilder
  private var preview: some View {
    if let data = upload.previewData, let image = UIImage(data: data) {
      Image(uiImage: image)
        .resizable()
        .scaledToFill()
    } else {
      TunedInImagePlaceholder()
    }
  }

  @ViewBuilder
  private var status: some View {
    switch upload.phase {
    case .preparing:
      statusLabel("Preparing", systemImage: nil, showsProgress: true)
    case .uploading:
      statusLabel("Uploading", systemImage: nil, showsProgress: true)
    case .saved:
      statusLabel("Saved", systemImage: "checkmark.circle.fill", showsProgress: false)
    case let .failed(message):
      VStack(alignment: .leading, spacing: 7) {
        Text(message)
          .font(.caption2.weight(.semibold))
          .foregroundStyle(.white)
          .lineLimit(3)
        Button(action: retry) {
          Label("Retry", systemImage: "arrow.clockwise")
            .font(.caption.weight(.bold))
            .foregroundStyle(TunedInDesign.actionForeground)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(TunedInDesign.accent, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Retries this photo without asking you to select it again")
      }
    }
  }

  private func statusLabel(
    _ title: String,
    systemImage: String?,
    showsProgress: Bool
  ) -> some View {
    HStack(spacing: 6) {
      if showsProgress {
        ProgressView()
          .controlSize(.small)
          .tint(.white)
      } else if let systemImage {
        Image(systemName: systemImage)
          .symbolEffect(.bounce, value: title)
      }
      Text(title)
    }
    .font(.caption.weight(.bold))
    .foregroundStyle(.white)
  }

  private var borderColor: Color {
    upload.phase.canRetry ? .orange : .white.opacity(0.18)
  }

  private var accessibilityLabel: String {
    switch upload.phase {
    case .preparing: "Photo preparing"
    case .uploading: "Photo uploading"
    case .saved: "Photo saved"
    case let .failed(message): "Photo upload failed. \(message)"
    }
  }
}
