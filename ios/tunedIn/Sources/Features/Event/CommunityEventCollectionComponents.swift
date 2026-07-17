import SwiftUI

struct EventPostGridTile: View {
  let post: EventPostPreview
  let viewerID: UUID
  let postRepository: any PostRepository
  let onOpen: () -> Void

  var body: some View {
    GeometryReader { proxy in
      ZStack(alignment: .bottomLeading) {
        Button(action: onOpen) {
          PostMediaPreview(
            postID: post.id,
            reportedPhotoCount: post.photoCount,
            postRepository: postRepository,
            height: proxy.size.width,
            maximumVisiblePhotos: 1
          )
          .frame(width: proxy.size.width, height: proxy.size.width)
        }
        .buttonStyle(TunedInPosterButtonStyle())
        .accessibilityLabel("Open \(post.author.displayName)’s post")

        LinearGradient(
          colors: [.clear, .black.opacity(0.78)],
          startPoint: .center,
          endPoint: .bottom
        )
        .allowsHitTesting(false)

        if let score = post.score {
          CommunityEventScoreBadge(score: score, size: .compact)
            .padding(7)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            .allowsHitTesting(false)
        }

        SocialProfileButton(profile: post.author) {
          HStack(spacing: 5) {
            ProfileAvatarView(profile: post.author, size: 20)
            Text(post.author.id == viewerID ? "You" : post.author.displayName)
              .font(.caption2.weight(.bold))
              .foregroundStyle(.white)
              .lineLimit(1)
          }
          .padding(.horizontal, 7)
          .padding(.vertical, 6)
          .frame(maxWidth: .infinity, alignment: .leading)
        }
      }
      .frame(width: proxy.size.width, height: proxy.size.width)
      .clipped()
    }
    .aspectRatio(1, contentMode: .fit)
  }
}

struct EventCollectionBottomBar: View {
  let title: String
  let onDismiss: () -> Void

  var body: some View {
    TunedInPersistentControlRegion {
      TunedInGlassTraversalLayout {
        TunedInGlassIconButton(
          systemImage: "chevron.backward",
          accessibilityLabel: "Back to concert",
          action: onDismiss
        )
      } center: {
        TunedInGlassBottomBar {
          Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(TunedInDesign.primaryText)
            .lineLimit(1)
            .frame(minWidth: 132, minHeight: 48)
            .padding(.horizontal, 16)
        }
      } trailing: {
        EmptyView()
      }
      .padding(.horizontal, TunedInDesign.bottomControlHorizontalInset)
      .padding(.top, 6)
      .padding(.bottom, TunedInDesign.bottomControlInset)
    }
  }
}
