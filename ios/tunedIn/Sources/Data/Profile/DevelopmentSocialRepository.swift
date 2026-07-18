#if DEBUG
  import Foundation

  enum DevelopmentSocialFixture {
    static let currentUserID = UUID(uuidString: "D0000000-0000-0000-0000-000000000001")!
    static let morganID = UUID(uuidString: "D0000000-0000-0000-0000-000000000002")!
    static let avaID = UUID(uuidString: "D0000000-0000-0000-0000-000000000003")!
    static let julesID = UUID(uuidString: "D0000000-0000-0000-0000-000000000004")!
    static let noaID = UUID(uuidString: "D0000000-0000-0000-0000-000000000005")!
    static let remiID = UUID(uuidString: "D0000000-0000-0000-0000-000000000006")!
    static let kaiID = UUID(uuidString: "D0000000-0000-0000-0000-000000000007")!
    static let rowanID = UUID(uuidString: "D0000000-0000-0000-0000-000000000008")!
    static let miaID = UUID(uuidString: "D0000000-0000-0000-0000-000000000009")!
    static let leoID = UUID(uuidString: "D0000000-0000-0000-0000-000000000010")!
    static let niaID = UUID(uuidString: "D0000000-0000-0000-0000-000000000011")!
    static let owenID = UUID(uuidString: "D0000000-0000-0000-0000-000000000012")!
    static let zoeID = UUID(uuidString: "D0000000-0000-0000-0000-000000000013")!

    static let profiles = [
      SocialProfile(
        id: morganID,
        username: "morgan_moon",
        displayName: "Morgan Moon",
        relationship: .friends
      ),
      SocialProfile(
        id: avaID,
        username: "ava_afterglow",
        displayName: "Ava Afterglow",
        relationship: .incoming
      ),
      SocialProfile(
        id: julesID,
        username: "jules_jams",
        displayName: "Jules Jams",
        relationship: .none
      ),
      SocialProfile(
        id: noaID,
        username: "noa_nights",
        displayName: "Noa Nights",
        relationship: .none
      ),
      SocialProfile(
        id: remiID,
        username: "remi_cole",
        displayName: "Remi Cole",
        relationship: .friends
      ),
      SocialProfile(
        id: kaiID,
        username: "kai_mercer",
        displayName: "Kai Mercer",
        relationship: .friends
      ),
      SocialProfile(
        id: rowanID,
        username: "rowan_ellis",
        displayName: "Rowan Ellis",
        relationship: .friends
      ),
      SocialProfile(
        id: miaID,
        username: "mia_torres",
        displayName: "Mia Torres",
        relationship: .friends
      ),
      SocialProfile(
        id: leoID,
        username: "leo_hart",
        displayName: "Leo Hart",
        relationship: .friends
      ),
      SocialProfile(
        id: niaID,
        username: "nia_brooks",
        displayName: "Nia Brooks",
        relationship: .friends
      ),
      SocialProfile(
        id: owenID,
        username: "owen_cruz",
        displayName: "Owen Cruz",
        relationship: .friends
      ),
      SocialProfile(
        id: zoeID,
        username: "zoe_kim",
        displayName: "Zoe Kim",
        relationship: .friends
      )
    ]

    static let currentProfile = SocialProfile(
      id: currentUserID,
      username: "dev_listener",
      displayName: "Development Listener",
      relationship: .friends
    )
  }

  actor DevelopmentSocialRepository: SocialRepository {
    private var relationships = Dictionary(
      uniqueKeysWithValues: DevelopmentSocialFixture.profiles.map { ($0.id, $0.relationship) }
    )

    func searchProfiles(usernamePrefix: String) async throws -> [SocialProfile] {
      let prefix = ProfileInput.normalizedUsername(usernamePrefix)
      guard !prefix.isEmpty else { return [] }

      return profiles(matching: { $0.username.hasPrefix(prefix) })
    }

    func profile(username: String) async throws -> SocialProfile? {
      profiles(matching: { $0.username == ProfileInput.normalizedUsername(username) }).first
    }

    func friends(username: String) async throws -> [SocialProfile] {
      let normalizedUsername = ProfileInput.normalizedUsername(username)
      if normalizedUsername == "dev_listener" {
        return profiles(matching: { relationships[$0.id] == .friends })
      }

      if normalizedUsername == "morgan_moon", relationships[DevelopmentSocialFixture.morganID] == .friends {
        return [DevelopmentSocialFixture.currentProfile]
      }

      return []
    }

    func incomingFriendRequests() async throws -> [SocialProfile] {
      profiles(matching: { relationships[$0.id] == .incoming })
    }

    func sendFriendRequest(to profileID: UUID) async throws {
      relationships[profileID] = .outgoing
    }

    func acceptFriendRequest(from profileID: UUID) async throws {
      relationships[profileID] = .friends
    }

    func declineFriendRequest(from profileID: UUID) async throws {
      relationships[profileID] = .declined
    }

    func withdrawFriendRequest(to profileID: UUID) async throws {
      relationships[profileID] = RelationshipState.none
    }

    func removeFriend(_ profileID: UUID) async throws {
      relationships[profileID] = RelationshipState.none
    }

    func block(_ profileID: UUID) async throws {
      relationships[profileID] = .blocked
    }

    func unblock(_ profileID: UUID) async throws {
      relationships[profileID] = RelationshipState.none
    }

    private func profiles(matching predicate: (SocialProfile) -> Bool) -> [SocialProfile] {
      DevelopmentSocialFixture.profiles
        .compactMap { profile in
          guard predicate(profile), let relationship = relationships[profile.id] else { return nil }
          guard relationship != .blocked else { return nil }
          return SocialProfile(
            id: profile.id,
            username: profile.username,
            displayName: profile.displayName,
            relationship: relationship
          )
        }
        .sorted { $0.username < $1.username }
    }
  }
#endif
