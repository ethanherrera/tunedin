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
    selectedContent
      .environmentObject(concertFloatingControls)
      .padding(.bottom, 80)
      .overlay(alignment: .bottom) {
        bottomControls
          .padding(.horizontal, 16)
          .padding(.top, 8)
          .padding(.bottom, 8)
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
        HStack(alignment: .bottom, spacing: 8) {
          TunedInGlassBottomBar {
            HStack(spacing: 2) {
              tabButton(.feed, title: "Feed", icon: "music.note.house")
              tabButton(.profile, title: "Profile", icon: "person.crop.circle")
            }
          }

          TunedInFloatingAction(
            systemImage: "magnifyingglass",
            accessibilityLabel: "Search people",
            accessibilityHint: "Opens people search"
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
          }

          TunedInFloatingAction {
            isPresentingConcertCreation = true
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
    TunedInGlassBottomBar {
      HStack(spacing: 2) {
        Button {
          concertFloatingControls.back(or: { activateTab(.profile) })
        } label: {
          Image(systemName: "chevron.backward")
            .font(.subheadline.weight(.bold))
            .foregroundStyle(TunedInDesign.primaryText)
            .frame(width: 42, height: 46)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Back to \(title.lowercased())")

        Divider()
          .overlay(.white.opacity(0.18))
          .frame(height: 30)

        tabButton(.feed, title: "Feed", icon: "music.note.house")
        tabButton(.profile, title: "Profile", icon: "person.crop.circle")
      }
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
    .frame(width: 68, height: 46)
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
    }
  }

  func resetBackOnly(owner: UUID) {
    guard backControlOwner == owner else { return }
    reset()
  }

  func back(or fallback: () -> Void) {
    guard let backAction else {
      fallback()
      return
    }
    backAction()
  }

  func select(page: ConcertDetailPage) {
    withAnimation(.smooth(duration: 0.24, extraBounce: 0)) {
      selectedPage = page
      selectPageAction?(page)
    }
  }

  func edit() {
    editAction?()
  }

  func delete() {
    deleteAction?()
  }
}

private struct ConcertContextBottomBar: View {
  @ObservedObject var controls: ConcertFloatingControls
  @Binding var isPresentingEditMenu: Bool
  let fallbackToProfile: () -> Void
  @Namespace private var selectionNamespace

  var body: some View {
    HStack(alignment: .bottom, spacing: 8) {
      TunedInGlassBottomBar {
        HStack(spacing: 2) {
          Button {
            controls.back(or: fallbackToProfile)
          } label: {
            Image(systemName: "chevron.backward")
              .font(.subheadline.weight(.bold))
              .foregroundStyle(TunedInDesign.primaryText)
              .frame(width: 42, height: 46)
              .contentShape(Capsule())
          }
          .buttonStyle(.plain)
          .accessibilityLabel("Back to previous screen")

          Divider()
            .overlay(.white.opacity(0.18))
            .frame(height: 30)

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
              .frame(maxWidth: .infinity)
              .frame(height: 46)
              .background {
                if controls.selectedPage == page {
                  Capsule()
                    .fill(TunedInDesign.accent)
                    .matchedGeometryEffect(id: "concert-context-selection", in: selectionNamespace)
                }
              }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Show \(page.title.lowercased())")
          }
        }
      }
      .frame(maxWidth: .infinity)

      if controls.isShowingEditMenu {
        TunedInFloatingAction(
          systemImage: "pencil",
          accessibilityLabel: "Edit concert menu",
          accessibilityHint: "Shows concert edit actions"
        ) {
          isPresentingEditMenu = true
        }
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
                Divider()
                  .overlay(.white.opacity(0.15))
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

struct ProfileTabView: View {
  let session: AppSession
  let user: AuthenticatedUser
  let profile: Profile
  let concertRepository: any ConcertRepository
  let socialRepository: any SocialRepository
  let archiveRefreshToken: Int
  @State private var friendCount = 0

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
              refreshToken: archiveRefreshToken
            )
          }
          .padding(.horizontal, 20)
          .padding(.top, 18)
          .padding(.bottom, 112)
        }
      }
      .toolbar(.hidden, for: .navigationBar)
    }
    .task(id: profile.username) {
      await loadFriendCount()
    }
  }

  private var currentSocialProfile: SocialProfile {
    SocialProfile(
      id: profile.id,
      username: profile.username ?? "listener",
      displayName: profile.displayName ?? "Concert listener",
      relationship: .friends
    )
  }

  private var profileHeader: some View {
    ProfileIdentityHeader(profile: currentSocialProfile) {
      HStack(spacing: 8) {
        NavigationLink {
          SettingsView(session: session, user: user)
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

  private func loadFriendCount() async {
    guard let username = profile.username, !username.isEmpty else { return }
    do {
      friendCount = try await socialRepository.friends(username: username).count
    } catch {}
  }
}

struct ProfileIdentityHeader<Trailing: View>: View {
  let profile: SocialProfile
  @ViewBuilder let trailing: Trailing

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      ProfileMonogram(profile: profile, size: 58)
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

  @Environment(\.dismiss) private var dismiss
  @EnvironmentObject private var floatingControls: ConcertFloatingControls
  @State private var floatingControlOwner = UUID()

  var body: some View {
    ZStack {
      TunedInDesign.pageBackground
        .ignoresSafeArea()

      ScrollView {
        VStack(alignment: .leading, spacing: 24) {
          AppearancePicker()
          accountSection
        }
        .padding(20)
        .padding(.bottom, 32)
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
