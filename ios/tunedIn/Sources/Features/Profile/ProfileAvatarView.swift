import SwiftUI

extension EnvironmentValues {
  @Entry var profileRepository: any ProfileRepository = UnavailableProfileRepository()
}

struct ProfileAvatarView: View {
  let profile: SocialProfile
  let size: CGFloat
  @Environment(\.profileRepository) private var repository
  @State private var url: URL?
  @State private var isResolvingURL = false
  @State private var failed = false

  var body: some View {
    Group {
      if profile.avatarObjectPath == nil || failed {
        ProfileMonogram(profile: profile, size: size)
      } else if let url {
        AsyncImage(url: url) { phase in
          switch phase {
          case let .success(image):
            image.resizable().scaledToFill()
          case .failure:
            ProfileMonogram(profile: profile, size: size)
          case .empty:
            TunedInSkeletonBlock(cornerRadius: size / 2)
          @unknown default:
            TunedInSkeletonBlock(cornerRadius: size / 2)
          }
        }
      } else if isResolvingURL {
        TunedInSkeletonBlock(cornerRadius: size / 2)
      } else {
        ProfileMonogram(profile: profile, size: size)
      }
    }
    .frame(width: size, height: size)
    .clipShape(Circle())
    .task(id: cacheKey) {
      url = nil
      failed = false
      guard let path = profile.avatarObjectPath else { return }
      isResolvingURL = true
      defer { isResolvingURL = false }
      do {
        url = try await repository.avatarURL(
          profileID: profile.id,
          objectPath: path,
          version: profile.avatarVersion
        )
      } catch {
        failed = true
      }
    }
  }

  private var cacheKey: String {
    "\(profile.id)-\(profile.avatarVersion)"
  }
}

private struct UnavailableProfileRepository: ProfileRepository {
  func fetchProfile(for _: UUID) async throws -> Profile {
    throw Error.unavailable
  }

  func isUsernameAvailable(_: String) async throws -> Bool {
    throw Error.unavailable
  }

  func completeOnboarding(username _: String, displayName _: String) async throws -> Profile {
    throw Error.unavailable
  }

  func setAvatar(jpegData _: Data, for _: UUID) async throws -> Profile {
    throw Error.unavailable
  }

  func removeAvatar(for _: UUID) async throws -> Profile {
    throw Error.unavailable
  }

  func avatarURL(profileID _: UUID, objectPath _: String, version _: Int64) async throws -> URL {
    throw Error.unavailable
  }

  enum Error: Swift.Error { case unavailable }
}
