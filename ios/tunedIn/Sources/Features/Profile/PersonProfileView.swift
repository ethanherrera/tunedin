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
  @State private var friends: [SocialProfile] = []
  @State private var isPerformingAction = false
  @State private var errorMessage: String?
  @State private var isShowingRemoveConfirmation = false

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
  }

  var body: some View {
    ZStack {
      TunedInDesign.pageBackground
        .ignoresSafeArea()

      ScrollView {
        VStack(alignment: .leading, spacing: 20) {
          profileHeader
          relationshipCard

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

          if profile.relationship.canViewFriendContent {
            friendListSection
            ConcertArchiveView(
              profileID: profile.id,
              viewerID: currentUserID,
              viewerUsername: currentUsername,
              isOwner: false,
              concertRepository: concertRepository,
              socialRepository: socialRepository,
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
      await loadFriendList()
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
          .padding(.vertical, 8)
      }
    }
  }

  private var profileHeader: some View {
    HStack(spacing: 16) {
      ProfileMonogram(profile: profile, size: 78)
      VStack(alignment: .leading, spacing: 5) {
        Text(profile.displayName)
          .font(.system(size: 28, weight: .bold, design: .serif))
          .foregroundStyle(TunedInDesign.primaryText)
        Text("@\(profile.username)")
          .font(.subheadline)
          .foregroundStyle(TunedInDesign.mutedText)
        RelationshipPill(relationship: profile.relationship)
      }
      Spacer(minLength: 0)
    }
  }

  private var relationshipCard: some View {
    TunedInGlassSection {
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
        Label("You’re friends", systemImage: "heart.fill")
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

  private var friendListSection: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Text("Friends")
          .font(.headline)
          .foregroundStyle(TunedInDesign.primaryText)
        Text("\(friends.count)")
          .font(.caption.weight(.bold))
          .foregroundStyle(TunedInDesign.actionForeground)
          .padding(.horizontal, 7)
          .padding(.vertical, 3)
          .background(TunedInDesign.accent, in: Capsule())
      }

      if friends.isEmpty {
        Text("Their circle is taking shape.")
          .font(.subheadline)
          .foregroundStyle(TunedInDesign.mutedText)
      } else {
        ScrollView(.horizontal, showsIndicators: false) {
          HStack(spacing: 10) {
            ForEach(friends) { friend in
              VStack(spacing: 6) {
                ProfileMonogram(profile: friend, size: 48)
                Text(friend.displayName.split(separator: " ").first.map(String.init) ?? friend.displayName)
                  .font(.caption.weight(.semibold))
                  .foregroundStyle(TunedInDesign.primaryText)
                  .lineLimit(1)
              }
              .frame(width: 66)
            }
          }
        }
      }
    }
  }

  private var privacyBoundary: some View {
    TunedInFormCard {
      Image(systemName: "eye.slash.fill")
        .font(.title2)
        .foregroundStyle(TunedInDesign.accent)
      Text("A profile, not a window.")
        .font(.headline)
        .foregroundStyle(TunedInDesign.primaryText)
      Text(
        "You can see who \(profile.displayName) is. Their friends and concert diary stay private until you’re friends."
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
      "In each other’s circle"
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
      "Accept to see Friends-visible concerts and each other’s friend lists."
    case .friends:
      "You can see Friends-visible concerts and the people in each other’s circle."
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
    Task {
      isPerformingAction = true
      do {
        try await action.perform(on: socialRepository, profileID: profile.id)
        profile = profile.updatingRelationship(action.resultingRelationship)
        if action != .block {
          if let refreshed = try await socialRepository.profile(username: profile.username) {
            profile = refreshed
          }
        }
        await loadFriendList()
        errorMessage = nil
      } catch {
        errorMessage = error.localizedDescription
      }
      isPerformingAction = false
    }
  }

  private func loadFriendList() async {
    guard profile.relationship.canViewFriendContent else {
      friends = []
      return
    }

    do {
      friends = try await socialRepository.friends(username: profile.username)
    } catch {
      errorMessage = error.localizedDescription
    }
  }
}

private extension SocialProfile {
  func updatingRelationship(_ relationship: RelationshipState) -> Self {
    Self(id: id, username: username, displayName: displayName, relationship: relationship)
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
