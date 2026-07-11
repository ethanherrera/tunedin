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
    .overlay(alignment: .bottom) {
      TunedInFloatingAction(title: "Log concert", systemImage: "plus") {
        isPresentingConcertCreation = true
      }
      .padding(.bottom, 64)
    }
    .fullScreenCover(isPresented: $isPresentingConcertCreation) {
      ConcertCreationView(concertRepository: concertRepository)
    }
    .tint(TunedInDesign.accent)
    .preferredColorScheme(.dark)
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
                  .foregroundStyle(.white)

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
                .foregroundStyle(.white)

              Text("Start with one show. Build the story when you’re ready.")
                .font(.subheadline)
                .foregroundStyle(TunedInDesign.mutedText)

              Button(action: onCreateConcert) {
                Label("Log a concert", systemImage: "plus")
                  .font(.subheadline.weight(.bold))
                  .foregroundStyle(TunedInDesign.ink)
                  .padding(.horizontal, 16)
                  .padding(.vertical, 12)
                  .background(TunedInDesign.accent, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
              }
              .buttonStyle(.plain)
            }

            TunedInFormCard {
              Text("Account")
                .font(.headline)
                .foregroundStyle(.white)
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
          .padding(.horizontal, 24)
          .padding(.top, 24)
          .padding(.bottom, 112)
        }
      }
      .toolbar(.hidden, for: .navigationBar)
    }
  }
}
