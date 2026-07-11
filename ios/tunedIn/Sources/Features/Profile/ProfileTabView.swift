import SwiftUI

struct MainTabView: View {
  let session: AppSession
  let user: AuthenticatedUser
  let profile: Profile
  let concertRepository: any ConcertRepository
  let socialRepository: any SocialRepository

  @State private var isPresentingConcertCreation = false
  @State private var archiveRefreshToken = 0

  var body: some View {
    TabView {
      NavigationStack {
        FriendsActivityFeedView(
          viewerID: profile.id,
          viewerUsername: profile.username ?? "",
          concertRepository: concertRepository,
          socialRepository: socialRepository
        )
      }
      .tabItem {
        Label("Feed", systemImage: "music.note.house")
      }

      ProfileTabView(
        session: session,
        user: user,
        profile: profile,
        concertRepository: concertRepository,
        socialRepository: socialRepository,
        archiveRefreshToken: archiveRefreshToken
      )
      .tabItem {
        Label("Profile", systemImage: "person.crop.circle")
      }
    }
    .overlay(alignment: .bottomTrailing) {
      TunedInFloatingAction {
        isPresentingConcertCreation = true
      }
      .padding(.trailing, 24)
      .padding(.bottom, -8)
    }
    .fullScreenCover(
      isPresented: $isPresentingConcertCreation,
      onDismiss: { archiveRefreshToken += 1 },
      content: { ConcertCreationView(concertRepository: concertRepository) }
    )
    .tint(TunedInDesign.accent)
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
  @State private var requestCount = 0

  var body: some View {
    NavigationStack {
      ZStack {
        TunedInDesign.pageBackground
          .ignoresSafeArea()

        ScrollView {
          VStack(alignment: .leading, spacing: 24) {
            profileHeader
            friendsEntry
            ConcertArchiveView(
              profileID: profile.id,
              viewerID: profile.id,
              viewerUsername: profile.username ?? "",
              isOwner: true,
              concertRepository: concertRepository,
              socialRepository: socialRepository,
              refreshToken: archiveRefreshToken
            )
            privateArchiveNote
            accountSection
            AppearancePicker()
          }
          .padding(.horizontal, 20)
          .padding(.top, 18)
          .padding(.bottom, 112)
        }
      }
      .toolbar(.hidden, for: .navigationBar)
    }
    .task {
      await loadSocialSummary()
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
    HStack(alignment: .top, spacing: 15) {
      ProfileMonogram(profile: currentSocialProfile, size: 66)
      VStack(alignment: .leading, spacing: 5) {
        Text("tunedIn")
          .font(.caption.weight(.black))
          .foregroundStyle(TunedInDesign.accent)
          .textCase(.uppercase)
        Text(profile.displayName ?? "")
          .font(.system(size: 28, weight: .bold, design: .serif))
          .foregroundStyle(TunedInDesign.primaryText)
        Text("@\(profile.username ?? "")")
          .font(.subheadline)
          .foregroundStyle(TunedInDesign.mutedText)
      }
      Spacer(minLength: 0)
      NavigationLink {
        FriendsListView(
          currentUserID: profile.id,
          currentUsername: profile.username ?? "",
          socialRepository: socialRepository,
          concertRepository: concertRepository
        )
      } label: {
        Image(systemName: "person.2.fill")
          .font(.headline.weight(.bold))
          .foregroundStyle(TunedInDesign.primaryText)
          .frame(width: 46, height: 46)
          .background(TunedInDesign.raisedSurface, in: Circle())
      }
      .accessibilityLabel("Open friends")
    }
  }

  private var friendsEntry: some View {
    NavigationLink {
      FriendsListView(
        currentUserID: profile.id,
        currentUsername: profile.username ?? "",
        socialRepository: socialRepository,
        concertRepository: concertRepository
      )
    } label: {
      TunedInGlassSection {
        HStack(alignment: .center, spacing: 14) {
          Image(systemName: "person.2.fill")
            .font(.title3.weight(.bold))
            .foregroundStyle(TunedInDesign.actionForeground)
            .frame(width: 48, height: 48)
            .background(TunedInDesign.accent, in: Circle())

          VStack(alignment: .leading, spacing: 4) {
            Text(friendCount == 0 ? "Friends" : "Friends · \(friendCount)")
              .font(.headline)
              .foregroundStyle(TunedInDesign.primaryText)
            Text(friendsSubtitle)
              .font(.subheadline)
              .foregroundStyle(TunedInDesign.mutedText)
              .lineLimit(2)
          }

          Spacer(minLength: 0)
          Image(systemName: "arrow.up.right")
            .font(.subheadline.weight(.bold))
            .foregroundStyle(TunedInDesign.accent)
        }
      }
    }
    .buttonStyle(.plain)
    .accessibilityHint("View friends, requests, and people search")
  }

  private var friendsSubtitle: String {
    if requestCount > 0 {
      return "\(requestCount) friend request\(requestCount == 1 ? "" : "s") waiting for you"
    }
    if friendCount > 0 {
      return "\(friendCount) friend\(friendCount == 1 ? "" : "s") in your circle · find more people"
    }
    return "Find people by @username. Your diary stays yours until then."
  }

  private var privateArchiveNote: some View {
    HStack(spacing: 10) {
      Image(systemName: "lock.fill")
        .foregroundStyle(TunedInDesign.accent)
      Text("Everything you add starts private. Share only when it feels right.")
        .font(.subheadline)
        .foregroundStyle(TunedInDesign.mutedText)
    }
    .padding(.horizontal, 4)
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

  private func loadSocialSummary() async {
    guard let username = profile.username else { return }
    async let friends = socialRepository.friends(username: username)
    async let incomingRequests = socialRepository.incomingFriendRequests()

    do {
      let (loadedFriends, loadedRequests) = try await (friends, incomingRequests)
      friendCount = loadedFriends.count
      requestCount = loadedRequests.count
    } catch {
      friendCount = 0
      requestCount = 0
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
