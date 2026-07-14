import SwiftUI

// swiftlint:disable:next type_body_length
struct PersonProfileView: View {
  let currentUserID: UUID
  let currentUsername: String
  let socialRepository: any SocialRepository
  let concertRepository: any ConcertRepository
  let onDismiss: (() -> Void)?

  @Environment(\.dismiss) private var dismiss
  @EnvironmentObject private var floatingControls: ConcertFloatingControls
  @State private var floatingControlOwner = UUID()
  @State private var profile: SocialProfile
  @State private var friendCount = 0
  @State private var isPerformingAction = false
  @State private var errorMessage: String?
  @State private var isShowingRemoveConfirmation = false
  @State private var archiveModel: ConcertArchiveModel

  init(
    profile: SocialProfile,
    currentUserID: UUID,
    currentUsername: String,
    socialRepository: any SocialRepository,
    concertRepository: any ConcertRepository,
    onDismiss: (() -> Void)? = nil
  ) {
    self.currentUserID = currentUserID
    self.currentUsername = currentUsername
    self.socialRepository = socialRepository
    self.concertRepository = concertRepository
    self.onDismiss = onDismiss
    _profile = State(initialValue: profile)
    _archiveModel = State(
      initialValue: ConcertArchiveModel(profileID: profile.id, concertRepository: concertRepository)
    )
  }

  var body: some View {
    ZStack {
      TunedInDesign.pageBackground
        .ignoresSafeArea()

      ScrollView {
        VStack(alignment: .leading, spacing: 20) {
          profileHeader
          if isCurrentUser {
            TunedInGlassSection {
              Label("This is your profile", systemImage: "person.crop.circle.badge.checkmark")
                .font(.headline)
                .foregroundStyle(TunedInDesign.primaryText)
            }
          } else {
            relationshipCard
          }

          if let errorMessage {
            TunedInFormCard {
              Label("Something went sideways", systemImage: "exclamationmark.triangle")
                .font(.headline)
                .foregroundStyle(TunedInDesign.primaryText)
              Text(errorMessage)
                .font(.subheadline)
                .foregroundStyle(TunedInDesign.mutedText)
            }
          }

          if isCurrentUser || profile.relationship.canViewFriendContent {
            friendCountLink
            ConcertArchiveView(
              profileID: profile.id,
              viewerID: currentUserID,
              viewerUsername: currentUsername,
              isOwner: isCurrentUser,
              concertRepository: concertRepository,
              socialRepository: socialRepository,
              model: archiveModel,
              refreshToken: 0
            )
          } else {
            privacyBoundary
          }
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 32)
      }
      .refreshable {
        await refreshServerContent()
      }
    }
    .navigationTitle("Profile")
    .navigationBarTitleDisplayMode(.inline)
    .navigationBarBackButtonHidden(onDismiss == nil)
    .confirmationDialog(
      "Remove \(profile.displayName)?",
      isPresented: $isShowingRemoveConfirmation,
      titleVisibility: .visible
    ) {
      Button("Remove friend", role: .destructive) {
        perform(.removeFriend)
      }
    } message: {
      Text("Friends-visible concerts disappear for both of you unless you are tagged collaborators.")
    }
    .task {
      await loadSocialContent(policy: .automatic)
    }
    .onAppear {
      guard onDismiss == nil else { return }
      floatingControls.configureBackOnly(title: "Profile", owner: floatingControlOwner) {
        floatingControls.reset()
        dismiss()
      }
    }
    .onDisappear {
      guard onDismiss == nil else { return }
      floatingControls.resetBackOnly(owner: floatingControlOwner)
    }
    .safeAreaInset(edge: .bottom, spacing: 0) {
      if let onDismiss {
        TunedInSubscreenBackBar(title: "Profile", action: onDismiss)
          .padding(.horizontal, TunedInDesign.bottomControlHorizontalInset)
          .padding(.top, 8)
          .padding(.bottom, TunedInDesign.bottomControlInset)
      }
    }
    .tunedInEdgeSwipeBack {
      if let onDismiss {
        onDismiss()
      } else {
        floatingControls.reset()
        dismiss()
      }
    }
  }

  private var profileHeader: some View {
    ProfileIdentityHeader(profile: profile) {
      RelationshipPill(relationship: profile.relationship)
    }
  }

  private var isCurrentUser: Bool {
    profile.id == currentUserID
  }

  private var relationshipCard: some View {
    TunedInGlassSection {
      if profile.relationship != .friends {
        HStack(alignment: .top, spacing: 12) {
          Image(systemName: relationshipIcon)
            .font(.title3.weight(.semibold))
            .foregroundStyle(TunedInDesign.accent)
            .frame(width: 28)
          VStack(alignment: .leading, spacing: 4) {
            Text(relationshipTitle)
              .font(.headline)
              .foregroundStyle(TunedInDesign.primaryText)
            Text(relationshipDescription)
              .font(.subheadline)
              .foregroundStyle(TunedInDesign.mutedText)
          }
        }
      }

      relationshipActions
    }
  }

  @ViewBuilder
  private var relationshipActions: some View {
    switch profile.relationship {
    case .none:
      primaryAction("Send friend request", icon: "person.badge.plus") {
        perform(.send)
      }
    case .outgoing:
      HStack(spacing: 10) {
        Label("Request sent", systemImage: "checkmark")
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(TunedInDesign.primaryText)
          .frame(maxWidth: .infinity)
          .padding(.vertical, 11)
          .background(TunedInDesign.raisedSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        compactAction("Withdraw") {
          perform(.withdraw)
        }
      }
    case .incoming:
      HStack(spacing: 10) {
        compactAction("Not now") {
          perform(.decline)
        }
        primaryAction("Accept", icon: "heart.fill") {
          perform(.accept)
        }
      }
    case .friends:
      HStack(spacing: 10) {
        Label("Friends", systemImage: "heart.fill")
          .font(.subheadline.weight(.bold))
          .foregroundStyle(TunedInDesign.actionForeground)
          .frame(maxWidth: .infinity)
          .padding(.vertical, 11)
          .background(TunedInDesign.accent, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        Menu {
          Button("Remove friend", role: .destructive) {
            isShowingRemoveConfirmation = true
          }
          Button("Block", role: .destructive) {
            perform(.block)
          }
        } label: {
          Image(systemName: "ellipsis")
            .font(.headline.weight(.bold))
            .foregroundStyle(TunedInDesign.primaryText)
            .frame(width: 46, height: 46)
            .background(TunedInDesign.raisedSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
      }
    case .declined:
      primaryAction("Try again later", icon: "clock") {}
        .disabled(true)
        .opacity(0.55)
    case .blocked:
      primaryAction("Unblock", icon: "person.badge.plus") {
        perform(.unblock)
      }
    case .unavailable:
      EmptyView()
    }
  }

  private var friendCountLink: some View {
    ProfileFriendsLink(count: friendCount) {
      FriendsListView(
        profileUsername: profile.username,
        currentUserID: currentUserID,
        currentUsername: currentUsername,
        socialRepository: socialRepository,
        concertRepository: concertRepository
      )
    }
  }

  private var privacyBoundary: some View {
    TunedInFormCard {
      Image(systemName: "eye.slash.fill")
        .font(.title2)
        .foregroundStyle(TunedInDesign.accent)
      Text("Friends-only archive")
        .font(.headline)
        .foregroundStyle(TunedInDesign.primaryText)
      Text(
        "Their friend list and friends-visible concerts unlock once you’re friends."
      )
      .font(.subheadline)
      .foregroundStyle(TunedInDesign.mutedText)
    }
  }

  private var relationshipTitle: String {
    switch profile.relationship {
    case .none:
      "A new concert person"
    case .outgoing:
      "Request is on its way"
    case .incoming:
      "They want to be friends"
    case .friends:
      "Friends"
    case .declined:
      "Give it a little space"
    case .blocked:
      "You’ve blocked this profile"
    case .unavailable:
      "This profile is private"
    }
  }

  private var relationshipDescription: String {
    switch profile.relationship {
    case .none:
      "Add them when you’re ready. Nothing from either diary is shared yet."
    case .outgoing:
      "You can take it back any time before they respond."
    case .incoming:
      "Accept to see friends-visible concerts and their friend list."
    case .friends:
      "You can see friends-visible concerts and their friend list."
    case .declined:
      "They passed for now. You can try again after a short cooldown."
    case .blocked:
      "Their Friends-visible content and direct requests are hidden."
    case .unavailable:
      "No relationship actions are available."
    }
  }

  private var relationshipIcon: String {
    switch profile.relationship {
    case .friends:
      "heart.fill"
    case .incoming:
      "person.badge.plus"
    case .outgoing:
      "paperplane.fill"
    case .blocked:
      "hand.raised.fill"
    default:
      "person.crop.circle"
    }
  }

  private func primaryAction(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Label(title, systemImage: isPerformingAction ? "hourglass" : icon)
        .font(.subheadline.weight(.bold))
        .foregroundStyle(TunedInDesign.actionForeground)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(TunedInDesign.accent, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
    .buttonStyle(.plain)
    .disabled(isPerformingAction)
  }

  private func compactAction(_ title: String, action: @escaping () -> Void) -> some View {
    Button(title, action: action)
      .font(.subheadline.weight(.bold))
      .foregroundStyle(TunedInDesign.primaryText)
      .frame(maxWidth: .infinity)
      .padding(.vertical, 12)
      .background(TunedInDesign.raisedSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
      .buttonStyle(.plain)
      .disabled(isPerformingAction)
  }

  private func perform(_ action: PersonAction) {
    guard !isCurrentUser else { return }
    Task {
      isPerformingAction = true
      do {
        try await action.perform(on: socialRepository, profileID: profile.id)
        profile = profile.updatingRelationship(action.resultingRelationship)
        if action != .block {
          if let refreshed = try await socialRepository.profile(
            username: profile.username,
            policy: .refresh
          ) {
            profile = refreshed
          }
        }
        await loadFriendCount(policy: .refresh)
        errorMessage = nil
      } catch {
        errorMessage = error.localizedDescription
      }
      isPerformingAction = false
    }
  }

  private func loadSocialContent(policy: CacheReadPolicy) async {
    do {
      let refreshedProfile = try await socialRepository.profile(
        username: profile.username,
        policy: policy
      )
      if let refreshedProfile {
        profile = refreshedProfile
      } else {
        profile = profile.updatingRelationship(.unavailable)
      }
      errorMessage = nil
    } catch {
      errorMessage = error.localizedDescription
    }

    await loadFriendCount(policy: policy)
  }

  private func loadFriendCount(policy: CacheReadPolicy) async {
    guard isCurrentUser || profile.relationship.canViewFriendContent else {
      friendCount = 0
      return
    }

    do {
      friendCount = try await socialRepository.friends(
        username: profile.username,
        policy: policy
      ).count
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  private func refreshServerContent() async {
    await loadSocialContent(policy: .refresh)
    if isCurrentUser || profile.relationship.canViewFriendContent {
      await archiveModel.reload(policy: .refresh)
    }
  }
}

private extension SocialProfile {
  func updatingRelationship(_ relationship: RelationshipState) -> Self {
    Self(
      id: id,
      username: username,
      displayName: displayName,
      relationship: relationship,
      avatarObjectPath: avatarObjectPath,
      avatarVersion: avatarVersion
    )
  }
}

private extension PersonAction {
  var resultingRelationship: RelationshipState {
    switch self {
    case .send:
      .outgoing
    case .accept:
      .friends
    case .decline, .withdraw, .removeFriend, .unblock:
      .none
    case .block:
      .blocked
    }
  }
}
