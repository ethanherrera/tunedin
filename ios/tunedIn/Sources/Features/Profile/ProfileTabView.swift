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
    let diaryID: UUID?

    var id: UUID { event.id }
  }

  let session: AppSession
  let user: AuthenticatedUser
  let profile: Profile
  let concertRepository: any ConcertRepository
  let eventRepository: (any EventRepository)?
  let socialRepository: any SocialRepository

  @State private var isPresentingConcertCreation = false
  @State private var isPresentingEventDiscovery = false
  @State private var isPresentingPeopleSearch = false
  @State private var shouldPresentPeopleSearchAfterDiscovery = false
  @State private var pendingCommunityEvent: CommunityEventRoute?
  @State private var presentedCommunityEvent: CommunityEventRoute?
  @State private var pendingSearchedProfile: SocialProfile?
  @State private var presentedSearchedProfile: SocialProfile?
  @State private var archiveRefreshToken = 0
  @State private var selectedTab: Tab = .feed
  @State private var feedNavigationID = UUID()
  @State private var plansNavigationID = UUID()
  @State private var profileNavigationID = UUID()
  @State private var isPresentingConcertEditMenu = false
  @State private var selectionFeedbackTrigger = 0
  @StateObject private var concertFloatingControls = ConcertFloatingControls()
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @Environment(\.musicCatalogRepository) private var musicCatalogRepository
  @Namespace private var bottomGlassNamespace
  @Namespace private var tabSelectionNamespace

  var body: some View {
    selectedContent
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .environmentObject(concertFloatingControls)
      .safeAreaInset(edge: .bottom, spacing: 0) {
        TunedInPersistentControlRegion {
          bottomControls
            .padding(.horizontal, TunedInDesign.bottomControlHorizontalInset)
            .padding(.top, 6)
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
      .fullScreenCover(
        isPresented: $isPresentingEventDiscovery,
        onDismiss: presentPendingDiscoveryDestination
      ) {
        if let eventRepository {
          EventDiscoveryView(
            viewerID: profile.id,
            eventRepository: eventRepository,
            musicCatalogRepository: musicCatalogRepository,
            onOpenEvent: { event in
              pendingCommunityEvent = CommunityEventRoute(event: event, diaryID: nil)
              isPresentingEventDiscovery = false
            },
            onSearchPeople: {
              shouldPresentPeopleSearchAfterDiscovery = true
              isPresentingEventDiscovery = false
            },
            onDismiss: { isPresentingEventDiscovery = false }
          )
        }
      }
      .fullScreenCover(item: $presentedCommunityEvent) { route in
        if let eventRepository {
          CommunityEventDetailView(
            eventID: route.event.id,
            viewerID: profile.id,
            repository: eventRepository,
            concertRepository: concertRepository,
            initialDiaryID: route.diaryID,
            onDismiss: { presentedCommunityEvent = nil }
          )
        }
      }
      .sheet(
        isPresented: $isPresentingPeopleSearch,
        onDismiss: presentPendingSearchedProfile
      ) {
        peopleSearchDrawer
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
            concertRepository: concertRepository,
            eventRepository: eventRepository,
            onOpenCommunityEvent: { event, diaryID in
              pendingCommunityEvent = CommunityEventRoute(event: event, diaryID: diaryID)
              presentedSearchedProfile = nil
            },
            onDismiss: { presentedSearchedProfile = nil }
          )
        }
        .environmentObject(concertFloatingControls)
        .tunedInKeyboardManaged()
      }
      .onChange(of: concertFloatingControls.isShowingEditMenu) { _, isShowingEditMenu in
        if !isShowingEditMenu {
          isPresentingConcertEditMenu = false
        }
      }
      .tint(TunedInDesign.accent)
      .tunedInSelectionFeedback(trigger: selectionFeedbackTrigger)
      .task {
        session.telemetry.captureAppBecameUsable(destination: "main_tabs")
      }
  }

  private var supportsEventActivity: Bool {
    eventRepository?.capabilities.contains(.activityFeed) == true
  }

  private var supportsPlans: Bool {
    eventRepository?.capabilities.contains(.plans) == true
  }

  private var bottomControls: some View {
    ZStack(alignment: .bottom) {
      switch concertFloatingControls.navigationContext {
      case .concert:
        ConcertContextBottomBar(
          controls: concertFloatingControls,
          isPresentingEditMenu: $isPresentingConcertEditMenu,
          glassNamespace: bottomGlassNamespace,
          fallbackToProfile: { activateTab(.profile) }
        )
        .transition(TunedInMotion.controlSceneTransition(reduceMotion: reduceMotion))
      case let .backOnly(title):
        subscreenBottomBar(title: title)
          .transition(TunedInMotion.controlSceneTransition(reduceMotion: reduceMotion))
      case .none:
        TunedInGlassTraversalLayout(glassNamespace: bottomGlassNamespace) {
          TunedInGlassIconButton(
            systemImage: "magnifyingglass",
            accessibilityLabel: eventRepository == nil ? "Search people" : "Find concerts"
          ) {
            if eventRepository == nil {
              isPresentingPeopleSearch = true
            } else {
              isPresentingEventDiscovery = true
            }
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
            accessibilityLabel: eventRepository == nil ? "Log concert" : "Find or add concert",
            style: .accent
          ) {
            if eventRepository == nil {
              isPresentingConcertCreation = true
            } else {
              isPresentingEventDiscovery = true
            }
          }
        }
        .transition(TunedInMotion.controlSceneTransition(reduceMotion: reduceMotion))
      }
    }
    .frame(maxWidth: .infinity, alignment: .center)
    .animation(
      TunedInMotion.navigation(reduceMotion: reduceMotion),
      value: concertFloatingControls.navigationContext
    )
  }

  private var peopleSearchDrawer: some View {
    NavigationStack {
      FriendSearchView(
        currentUserID: profile.id,
        currentUsername: profile.username ?? "",
        socialRepository: socialRepository,
        concertRepository: concertRepository,
        presentation: .drawer,
        onSelectProfile: { searchedProfile in
          pendingSearchedProfile = searchedProfile
          isPresentingPeopleSearch = false
        }
      )
    }
    .environmentObject(concertFloatingControls)
    .tunedInKeyboardManaged()
    .presentationDetents([.medium, .large])
    .presentationDragIndicator(.visible)
  }

  private func presentPendingSearchedProfile() {
    guard let pendingSearchedProfile else { return }
    self.pendingSearchedProfile = nil
    presentedSearchedProfile = pendingSearchedProfile
  }

  private func presentPendingDiscoveryDestination() {
    if let pendingCommunityEvent {
      self.pendingCommunityEvent = nil
      presentedCommunityEvent = pendingCommunityEvent
      return
    }
    if shouldPresentPeopleSearchAfterDiscovery {
      shouldPresentPeopleSearchAfterDiscovery = false
      isPresentingPeopleSearch = true
    }
  }

  private func presentPendingProfileDestination() {
    guard let pendingCommunityEvent else { return }
    self.pendingCommunityEvent = nil
    presentedCommunityEvent = pendingCommunityEvent
  }

  @ViewBuilder
  private var selectedContent: some View {
    switch selectedTab {
    case .feed:
      Group {
        if let eventRepository, supportsEventActivity {
          CommunityActivityFeedView(
            viewerID: profile.id,
            repository: eventRepository,
            onOpenActivity: { activity in
              presentedCommunityEvent = CommunityEventRoute(
                event: activity.event,
                diaryID: activity.diary?.id
              )
            }
          )
        } else {
          NavigationStack {
            FriendsActivityFeedView(
              viewerID: profile.id,
              viewerUsername: profile.username ?? "",
              concertRepository: concertRepository,
              socialRepository: socialRepository
            )
          }
        }
      }
      .id(feedNavigationID)
    case .plans:
      if let eventRepository, supportsPlans {
        CommunityPlansView(
          viewerID: profile.id,
          repository: eventRepository,
          onOpenEvent: {
            presentedCommunityEvent = CommunityEventRoute(event: $0, diaryID: nil)
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
        concertRepository: concertRepository,
        eventRepository: eventRepository,
        socialRepository: socialRepository,
        archiveRefreshToken: archiveRefreshToken,
        onOpenCommunityEvent: { event, diaryID in
          presentedCommunityEvent = CommunityEventRoute(event: event, diaryID: diaryID)
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
    concertFloatingControls.reset()

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
        concertFloatingControls.back(or: { activateTab(.profile) })
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

  func configureBackOnly(title: String, owner: UUID, back: @escaping () -> Void) {
    backAction = back
    selectPageAction = nil
    editAction = nil
    deleteAction = nil
    backControlOwner = owner
    canDelete = false
    isShowingEditMenu = false
    navigationContext = .backOnly(title)
  }

  func reset() {
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
    selectedPage = page
    selectPageAction?(page)
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
  let glassNamespace: Namespace.ID
  let fallbackToProfile: () -> Void
  @Namespace private var selectionNamespace
  @State private var selectionFeedbackTrigger = 0
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  var body: some View {
    TunedInGlassTraversalLayout(glassNamespace: glassNamespace) {
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
              if controls.selectedPage != page {
                selectionFeedbackTrigger += 1
              }
              controls.select(page: page)
            } label: {
              Group {
                if dynamicTypeSize.isAccessibilitySize {
                  Image(systemName: page.icon)
                    .font(.body.weight(.bold))
                    .accessibilityHidden(true)
                } else {
                  VStack(spacing: 2) {
                    Image(systemName: page.icon)
                      .font(.caption.weight(.bold))
                    Text(page.title)
                      .font(.caption2.weight(.bold))
                      .lineLimit(1)
                      .minimumScaleFactor(0.75)
                  }
                }
              }
              .foregroundStyle(
                controls.selectedPage == page
                  ? TunedInDesign.selectedControlForeground
                  : TunedInDesign.primaryText
              )
              .frame(minWidth: 0, maxWidth: .infinity)
              .frame(height: 48)
              .background {
                if controls.selectedPage == page {
                  TunedInSelectionLens()
                    .matchedGeometryEffect(id: "concert-context-selection", in: selectionNamespace)
                }
              }
              .contentShape(.interaction, Capsule())
            }
            .buttonStyle(.plain)
            .contentShape(.interaction, Capsule())
            .disabled(controls.isInteractionLocked)
            .accessibilityLabel("Show \(page.title.lowercased())")
            .accessibilityAddTraits(controls.selectedPage == page ? .isSelected : [])
          }
        }
      }
      .frame(maxWidth: 252)
      .animation(
        TunedInMotion.selection(reduceMotion: reduceMotion),
        value: controls.selectedPage
      )
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
            systemImage: "ellipsis",
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
    .tunedInSelectionFeedback(trigger: selectionFeedbackTrigger)
  }
}

struct ProfileTabView: View {
  let session: AppSession
  let user: AuthenticatedUser
  let profile: Profile
  let concertRepository: any ConcertRepository
  let eventRepository: (any EventRepository)?
  let socialRepository: any SocialRepository
  let archiveRefreshToken: Int
  let onOpenCommunityEvent: (CommunityEventSummary, UUID?) -> Void
  @State private var friendCount = 0
  @State private var communityHistory = CommunityProfileHistory.empty
  @State private var archiveModel: ConcertArchiveModel
  @State private var isShowingLegacyArchive = false

  init(
    session: AppSession,
    user: AuthenticatedUser,
    profile: Profile,
    concertRepository: any ConcertRepository,
    eventRepository: (any EventRepository)?,
    socialRepository: any SocialRepository,
    archiveRefreshToken: Int,
    onOpenCommunityEvent: @escaping (CommunityEventSummary, UUID?) -> Void
  ) {
    self.session = session
    self.user = user
    self.profile = profile
    self.concertRepository = concertRepository
    self.eventRepository = eventRepository
    self.socialRepository = socialRepository
    self.archiveRefreshToken = archiveRefreshToken
    self.onOpenCommunityEvent = onOpenCommunityEvent
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
          VStack(alignment: .leading, spacing: 20) {
            profileHeader
            friendCountLink
            if eventRepository?.capabilities.contains(.diaries) == true {
              CommunityProfileHistorySection(
                history: communityHistory,
                onOpenEvent: onOpenCommunityEvent
              )
              LegacyConcertArchiveDisclosure(
                profileID: profile.id,
                viewerID: profile.id,
                viewerUsername: profile.username ?? "",
                isOwner: true,
                concertRepository: concertRepository,
                socialRepository: socialRepository,
                model: archiveModel,
                refreshToken: archiveRefreshToken,
                isExpanded: $isShowingLegacyArchive
              )
            } else {
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
    await loadCommunityHistory()
    if eventRepository?.capabilities.contains(.diaries) != true || isShowingLegacyArchive {
      await archiveModel.reload(policy: .refresh)
    }
    try? await session.refreshProfile()
  }

  private func loadCommunityHistory() async {
    guard let eventRepository, eventRepository.capabilities.contains(.diaries) else {
      communityHistory = .empty
      return
    }
    communityHistory = (try? await eventRepository.profileHistory(
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

struct LegacyConcertArchiveDisclosure: View {
  let profileID: UUID
  let viewerID: UUID
  let viewerUsername: String
  let isOwner: Bool
  let concertRepository: any ConcertRepository
  let socialRepository: any SocialRepository
  let model: ConcertArchiveModel
  let refreshToken: Int
  @Binding var isExpanded: Bool

  var body: some View {
    DisclosureGroup(isExpanded: $isExpanded) {
      ConcertArchiveView(
        profileID: profileID,
        viewerID: viewerID,
        viewerUsername: viewerUsername,
        isOwner: isOwner,
        concertRepository: concertRepository,
        socialRepository: socialRepository,
        model: model,
        refreshToken: refreshToken
      )
      .padding(.top, 16)
    } label: {
      VStack(alignment: .leading, spacing: 3) {
        Label("Older concert logs", systemImage: "archivebox")
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(TunedInDesign.primaryText)
        Text("Shared logs from the earlier tunedIn experience")
          .font(.caption)
          .foregroundStyle(TunedInDesign.mutedText)
      }
      .padding(.vertical, 8)
    }
    .tint(TunedInDesign.mutedText)
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
