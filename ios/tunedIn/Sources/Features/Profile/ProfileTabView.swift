import PhotosUI
import SwiftUI

struct MainTabView: View {
  private enum Tab: Hashable {
    case feed
    case profile
  }

  let session: AppSession
  let user: AuthenticatedUser
  let profile: Profile
  let concertRepository: any ConcertRepository
  let socialRepository: any SocialRepository

  @State private var isPresentingConcertCreation = false
  @State private var isPresentingPeopleSearch = false
  @State private var pendingSearchedProfile: SocialProfile?
  @State private var presentedSearchedProfile: SocialProfile?
  @State private var archiveRefreshToken = 0
  @State private var selectedTab: Tab = .feed
  @State private var feedNavigationID = UUID()
  @State private var profileNavigationID = UUID()
  @State private var isPresentingConcertEditMenu = false
  @StateObject private var concertFloatingControls = ConcertFloatingControls()

  var body: some View {
    GeometryReader { _ in
      ZStack(alignment: .bottom) {
        selectedContent
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .environmentObject(concertFloatingControls)

        bottomControls
          .padding(.horizontal, TunedInDesign.bottomControlHorizontalInset)
          .padding(.top, 8)
          .padding(.bottom, TunedInDesign.bottomControlInset)
      }
    }
    .tunedInEdgeSwipeBack(
      isEnabled: concertFloatingControls.navigationContext != .none
        && !concertFloatingControls.isInteractionLocked
    ) {
      concertFloatingControls.back(or: { activateTab(.profile) })
    }
    .fullScreenCover(
      isPresented: $isPresentingConcertCreation,
      onDismiss: { archiveRefreshToken += 1 },
      content: { ConcertCreationView(concertRepository: concertRepository) }
    )
    .fullScreenCover(item: $presentedSearchedProfile) { searchedProfile in
      NavigationStack {
        PersonProfileView(
          profile: searchedProfile,
          currentUserID: profile.id,
          currentUsername: profile.username ?? "",
          socialRepository: socialRepository,
          concertRepository: concertRepository,
          onDismiss: { presentedSearchedProfile = nil }
        )
      }
      .environmentObject(concertFloatingControls)
      .tunedInKeyboardManaged()
    }
    .onChange(of: isPresentingPeopleSearch) { _, isPresented in
      guard !isPresented, let pendingSearchedProfile else { return }
      self.pendingSearchedProfile = nil
      presentedSearchedProfile = pendingSearchedProfile
    }
    .onChange(of: concertFloatingControls.isShowingEditMenu) { _, isShowingEditMenu in
      if !isShowingEditMenu {
        isPresentingConcertEditMenu = false
      }
    }
    .tint(TunedInDesign.accent)
    .task {
      session.telemetry.captureAppBecameUsable(destination: "main_tabs")
    }
  }

  private var bottomControls: some View {
    ZStack(alignment: .bottom) {
      switch concertFloatingControls.navigationContext {
      case .concert:
        ConcertContextBottomBar(
          controls: concertFloatingControls,
          isPresentingEditMenu: $isPresentingConcertEditMenu,
          fallbackToProfile: { activateTab(.profile) }
        )
        .transition(.opacity.combined(with: .scale(scale: 0.94, anchor: .bottom)))
      case let .backOnly(title):
        subscreenBottomBar(title: title)
          .transition(.opacity.combined(with: .scale(scale: 0.94, anchor: .bottom)))
      case .none:
        TunedInGlassTraversalLayout(height: 128) {
          EmptyView()
        } center: {
          TunedInGlassBottomBar {
            HStack(spacing: 2) {
              tabButton(.feed, title: "Feed", icon: "music.note.house")
              tabButton(.profile, title: "Profile", icon: "person.crop.circle")
            }
          }
        } trailing: {
          VStack(alignment: .trailing, spacing: 8) {
            TunedInGlassIconButton(
              systemImage: "magnifyingglass",
              accessibilityLabel: "Search people",
              style: .accent
            ) {
              isPresentingPeopleSearch = true
            }
            .popover(
              isPresented: $isPresentingPeopleSearch,
              attachmentAnchor: .point(.top),
              arrowEdge: .bottom
            ) {
              NavigationStack {
                FriendSearchView(
                  currentUserID: profile.id,
                  currentUsername: profile.username ?? "",
                  socialRepository: socialRepository,
                  concertRepository: concertRepository,
                  presentation: .popover,
                  onSelectProfile: { searchedProfile in
                    pendingSearchedProfile = searchedProfile
                    isPresentingPeopleSearch = false
                  }
                )
              }
              .frame(width: 330, height: 260)
              .presentationCompactAdaptation(.popover)
              .presentationBackground(.clear)
              .tunedInKeyboardManaged(showsDismissControl: false)
            }

            TunedInGlassIconButton(
              systemImage: "plus",
              accessibilityLabel: "Log concert",
              style: .accent
            ) {
              isPresentingConcertCreation = true
            }
          }
        }
        .transition(.opacity.combined(with: .scale(scale: 0.94, anchor: .bottom)))
      }
    }
    .frame(maxWidth: .infinity, alignment: .center)
    .animation(.smooth(duration: 0.28, extraBounce: 0), value: concertFloatingControls.navigationContext)
  }

  @ViewBuilder
  private var selectedContent: some View {
    switch selectedTab {
    case .feed:
      NavigationStack {
        FriendsActivityFeedView(
          viewerID: profile.id,
          viewerUsername: profile.username ?? "",
          concertRepository: concertRepository,
          socialRepository: socialRepository
        )
      }
      .id(feedNavigationID)
    case .profile:
      ProfileTabView(
        session: session,
        user: user,
        profile: profile,
        concertRepository: concertRepository,
        socialRepository: socialRepository,
        archiveRefreshToken: archiveRefreshToken
      )
      .id(profileNavigationID)
    }
  }

  private func tabButton(_ tab: Tab, title: String, icon: String) -> some View {
    Button {
      activateTab(tab)
    } label: {
      navigationLabel(title: title, icon: icon, isSelected: selectedTab == tab)
    }
    .buttonStyle(.plain)
  }

  private func activateTab(_ tab: Tab) {
    concertFloatingControls.reset()

    switch tab {
    case .feed:
      feedNavigationID = UUID()
    case .profile:
      profileNavigationID = UUID()
    }

    selectedTab = tab
  }

  private func subscreenBottomBar(title: String) -> some View {
    TunedInGlassTraversalLayout {
      TunedInGlassIconButton(
        systemImage: "chevron.backward",
        accessibilityLabel: "Back to \(title.lowercased())"
      ) {
        concertFloatingControls.back(or: { activateTab(.profile) })
      }
    } center: {
      TunedInGlassBottomBar {
        HStack(spacing: 2) {
          tabButton(.feed, title: "Feed", icon: "music.note.house")
          tabButton(.profile, title: "Profile", icon: "person.crop.circle")
        }
      }
    } trailing: {
      EmptyView()
    }
  }

  private func navigationLabel(title: String, icon: String, isSelected: Bool) -> some View {
    VStack(spacing: 2) {
      Image(systemName: icon)
        .font(.subheadline.weight(.bold))
      Text(title)
        .font(.caption2.weight(.bold))
    }
    .foregroundStyle(isSelected ? TunedInDesign.actionForeground : TunedInDesign.primaryText)
    .frame(minWidth: 58, minHeight: 48)
    .padding(.horizontal, 3)
    .background(isSelected ? TunedInDesign.accent : .clear, in: Capsule())
  }
}

enum BottomNavigationContext: Equatable {
  case none
  case backOnly(String)
  case concert
}

@MainActor
final class ConcertFloatingControls: ObservableObject {
  @Published private(set) var navigationContext: BottomNavigationContext = .none
  @Published private(set) var isShowingEditMenu = false
  @Published private(set) var canDelete = false
  @Published private(set) var selectedPage: ConcertDetailPage = .concert
  @Published private(set) var isInteractionLocked = false
  @Published private(set) var albumPickerLimit: Int?
  @Published var pendingPhotoSelections: [PhotosPickerItem] = []

  private var backAction: (() -> Void)?
  private var selectPageAction: ((ConcertDetailPage) -> Void)?
  private var editAction: (() -> Void)?
  private var deleteAction: (() -> Void)?
  private var backControlOwner: UUID?

  func configure(
    selectedPage: ConcertDetailPage,
    back: @escaping () -> Void,
    selectPage: @escaping (ConcertDetailPage) -> Void,
    edit: (() -> Void)?,
    delete: (() -> Void)?
  ) {
    withAnimation(.smooth(duration: 0.28, extraBounce: 0)) {
      self.selectedPage = selectedPage
      backAction = back
      selectPageAction = selectPage
      editAction = edit
      deleteAction = delete
      backControlOwner = nil
      canDelete = delete != nil
      isShowingEditMenu = edit != nil
      navigationContext = .concert
    }
  }

  func configureBackOnly(title: String, owner: UUID, back: @escaping () -> Void) {
    withAnimation(.smooth(duration: 0.28, extraBounce: 0)) {
      backAction = back
      selectPageAction = nil
      editAction = nil
      deleteAction = nil
      backControlOwner = owner
      canDelete = false
      isShowingEditMenu = false
      navigationContext = .backOnly(title)
    }
  }

  func reset() {
    withAnimation(.smooth(duration: 0.28, extraBounce: 0)) {
      backAction = nil
      selectPageAction = nil
      editAction = nil
      deleteAction = nil
      backControlOwner = nil
      canDelete = false
      isShowingEditMenu = false
      navigationContext = .none
      selectedPage = .concert
      isInteractionLocked = false
      albumPickerLimit = nil
      pendingPhotoSelections = []
    }
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

  func select(page: ConcertDetailPage) {
    guard !isInteractionLocked else { return }
    withAnimation(.smooth(duration: 0.24, extraBounce: 0)) {
      selectedPage = page
      selectPageAction?(page)
    }
  }

  func edit() {
    guard !isInteractionLocked else { return }
    editAction?()
  }

  func delete() {
    guard !isInteractionLocked else { return }
    deleteAction?()
  }

  func setInteractionLocked(_ locked: Bool) {
    isInteractionLocked = locked
  }

  func setAlbumPolicy(_ policy: ConcertAlbumPolicy) {
    albumPickerLimit = policy.pickerBatchLimit
  }
}

private struct ConcertContextBottomBar: View {
  @ObservedObject var controls: ConcertFloatingControls
  @Binding var isPresentingEditMenu: Bool
  let fallbackToProfile: () -> Void
  @Namespace private var selectionNamespace

  var body: some View {
    TunedInGlassTraversalLayout {
      TunedInGlassIconButton(
        systemImage: "chevron.backward",
        accessibilityLabel: "Back to previous screen"
      ) {
        controls.back(or: fallbackToProfile)
      }
      .disabled(controls.isInteractionLocked)
    } center: {
      TunedInGlassBottomBar {
        HStack(spacing: 2) {
          ForEach(ConcertDetailPage.allCases, id: \.self) { page in
            Button {
              controls.select(page: page)
            } label: {
              VStack(spacing: 2) {
                Image(systemName: page.icon)
                  .font(.caption.weight(.bold))
                Text(page.title)
                  .font(.caption2.weight(.bold))
                  .lineLimit(1)
                  .minimumScaleFactor(0.75)
              }
              .foregroundStyle(
                controls.selectedPage == page ? TunedInDesign.actionForeground : TunedInDesign.primaryText
              )
              .frame(minWidth: 0, maxWidth: .infinity)
              .frame(height: 48)
              .background {
                if controls.selectedPage == page {
                  Capsule()
                    .fill(TunedInDesign.accent)
                    .matchedGeometryEffect(id: "concert-context-selection", in: selectionNamespace)
                }
              }
            }
            .buttonStyle(.plain)
            .disabled(controls.isInteractionLocked)
            .accessibilityLabel("Show \(page.title.lowercased())")
          }
        }
      }
      .frame(maxWidth: 252)
    } trailing: {
      if controls.isShowingEditMenu {
        if controls.selectedPage == .photos {
          PhotosPicker(
            selection: $controls.pendingPhotoSelections,
            maxSelectionCount: controls.albumPickerLimit ?? 1,
            matching: .images
          ) {
            TunedInFloatingActionLabel(systemImage: "plus")
          }
          .buttonStyle(.plain)
          .disabled(controls.isInteractionLocked || controls.albumPickerLimit == nil)
          .accessibilityLabel("Add photos")
          .accessibilityHint(
            controls.albumPickerLimit == nil ? "Album policy is loading" : "Select photos for this album"
          )
        } else {
          TunedInFloatingAction(
            systemImage: "pencil",
            accessibilityLabel: "Edit concert menu",
            accessibilityHint: "Shows concert edit actions"
          ) {
            isPresentingEditMenu = true
          }
          .disabled(controls.isInteractionLocked)
          .popover(
            isPresented: $isPresentingEditMenu,
            attachmentAnchor: .point(.top),
            arrowEdge: .bottom
          ) {
            TunedInGlassPopover {
              VStack(spacing: 4) {
                Button {
                  isPresentingEditMenu = false
                  controls.edit()
                } label: {
                  Label("Edit concert", systemImage: "pencil")
                    .foregroundStyle(TunedInDesign.primaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.plain)

                if controls.canDelete {
                  Divider().overlay(.white.opacity(0.15))
                  Button(role: .destructive) {
                    isPresentingEditMenu = false
                    controls.delete()
                  } label: {
                    Label("Delete concert", systemImage: "trash")
                      .foregroundStyle(.red)
                      .frame(maxWidth: .infinity, alignment: .leading)
                      .padding(.horizontal, 14)
                      .padding(.vertical, 12)
                  }
                  .buttonStyle(.plain)
                }
              }
              .frame(width: 210)
              .padding(8)
            }
            .presentationCompactAdaptation(.popover)
            .presentationBackground(.clear)
          }
        }
      }
    }
  }
}

struct ProfileTabView: View {
  let session: AppSession
  let user: AuthenticatedUser
  let profile: Profile
  let concertRepository: any ConcertRepository
  let socialRepository: any SocialRepository
  let archiveRefreshToken: Int
  @State private var friendCount = 0
  @State private var archiveModel: ConcertArchiveModel

  init(
    session: AppSession,
    user: AuthenticatedUser,
    profile: Profile,
    concertRepository: any ConcertRepository,
    socialRepository: any SocialRepository,
    archiveRefreshToken: Int
  ) {
    self.session = session
    self.user = user
    self.profile = profile
    self.concertRepository = concertRepository
    self.socialRepository = socialRepository
    self.archiveRefreshToken = archiveRefreshToken
    _archiveModel = State(
      initialValue: ConcertArchiveModel(profileID: profile.id, concertRepository: concertRepository)
    )
  }

  var body: some View {
    NavigationStack {
      ZStack {
        TunedInDesign.pageBackground
          .ignoresSafeArea()

        ScrollView {
          VStack(alignment: .leading, spacing: 24) {
            profileHeader
            friendCountLink
            ConcertArchiveView(
              profileID: profile.id,
              viewerID: profile.id,
              viewerUsername: profile.username ?? "",
              isOwner: true,
              concertRepository: concertRepository,
              socialRepository: socialRepository,
              model: archiveModel,
              refreshToken: archiveRefreshToken
            )
          }
          .padding(.horizontal, 20)
          .padding(.top, 18)
          .padding(.bottom, 112)
        }
        .refreshable {
          await refreshServerContent()
        }
      }
      .toolbar(.hidden, for: .navigationBar)
    }
    .task(id: profile.username) {
      await loadFriendCount(policy: .automatic)
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
      HStack(spacing: 8) {
        NavigationLink {
          SettingsView(session: session, user: user, profile: profile)
        } label: {
          Image(systemName: "gearshape")
            .font(.headline.weight(.bold))
            .foregroundStyle(TunedInDesign.primaryText)
            .frame(width: 42, height: 42)
            .background(TunedInDesign.raisedSurface, in: Circle())
        }
        .accessibilityLabel("Open settings")
      }
    }
  }

  private var friendCountLink: some View {
    ProfileFriendsLink(count: friendCount) {
      FriendsListView(
        currentUserID: profile.id,
        currentUsername: profile.username ?? "",
        socialRepository: socialRepository,
        concertRepository: concertRepository
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
    await archiveModel.reload(policy: .refresh)
    try? await session.refreshProfile()
  }
}

struct ProfileIdentityHeader<Trailing: View>: View {
  let profile: SocialProfile
  @ViewBuilder let trailing: Trailing

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      ProfileAvatarView(profile: profile, size: 58)
      VStack(alignment: .leading, spacing: 3) {
        Text("tunedIn")
          .font(.caption.weight(.black))
          .foregroundStyle(TunedInDesign.accent)
          .textCase(.uppercase)
        Text(profile.displayName)
          .font(.system(size: 26, weight: .bold, design: .serif))
          .foregroundStyle(TunedInDesign.primaryText)
          .lineLimit(2)
          .minimumScaleFactor(0.82)
        Text("@\(profile.username)")
          .font(.subheadline)
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
        Image(systemName: "person.2.fill")
          .font(.headline)
          .foregroundStyle(TunedInDesign.accent)
          .frame(width: 26)
        Text(friendCountLabel)
          .font(.headline)
          .foregroundStyle(TunedInDesign.primaryText)
        Spacer()
        Image(systemName: "chevron.right")
          .font(.caption.weight(.bold))
          .foregroundStyle(TunedInDesign.mutedText)
      }
      .padding(.horizontal, 15)
      .padding(.vertical, 14)
      .frame(maxWidth: .infinity)
      .background(TunedInDesign.raisedSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
      .overlay {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
          .strokeBorder(TunedInDesign.cardBorder.opacity(0.72))
      }
      .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
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
  @EnvironmentObject private var floatingControls: ConcertFloatingControls
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
        VStack(alignment: .leading, spacing: 24) {
          profilePhotoSection
          AppearancePicker()
          TelemetrySettingsSection(telemetry: session.telemetry)
          feedbackSection
          accountSection
        }
        .padding(20)
        .padding(.bottom, 32)
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
      set: { if !$0 { feedbackConfirmation = nil } }
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
    TunedInFormCard {
      Text("Profile Photo").font(.headline).foregroundStyle(TunedInDesign.primaryText)
      HStack(spacing: 16) {
        ProfileAvatarView(
          profile: SocialProfile(
            id: displayedProfile.id,
            username: displayedProfile.username ?? "listener",
            displayName: displayedProfile.displayName ?? "Listener",
            relationship: .friends,
            avatarObjectPath: displayedProfile.avatarObjectPath,
            avatarVersion: displayedProfile.avatarVersion
          ),
          size: 72
        )
        VStack(alignment: .leading, spacing: 8) {
          PhotosPicker(selection: $selectedPhoto, matching: .images) {
            Text(displayedProfile.avatarObjectPath == nil ? "Choose photo" : "Change photo")
          }
          .disabled(isChangingPhoto)
          if displayedProfile.avatarObjectPath != nil {
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
      Text("Account")
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
      Text("Help improve tunedIn")
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
  @AppStorage(TunedInAppearance.storageKey) private var appearanceRawValue = TunedInAppearance.light.rawValue

  private var appearance: TunedInAppearance {
    TunedInAppearance(rawValue: appearanceRawValue) ?? .system
  }

  var body: some View {
    TunedInFormCard {
      Text("Appearance")
        .font(.headline)
        .foregroundStyle(TunedInDesign.primaryText)

      Text("Choose the way you want your diary to feel.")
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
