import SwiftUI

struct MainTabView: View {
  let session: AppSession
  let user: AuthenticatedUser
  let profile: Profile

  var body: some View {
    TabView {
      NavigationStack {
        FeedPlaceholderView()
      }
      .tabItem {
        Label("Feed", systemImage: "music.note.house")
      }

      ProfileTabView(session: session, user: user, profile: profile)
        .tabItem {
          Label("Profile", systemImage: "person.crop.circle")
        }
    }
  }
}

private struct ProfileTabView: View {
  let session: AppSession
  let user: AuthenticatedUser
  let profile: Profile

  var body: some View {
    NavigationStack {
      List {
        Section {
          HStack(spacing: 16) {
            Image(systemName: "person.crop.circle.fill")
              .font(.system(size: 56))
              .foregroundStyle(.tint)
              .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
              Text(profile.displayName ?? "")
                .font(.title3.weight(.semibold))

              Text("@\(profile.username ?? "")")
                .foregroundStyle(.secondary)
            }
          }
          .padding(.vertical, 6)
        }

        Section("Account") {
          LabeledContent("Email", value: user.email ?? "Unavailable")
        }

        Section {
          Button("Sign Out", role: .destructive) {
            Task {
              await session.signOut()
            }
          }
        }
      }
      .navigationTitle("Profile")
    }
  }
}
