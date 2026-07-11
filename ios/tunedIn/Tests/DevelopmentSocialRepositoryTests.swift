#if DEBUG
  import Foundation
  import Testing
  @testable import tunedIn

  struct SocialRPCParameterTests {
    @Test
    func relationshipActionsEncodeTheirDatabaseParameterNames() throws {
      let profileID = UUID()

      #expect(try encodedKeys(RecipientIDParameter(recipientID: profileID)) == ["p_recipient_id"])
      #expect(try encodedKeys(RequesterIDParameter(requesterID: profileID)) == ["p_requester_id"])
      #expect(try encodedKeys(FriendIDParameter(friendID: profileID)) == ["p_friend_id"])
      #expect(try encodedKeys(ProfileIDParameter(profileID: profileID)) == ["p_profile_id"])
    }

    private func encodedKeys(_ value: some Encodable) throws -> Set<String> {
      let data = try JSONEncoder().encode(value)
      let object = try JSONSerialization.jsonObject(with: data)
      return Set(try #require((object as? [String: Any])?.keys))
    }
  }

  struct DevelopmentSocialRepositoryTests {
    @Test
    func friendRequestJourneyUpdatesEachRelationshipState() async throws {
      let repository = DevelopmentSocialRepository()

      let jules = try #require(await repository.profile(username: "jules_jams"))
      #expect(jules.relationship == .none)

      try await repository.sendFriendRequest(to: jules.id)
      let outgoing = try #require(await repository.profile(username: "jules_jams"))
      #expect(outgoing.relationship == .outgoing)

      try await repository.withdrawFriendRequest(to: jules.id)
      let withdrawn = try #require(await repository.profile(username: "jules_jams"))
      #expect(withdrawn.relationship == .none)

      let ava = try #require(await repository.profile(username: "ava_afterglow"))
      #expect(ava.relationship == .incoming)
      try await repository.acceptFriendRequest(from: ava.id)
      let accepted = try #require(await repository.profile(username: "ava_afterglow"))
      #expect(accepted.relationship == .friends)
    }

    @Test
    func blockingHidesDiscoveryUntilUnblocked() async throws {
      let repository = DevelopmentSocialRepository()
      let morgan = try #require(await repository.profile(username: "morgan_moon"))

      try await repository.block(morgan.id)
      let hidden = try await repository.profile(username: "morgan_moon")
      #expect(hidden == nil)

      try await repository.unblock(morgan.id)
      let unblocked = try #require(await repository.profile(username: "morgan_moon"))
      #expect(unblocked.relationship == .none)
    }
  }
#endif
