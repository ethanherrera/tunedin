import SwiftUI

extension EnvironmentValues {
  @Entry var profileRepository: any ProfileRepository = UnavailableProfileRepository()
}

struct ProfileAvatarView: View {
  let profile: SocialProfile
  let size: CGFloat
  @Environment(\.profileRepository) private var repository
  @State private var url: URL?

  var body: some View {
    ZStack {
      ProfileMonogram(profile: profile, size: size)
      if let url {
        AsyncImage(url: url) { phase in
          if case let .success(image) = phase {
            image.resizable().scaledToFill()
          }
        }
      }
    }
    .frame(width: size, height: size)
    .clipShape(Circle())
    .task(id: cacheKey) {
      url = nil
      guard let path = profile.avatarObjectPath else { return }
      url = try? await repository.avatarURL(
        profileID: profile.id,
        objectPath: path,
        version: profile.avatarVersion
      )
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
