import PhotosUI
import SwiftUI

// Main-tab transition code temporarily shares this file with the existing profile surfaces.
// swiftlint:disable file_length

// swiftlint:disable:next type_body_length
struct MainTabView: View {
  private enum Tab: Hashable {
    case feed
    case plans
    case profile
  }

  private struct CommunityEventRoute: Identifiable {
    let event: CommunityEventSummary
    let postID: UUID?

    var id: UUID {
      event.id
    }
  }

  let session: AppSession
  let user: AuthenticatedUser
  let profile: Profile
  let postRepository: any PostRepository
  let eventRepository: any EventRepository
  let socialRepository: any SocialRepository

  @State private var isPresentingEventDiscovery = false
  @State private var isPresentingCommunityEventCreation = false
  @State private var pendingCommunityEvent: CommunityEventRoute?
  @State private var presentedCommunityEvent: CommunityEventRoute?
  @State private var pendingSearchedProfile: SocialProfile?
  @State private var presentedSearchedProfile: SocialProfile?
  @State private var selectedTab: Tab = .feed
  @State private var feedNavigationID = UUID()
  @State private var plansNavigationID = UUID()
  @State private var profileNavigationID = UUID()
  @State private var selectionFeedbackTrigger = 0
  @StateObject private var floatingControls = AppFloatingControls()
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @Environment(\.musicCatalogRepository) private var musicCatalogRepository
  @Namespace private var bottomGlassNamespace
  @Namespace private var tabSelectionNamespace

  var body: some View {
    selectedContent
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .environmentObject(floatingControls)
      .safeAreaInset(edge: .bottom, spacing: 0) {
        TunedInPersistentControlRegion {
          bottomControls
            .padding(.horizontal, TunedInDesign.bottomControlHorizontalInset)
            .padding(.top, 6)
            .padding(.bottom, TunedInDesign.bottomControlInset)
        }
      }
      .tunedInEdgeSwipeBack(
        isEnabled: floatingControls.navigationContext != .none
          && !floatingControls.isInteractionLocked
      ) {
        floatingControls.back(or: { activateTab(.profile) })
      }
      .fullScreenCover(
        isPresented: $isPresentingEventDiscovery,
        onDismiss: presentPendingDiscoveryDestination
      ) {
        EventDiscoveryView(
          viewerID: profile.id,
          eventRepository: eventRepository,
          musicCatalogRepository: musicCatalogRepository,
          socialRepository: socialRepository,
          currentUsername: profile.username ?? "",
          onOpenEvent: { event in
            pendingCommunityEvent = CommunityEventRoute(event: event, postID: nil)
            isPresentingEventDiscovery = false
          },
          onOpenProfile: { searchedProfile in
            pendingSearchedProfile = searchedProfile
            isPresentingEventDiscovery = false
          },
          onDismiss: { isPresentingEventDiscovery = false }
        )
      }
      .fullScreenCover(
        isPresented: $isPresentingCommunityEventCreation,
        onDismiss: presentPendingDiscoveryDestination
      ) {
        CommunityEventCreationView(
          creatorID: profile.id,
          eventRepository: eventRepository,
          musicCatalogRepository: musicCatalogRepository,
          onCreated: { event in
            pendingCommunityEvent = CommunityEventRoute(event: event, postID: nil)
            isPresentingCommunityEventCreation = false
          },
          onDismiss: { isPresentingCommunityEventCreation = false }
        )
      }
      .fullScreenCover(
        item: $presentedCommunityEvent,
        onDismiss: presentPendingProfileDestination
      ) { route in
        CommunityEventDetailView(
          eventID: route.event.id,
          viewerID: profile.id,
          repository: eventRepository,
          postRepository: postRepository,
          initialPostID: route.postID,
          onDismiss: { presentedCommunityEvent = nil }
        )
      }
      .fullScreenCover(
        item: $presentedSearchedProfile,
        onDismiss: presentPendingProfileDestination
      ) { searchedProfile in
        NavigationStack {
          PersonProfileView(
            profile: searchedProfile,
            currentUserID: profile.id,
            currentUsername: profile.username ?? "",
            socialRepository: socialRepository,
            postRepository: postRepository,
            eventRepository: eventRepository,
            onOpenCommunityEvent: { event, postID in
              pendingCommunityEvent = CommunityEventRoute(event: event, postID: postID)
              presentedSearchedProfile = nil
            },
            onDismiss: { presentedSearchedProfile = nil }
          )
        }
        .environmentObject(floatingControls)
        .tunedInKeyboardManaged()
      }
      .tint(TunedInDesign.accent)
      .environment(
        \.openSocialProfile,
        OpenSocialProfileAction { requestedProfile in
          openSocialProfile(requestedProfile)
        }
      )
      .tunedInSelectionFeedback(trigger: selectionFeedbackTrigger)
      .task {
        session.telemetry.captureAppBecameUsable(destination: "main_tabs")
      }
  }

  private var supportsEventActivity: Bool {
    eventRepository.capabilities.contains(.activityFeed)
  }

  private var supportsPlans: Bool {
    eventRepository.capabilities.contains(.plans)
  }

  private var bottomControls: some View {
    ZStack(alignment: .bottom) {
      switch floatingControls.navigationContext {
      case let .backOnly(title):
        subscreenBottomBar(title: title)
          .transition(TunedInMotion.controlSceneTransition(reduceMotion: reduceMotion))
      case .none:
        TunedInGlassTraversalLayout(glassNamespace: bottomGlassNamespace) {
          TunedInGlassIconButton(
            systemImage: "magnifyingglass",
            accessibilityLabel: "Search"
          ) {
            isPresentingEventDiscovery = true
          }
        } center: {
          TunedInGlassBottomBar {
            HStack(spacing: 2) {
              mainTabButtons
            }
          }
          .animation(TunedInMotion.selection(reduceMotion: reduceMotion), value: selectedTab)
        } trailing: {
          TunedInGlassIconButton(
            systemImage: "plus",
            accessibilityLabel: "Add concert",
            style: .accent
          ) {
            isPresentingCommunityEventCreation = true
          }
        }
        .transition(TunedInMotion.controlSceneTransition(reduceMotion: reduceMotion))
      }
    }
    .frame(maxWidth: .infinity, alignment: .center)
    .animation(
      TunedInMotion.navigation(reduceMotion: reduceMotion),
      value: floatingControls.navigationContext
    )
  }

  private func presentPendingDiscoveryDestination() {
    if let pendingCommunityEvent {
      self.pendingCommunityEvent = nil
      presentedCommunityEvent = pendingCommunityEvent
      return
    }
    if let pendingSearchedProfile {
      self.pendingSearchedProfile = nil
      presentedSearchedProfile = pendingSearchedProfile
    }
  }

  private func presentPendingProfileDestination() {
    if let pendingSearchedProfile {
      self.pendingSearchedProfile = nil
      presentedSearchedProfile = pendingSearchedProfile
      return
    }
    if let pendingCommunityEvent {
      self.pendingCommunityEvent = nil
      presentedCommunityEvent = pendingCommunityEvent
    }
  }

  private func openSocialProfile(_ requestedProfile: SocialProfile) {
    Task { @MainActor in
      let resolvedProfile = await (try? socialRepository.profile(
        username: requestedProfile.username
      )) ?? requestedProfile
      routeToSocialProfile(resolvedProfile)
    }
  }

  @MainActor
  private func routeToSocialProfile(_ requestedProfile: SocialProfile) {
    if requestedProfile.id == profile.id {
      pendingSearchedProfile = nil
      selectedTab = .profile
      profileNavigationID = UUID()
      presentedCommunityEvent = nil
      presentedSearchedProfile = nil
      return
    }

    if presentedCommunityEvent != nil || presentedSearchedProfile != nil {
      pendingSearchedProfile = requestedProfile
      presentedCommunityEvent = nil
      presentedSearchedProfile = nil
    } else {
      presentedSearchedProfile = requestedProfile
    }
  }

  @ViewBuilder
  private var selectedContent: some View {
    switch selectedTab {
    case .feed:
      CommunityActivityFeedView(
        viewerID: profile.id,
        repository: eventRepository,
        postRepository: postRepository,
        onOpenActivity: { activity in
          presentedCommunityEvent = CommunityEventRoute(
            event: activity.event,
            postID: activity.post?.id
          )
        }
      )
      .id(feedNavigationID)
    case .plans:
      if supportsPlans {
        CommunityPlansView(
          viewerID: profile.id,
          repository: eventRepository,
          onOpenEvent: {
            presentedCommunityEvent = CommunityEventRoute(event: $0, postID: nil)
          }
        )
        .id(plansNavigationID)
      } else {
        Color.clear
      }
    case .profile:
      ProfileTabView(
        session: session,
        user: user,
        profile: profile,
        postRepository: postRepository,
        eventRepository: eventRepository,
        socialRepository: socialRepository,
        onOpenCommunityEvent: { event, postID in
          presentedCommunityEvent = CommunityEventRoute(event: event, postID: postID)
        }
      )
      .id(profileNavigationID)
    }
  }

  @ViewBuilder
  private var mainTabButtons: some View {
    tabButton(.feed, title: "Feed", icon: "music.note.house")
    if supportsPlans {
      tabButton(.plans, title: "Plans", icon: "calendar")
    }
    tabButton(.profile, title: "Profile", icon: "person.crop.circle")
  }

  private func tabButton(_ tab: Tab, title: String, icon: String) -> some View {
    Button {
      activateTab(tab)
    } label: {
      navigationLabel(title: title, icon: icon, isSelected: selectedTab == tab)
    }
    .buttonStyle(.plain)
    .contentShape(.interaction, Capsule())
    .accessibilityLabel(title)
  }

  private func activateTab(_ tab: Tab) {
    if selectedTab != tab {
      selectionFeedbackTrigger += 1
    }
    floatingControls.reset()

    switch tab {
    case .feed:
      feedNavigationID = UUID()
    case .plans:
      plansNavigationID = UUID()
    case .profile:
      profileNavigationID = UUID()
    }

    selectedTab = tab
  }

  private func subscreenBottomBar(title: String) -> some View {
    TunedInGlassTraversalLayout(glassNamespace: bottomGlassNamespace) {
      TunedInGlassIconButton(
        systemImage: "chevron.backward",
        accessibilityLabel: "Back to \(title.lowercased())"
      ) {
        floatingControls.back(or: { activateTab(.profile) })
      }
    } center: {
      TunedInGlassBottomBar {
        HStack(spacing: 2) {
          mainTabButtons
        }
      }
      .animation(TunedInMotion.selection(reduceMotion: reduceMotion), value: selectedTab)
    } trailing: {
      EmptyView()
    }
  }

  private func navigationLabel(title: String, icon: String, isSelected: Bool) -> some View {
    Group {
      if dynamicTypeSize.isAccessibilitySize {
        Image(systemName: icon)
          .font(.title3.weight(.bold))
          .accessibilityHidden(true)
      } else {
        HStack(spacing: 6) {
          Image(systemName: icon)
            .font(.caption.weight(.bold))
          Text(title)
            .font(.caption.weight(.bold))
        }
      }
    }
    .foregroundStyle(isSelected ? TunedInDesign.selectedControlForeground : TunedInDesign.primaryText)
    .frame(width: dynamicTypeSize.isAccessibilitySize ? 52 : (supportsPlans ? 68 : 78))
    .frame(minHeight: 44)
    .padding(.horizontal, 2)
    .background {
      if isSelected {
        TunedInSelectionLens()
          .matchedGeometryEffect(id: "main-tab-selection", in: tabSelectionNamespace)
      }
    }
    .contentShape(.interaction, Capsule())
    .accessibilityAddTraits(isSelected ? .isSelected : [])
  }
}

enum AppNavigationContext: Equatable {
  case none
  case backOnly(String)
}

@MainActor
final class AppFloatingControls: ObservableObject {
  @Published private(set) var navigationContext: AppNavigationContext = .none
  @Published private(set) var isInteractionLocked = false

  private var backAction: (() -> Void)?
  private var backControlOwner: UUID?

  func configureBackOnly(title: String, owner: UUID, back: @escaping () -> Void) {
    backAction = back
    backControlOwner = owner
    navigationContext = .backOnly(title)
  }

  func reset() {
    backAction = nil
    backControlOwner = nil
    navigationContext = .none
    isInteractionLocked = false
  }

  func resetBackOnly(owner: UUID) {
    guard backControlOwner == owner else { return }
    reset()
  }

  func back(or fallback: () -> Void) {
    guard !isInteractionLocked else { return }
    guard let backAction else {
      fallback()
      return
    }
    backAction()
  }

  func setInteractionLocked(_ locked: Bool) {
    isInteractionLocked = locked
  }
}

struct ProfileTabView: View {
  let session: AppSession
  let user: AuthenticatedUser
  let profile: Profile
  let postRepository: any PostRepository
  let eventRepository: any EventRepository
  let socialRepository: any SocialRepository
  let onOpenCommunityEvent: (CommunityEventSummary, UUID?) -> Void

  @State private var friendCount = 0
  @State private var communityHistory = CommunityProfileHistory.empty

  var body: some View {
    NavigationStack {
      ZStack {
        TunedInDesign.pageBackground
          .ignoresSafeArea()

        ScrollView {
          VStack(alignment: .leading, spacing: 20) {
            profileHeader
            friendCountLink
            CommunityProfileHistorySection(
              history: communityHistory,
              eventRepository: eventRepository,
              postRepository: postRepository,
              onOpenEvent: onOpenCommunityEvent
            )
          }
          .padding(.horizontal, 20)
          .padding(.top, 12)
          .padding(.bottom, TunedInDesign.scrollContentBottomInset)
        }
        .refreshable {
          await refreshServerContent()
        }
      }
      .toolbar(.hidden, for: .navigationBar)
    }
    .task(id: profile.username) {
      await loadFriendCount(policy: .automatic)
      await loadCommunityHistory()
    }
  }

  private var currentSocialProfile: SocialProfile {
    SocialProfile(
      id: profile.id,
      username: profile.username ?? "listener",
      displayName: profile.displayName ?? "Concert listener",
      relationship: .friends,
      avatarObjectPath: profile.avatarObjectPath,
      avatarVersion: profile.avatarVersion
    )
  }

  private var profileHeader: some View {
    ProfileIdentityHeader(profile: currentSocialProfile) {
      NavigationLink {
        SettingsView(session: session, user: user, profile: profile)
      } label: {
        Image(systemName: "slider.horizontal.3")
          .font(.subheadline.weight(.bold))
          .foregroundStyle(TunedInDesign.primaryText)
          .frame(width: 44, height: 44)
          .background(TunedInDesign.raisedSurface, in: Circle())
      }
      .accessibilityLabel("Open settings")
    }
  }

  private var friendCountLink: some View {
    ProfileFriendsLink(count: friendCount) {
      FriendsListView(
        currentUserID: profile.id,
        currentUsername: profile.username ?? "",
        socialRepository: socialRepository,
        postRepository: postRepository,
        eventRepository: eventRepository,
        onOpenCommunityEvent: onOpenCommunityEvent
      )
    }
  }

  private func loadFriendCount(policy: CacheReadPolicy) async {
    guard let username = profile.username, !username.isEmpty else { return }
    do {
      friendCount = try await socialRepository.friends(
        username: username,
        policy: policy
      ).count
    } catch {}
  }

  private func refreshServerContent() async {
    await loadFriendCount(policy: .refresh)
    await loadCommunityHistory()
    try? await session.refreshProfile()
  }

  private func loadCommunityHistory() async {
    communityHistory = await (try? eventRepository.profileHistory(
      profileID: profile.id,
      viewerID: profile.id
    )) ?? .empty
  }
}

struct ProfileIdentityHeader<Trailing: View>: View {
  let profile: SocialProfile
  @ViewBuilder let trailing: Trailing

  var body: some View {
    HStack(alignment: .center, spacing: 16) {
      ProfileAvatarView(profile: profile, size: 72)
      VStack(alignment: .leading, spacing: 4) {
        Text(profile.displayName)
          .font(.system(.title2, design: .rounded, weight: .bold))
          .foregroundStyle(TunedInDesign.primaryText)
          .lineLimit(2)
          .minimumScaleFactor(0.82)
        Text("@\(profile.username)")
          .font(.subheadline.weight(.medium))
          .foregroundStyle(TunedInDesign.mutedText)
      }
      .layoutPriority(1)
      Spacer(minLength: 0)
      trailing
    }
  }
}

struct ProfileFriendsLink<Destination: View>: View {
  let count: Int
  @ViewBuilder let destination: () -> Destination

  var body: some View {
    NavigationLink {
      destination()
    } label: {
      HStack(spacing: 10) {
        Image(systemName: "person.2")
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(TunedInDesign.mutedText)
        Text(friendCountLabel)
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(TunedInDesign.primaryText)
      }
      .padding(.vertical, 2)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel("Open \(friendCountLabel)")
  }

  private var friendCountLabel: String {
    "\(count) \(count == 1 ? "friend" : "friends")"
  }
}

struct SettingsView: View {
  let session: AppSession
  let user: AuthenticatedUser
  let profile: Profile

  @Environment(\.dismiss) private var dismiss
  @EnvironmentObject private var floatingControls: AppFloatingControls
  @State private var floatingControlOwner = UUID()
  @State private var selectedPhoto: PhotosPickerItem?
  @State private var isChangingPhoto = false
  @State private var photoError: String?
  @State private var isConfirmingRemoval = false
  @State private var isShowingFeedback = false
  @State private var feedbackConfirmation: String?

  var body: some View {
    ZStack {
      TunedInDesign.pageBackground
        .ignoresSafeArea()

      ScrollView {
        VStack(alignment: .leading, spacing: 18) {
          Text("Make tunedIn yours")
            .font(.title2.weight(.bold))
            .foregroundStyle(TunedInDesign.primaryText)
          profilePhotoSection
          AppearancePicker()
          TelemetrySettingsSection(telemetry: session.telemetry)
          feedbackSection
          accountSection
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, TunedInDesign.scrollContentBottomInset)
      }
      .refreshable {
        try? await session.refreshProfile()
      }
    }
    .navigationTitle("Settings")
    .navigationBarTitleDisplayMode(.inline)
    .navigationBarBackButtonHidden()
    .onAppear {
      floatingControls.configureBackOnly(title: "Settings", owner: floatingControlOwner) {
        floatingControls.reset()
        dismiss()
      }
    }
    .onDisappear { floatingControls.resetBackOnly(owner: floatingControlOwner) }
    .tint(TunedInDesign.accent)
    .onChange(of: selectedPhoto) { _, item in
      guard let item else { return }
      Task { await upload(item) }
    }
    .alert("Remove profile photo?", isPresented: $isConfirmingRemoval) {
      Button("Cancel", role: .cancel) {}
      Button("Remove", role: .destructive) { Task { await removePhoto() } }
    } message: {
      Text("Your profile will return to its monogram.")
    }
    .alert("Feedback sent", isPresented: Binding(
      get: { feedbackConfirmation != nil },
      set: {
        if !$0 {
          feedbackConfirmation = nil
        }
      }
    )) {
      Button("Done", role: .cancel) {}
    } message: {
      Text(feedbackConfirmation ?? "Thank you for helping make tunedIn better.")
    }
    .sheet(isPresented: $isShowingFeedback) {
      FeedbackView(session: session) {
        feedbackConfirmation = "Thank you for helping make tunedIn better."
      }
    }
  }

  private var profilePhotoSection: some View {
    let currentProfile = displayedProfile

    return TunedInFormCard {
      Label("Profile photo", systemImage: "person.crop.circle")
        .font(.headline)
        .foregroundStyle(TunedInDesign.primaryText)
      HStack(spacing: 16) {
        ProfileAvatarView(
          profile: SocialProfile(
            id: currentProfile.id,
            username: currentProfile.username ?? "listener",
            displayName: currentProfile.displayName ?? "Listener",
            relationship: .friends,
            avatarObjectPath: currentProfile.avatarObjectPath,
            avatarVersion: currentProfile.avatarVersion
          ),
          size: 72
        )
        VStack(alignment: .leading, spacing: 8) {
          PhotosPicker(selection: $selectedPhoto, matching: .images) {
            Text(currentProfile.avatarObjectPath == nil ? "Choose photo" : "Change photo")
          }
          .disabled(isChangingPhoto)
          if currentProfile.avatarObjectPath != nil {
            Button("Remove photo", role: .destructive) { isConfirmingRemoval = true }
              .disabled(isChangingPhoto)
          }
        }
      }
      if isChangingPhoto {
        ProgressView("Updating photo…")
      }
      if let photoError {
        Text(photoError).font(.footnote).foregroundStyle(.red)
        Button("Try again") {
          guard let selectedPhoto else { return }
          Task { await upload(selectedPhoto) }
        }
        .disabled(isChangingPhoto)
      }
    }
  }

  private var displayedProfile: Profile {
    if case let .signedIn(signedInUser, currentProfile) = session.phase, signedInUser.id == user.id {
      return currentProfile
    }
    return profile
  }

  private func upload(_ item: PhotosPickerItem) async {
    isChangingPhoto = true
    photoError = nil
    defer { isChangingPhoto = false }
    do {
      guard let data = try await item.loadTransferable(type: Data.self) else { return }
      let jpeg = try await AvatarImageProcessor.process(data)
      try Task.checkCancellation()
      try await session.setAvatar(jpegData: jpeg)
      selectedPhoto = nil
    } catch is CancellationError {
      return
    } catch {
      photoError = error.localizedDescription
    }
  }

  private func removePhoto() async {
    isChangingPhoto = true
    photoError = nil
    defer { isChangingPhoto = false }
    do { try await session.removeAvatar() } catch { photoError = error.localizedDescription }
  }

  private var accountSection: some View {
    TunedInFormCard {
      Label("Account", systemImage: "person.text.rectangle")
        .font(.headline)
        .foregroundStyle(TunedInDesign.primaryText)
      Text(user.email ?? "Unavailable")
        .font(.subheadline)
        .foregroundStyle(TunedInDesign.mutedText)

      Button("Sign out", role: .destructive) {
        Task {
          await session.signOut()
        }
      }
      .font(.subheadline.weight(.semibold))
    }
  }

  private var feedbackSection: some View {
    TunedInFormCard {
      Label("Help improve tunedIn", systemImage: "bubble.left.and.bubble.right")
        .font(.headline)
        .foregroundStyle(TunedInDesign.primaryText)
      Text("Report a problem or share an idea directly with the team.")
        .font(.subheadline)
        .foregroundStyle(TunedInDesign.mutedText)
      Button("Send feedback") {
        isShowingFeedback = true
      }
      .font(.subheadline.weight(.semibold))
    }
  }
}

private struct AppearancePicker: View {
  @AppStorage(TunedInAppearance.storageKey)
  private var appearanceRawValue = TunedInAppearance.defaultAppearance.rawValue

  private var appearance: TunedInAppearance {
    TunedInAppearance(rawValue: appearanceRawValue) ?? .system
  }

  var body: some View {
    TunedInFormCard {
      Label("Appearance", systemImage: "circle.lefthalf.filled")
        .font(.headline)
        .foregroundStyle(TunedInDesign.primaryText)

      Text("Choose how tunedIn looks and feels.")
        .font(.subheadline)
        .foregroundStyle(TunedInDesign.mutedText)

      HStack(spacing: 8) {
        ForEach(TunedInAppearance.allCases) { option in
          Button {
            withAnimation(.snappy) {
              appearanceRawValue = option.rawValue
            }
          } label: {
            VStack(spacing: 6) {
              Image(systemName: option.systemImage)
                .font(.subheadline.weight(.semibold))
              Text(option.title)
                .font(.caption.weight(.bold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .foregroundStyle(option == appearance ? TunedInDesign.actionForeground : TunedInDesign.primaryText)
            .background(
              option == appearance ? TunedInDesign.accent : TunedInDesign.raisedSurface,
              in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
          }
          .buttonStyle(.plain)
          .accessibilityLabel("Use \(option.title.lowercased()) appearance")
          .accessibilityAddTraits(option == appearance ? .isSelected : [])
        }
      }
    }
  }
}
