import SwiftUI

struct MainTabView: View {
  let session: AppSession
  let user: AuthenticatedUser
  let profile: Profile
  let concertRepository: any ConcertRepository

  @State private var isPresentingConcertCreation = false

  var body: some View {
    TabView {
      NavigationStack {
        FeedPlaceholderView {
          isPresentingConcertCreation = true
        }
      }
      .tabItem {
        Label("Feed", systemImage: "music.note.house")
      }

      ProfileTabView(
        session: session,
        user: user,
        profile: profile,
        onCreateConcert: { isPresentingConcertCreation = true }
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
    .fullScreenCover(isPresented: $isPresentingConcertCreation) {
      ConcertCreationView(concertRepository: concertRepository)
    }
    .tint(TunedInDesign.accent)
  }
}

private struct ProfileTabView: View {
  let session: AppSession
  let user: AuthenticatedUser
  let profile: Profile
  let onCreateConcert: () -> Void

  var body: some View {
    NavigationStack {
      ZStack {
        TunedInDesign.pageBackground
          .ignoresSafeArea()

        ScrollView {
          VStack(alignment: .leading, spacing: 24) {
            HStack(spacing: 16) {
              Image(systemName: "person.crop.circle.fill")
                .font(.system(size: 62))
                .foregroundStyle(TunedInDesign.accent)
                .accessibilityHidden(true)

              VStack(alignment: .leading, spacing: 4) {
                Text(profile.displayName ?? "")
                  .font(.title2.weight(.bold))
                  .foregroundStyle(TunedInDesign.primaryText)

                Text("@\(profile.username ?? "")")
                  .font(.subheadline)
                  .foregroundStyle(TunedInDesign.mutedText)
              }
            }

            TunedInFormCard {
              Label("YOUR PRIVATE ARCHIVE", systemImage: "lock.fill")
                .font(.caption.weight(.bold))
                .foregroundStyle(TunedInDesign.accent)

              Text("The nights you save are yours.")
                .font(.headline)
                .foregroundStyle(TunedInDesign.primaryText)

              Text("Start with one show. Build the story when you’re ready.")
                .font(.subheadline)
                .foregroundStyle(TunedInDesign.mutedText)

              Button(action: onCreateConcert) {
                Label("Log a concert", systemImage: "plus")
                  .font(.subheadline.weight(.bold))
                  .foregroundStyle(TunedInDesign.actionForeground)
                  .padding(.horizontal, 16)
                  .padding(.vertical, 12)
                  .background(TunedInDesign.accent, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
              }
              .buttonStyle(.plain)
            }

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

            AppearancePicker()
          }
          .padding(.horizontal, 24)
          .padding(.top, 24)
          .padding(.bottom, 112)
        }
      }
      .toolbar(.hidden, for: .navigationBar)
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
