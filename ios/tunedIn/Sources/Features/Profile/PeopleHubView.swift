// swiftlint:disable file_length

import Observation
import SwiftUI

struct FriendsListView: View {
  let currentUserID: UUID
  let currentUsername: String
  let socialRepository: any SocialRepository
  let concertRepository: any ConcertRepository

  @State private var model: PeopleHubModel
  @Environment(\.dismiss) private var dismiss
  @EnvironmentObject private var floatingControls: ConcertFloatingControls

  init(
    currentUserID: UUID,
    currentUsername: String,
    socialRepository: any SocialRepository,
    concertRepository: any ConcertRepository
  ) {
    self.currentUserID = currentUserID
    self.currentUsername = currentUsername
    self.socialRepository = socialRepository
    self.concertRepository = concertRepository
    _model = State(
      initialValue: PeopleHubModel(
        repository: socialRepository,
        currentUsername: currentUsername
      )
    )
  }

  var body: some View {
    ZStack {
      TunedInDesign.pageBackground
        .ignoresSafeArea()

      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          if let errorMessage = model.errorMessage {
            ContentUnavailableView {
              Label("Couldn’t refresh friends", systemImage: "exclamationmark.triangle")
            } description: {
              Text(errorMessage)
            } actions: {
              Button("Try again") { Task { await model.refresh() } }
            }
          } else if model.friends.isEmpty {
            ContentUnavailableView(
              "No friends yet",
              systemImage: "person.2",
              description: Text("Search by @username to find someone.")
            )
            .frame(maxWidth: .infinity)
            .padding(.top, 72)
          } else {
            LazyVStack(spacing: 10) {
              ForEach(model.friends) { profile in
                friendProfileLink(profile)
              }
            }
          }
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 32)
      }
    }
    .navigationTitle("Friends")
    .navigationBarTitleDisplayMode(.inline)
    .navigationBarBackButtonHidden()
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        NavigationLink {
          FriendSearchView(
            currentUserID: currentUserID,
            currentUsername: currentUsername,
            socialRepository: socialRepository,
            concertRepository: concertRepository
          )
        } label: {
          Image(systemName: "magnifyingglass")
        }
        .accessibilityLabel("Search people")
      }
    }
    .task { await model.refresh() }
    .onAppear {
      floatingControls.configureBackOnly(title: "Friends") {
        floatingControls.reset()
        dismiss()
      }
    }
    .onDisappear { floatingControls.reset() }
  }

  private func friendProfileLink(_ profile: SocialProfile) -> some View {
    NavigationLink {
      PersonProfileView(
        profile: profile,
        currentUserID: currentUserID,
        currentUsername: currentUsername,
        socialRepository: socialRepository,
        concertRepository: concertRepository
      )
    } label: {
      PersonRow(profile: profile)
    }
    .buttonStyle(.plain)
  }
}

struct FriendSearchView: View {
  enum Presentation: Equatable {
    case page
    case popover
  }

  let currentUserID: UUID
  let currentUsername: String
  let socialRepository: any SocialRepository
  let concertRepository: any ConcertRepository
  let presentation: Presentation
  let onSelectProfile: ((SocialProfile) -> Void)?

  @State private var model: PeopleHubModel
  @Environment(\.dismiss) private var dismiss
  @EnvironmentObject private var floatingControls: ConcertFloatingControls

  init(
    currentUserID: UUID,
    currentUsername: String,
    socialRepository: any SocialRepository,
    concertRepository: any ConcertRepository,
    presentation: Presentation = .page,
    onSelectProfile: ((SocialProfile) -> Void)? = nil
  ) {
    self.currentUserID = currentUserID
    self.currentUsername = currentUsername
    self.socialRepository = socialRepository
    self.concertRepository = concertRepository
    self.presentation = presentation
    self.onSelectProfile = onSelectProfile
    _model = State(
      initialValue: PeopleHubModel(
        repository: socialRepository,
        currentUsername: currentUsername
      )
    )
  }

  var body: some View {
    @Bindable var model = model

    Group {
      if presentation == .page {
        ZStack {
          TunedInDesign.pageBackground
            .ignoresSafeArea()
          searchContent
        }
      } else {
        TunedInGlassPopover {
          searchContent
        }
        .padding(8)
      }
    }
    .navigationTitle(presentation == .page ? "Search" : "")
    .navigationBarTitleDisplayMode(.inline)
    .navigationBarBackButtonHidden(presentation == .page)
    .onChange(of: model.query) { _, query in
      Task {
        try? await Task.sleep(for: .milliseconds(220))
        guard query == model.query else { return }
        await model.search()
      }
    }
    .onAppear {
      guard presentation == .page else { return }
      floatingControls.configureBackOnly(title: "Search") {
        floatingControls.reset()
        dismiss()
      }
    }
    .onDisappear {
      guard presentation == .page else { return }
      floatingControls.reset()
    }
  }

  private var searchContent: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 12) {
        TunedInGlassSearchField(
          text: $model.query,
          prompt: "Search @username",
          style: presentation == .popover ? .neutralPopover : .standard
        )

        if model.query.isEmpty {
          searchHint
        } else if model.isSearching {
          HStack(spacing: 10) {
            ProgressView()
            Text("Searching people…")
              .font(.subheadline)
              .foregroundStyle(TunedInDesign.mutedText)
          }
          .padding(.vertical, 18)
        } else if model.searchResults.isEmpty {
          ContentUnavailableView(
            "No results",
            systemImage: "person.crop.circle.badge.questionmark",
            description: Text("Try another @username.")
          )
        } else {
          LazyVStack(spacing: 0) {
            ForEach(model.searchResults) { profile in
              if let onSelectProfile {
                Button {
                  onSelectProfile(profile)
                } label: {
                  FriendSearchResultRow(profile: profile)
                }
                .buttonStyle(.plain)
              } else {
                NavigationLink {
                  PersonProfileView(
                    profile: profile,
                    currentUserID: currentUserID,
                    currentUsername: currentUsername,
                    socialRepository: socialRepository,
                    concertRepository: concertRepository
                  )
                } label: {
                  FriendSearchResultRow(profile: profile)
                }
                .buttonStyle(.plain)
              }

              if profile.id != model.searchResults.last?.id {
                Divider()
                  .overlay(TunedInDesign.cardBorder.opacity(0.7))
                  .padding(.leading, 64)
              }
            }
          }
          .padding(.top, 6)
        }
      }
      .padding(.horizontal, 20)
      .padding(.top, 12)
      .padding(.bottom, 32)
    }
  }

  private var searchHint: some View {
    Text("Search by @username.")
      .font(.subheadline)
      .foregroundStyle(TunedInDesign.mutedText)
      .padding(.horizontal, 4)
  }
}

struct FriendRequestsView: View {
  let socialRepository: any SocialRepository
  let concertRepository: any ConcertRepository
  let currentUsername: String

  @State private var model: PeopleHubModel

  init(
    socialRepository: any SocialRepository,
    concertRepository: any ConcertRepository,
    currentUsername: String
  ) {
    self.socialRepository = socialRepository
    self.concertRepository = concertRepository
    self.currentUsername = currentUsername
    _model = State(
      initialValue: PeopleHubModel(
        repository: socialRepository,
        currentUsername: currentUsername
      )
    )
  }

  var body: some View {
    ZStack {
      TunedInDesign.pageBackground
        .ignoresSafeArea()

      ScrollView {
        VStack(alignment: .leading, spacing: 18) {
          Text("Requests")
            .font(.system(size: 34, weight: .bold, design: .serif))
            .foregroundStyle(TunedInDesign.primaryText)

          if model.incomingRequests.isEmpty {
            ContentUnavailableView {
              Label("You’re all caught up", systemImage: "checkmark.circle")
            } description: {
              Text("New friend requests will appear here.")
            }
          } else {
            LazyVStack(spacing: 10) {
              ForEach(model.incomingRequests) { profile in
                FriendRequestCard(profile: profile) {
                  Task { await model.perform(.accept, for: profile) }
                } onDecline: {
                  Task { await model.perform(.decline, for: profile) }
                }
              }
            }
          }
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 32)
      }
    }
    .navigationBarTitleDisplayMode(.inline)
    .task { await model.refresh() }
  }
}

@MainActor
@Observable
final class PeopleHubModel {
  var query = ""
  private(set) var searchResults: [SocialProfile] = []
  private(set) var friends: [SocialProfile] = []
  private(set) var incomingRequests: [SocialProfile] = []
  private(set) var isSearching = false
  private(set) var errorMessage: String?

  private let repository: any SocialRepository
  private let currentUsername: String

  init(repository: any SocialRepository, currentUsername: String) {
    self.repository = repository
    self.currentUsername = currentUsername
  }

  func refresh() async {
    do {
      async let friendValues = repository.friends(username: currentUsername)
      async let incomingValues = repository.incomingFriendRequests()
      let (loadedFriends, loadedIncoming) = try await (friendValues, incomingValues)
      friends = loadedFriends
      incomingRequests = loadedIncoming
      errorMessage = nil
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  func search() async {
    guard !query.isEmpty else {
      searchResults = []
      return
    }

    isSearching = true
    do {
      searchResults = try await repository.searchProfiles(usernamePrefix: query)
      errorMessage = nil
    } catch {
      searchResults = []
      errorMessage = error.localizedDescription
    }
    isSearching = false
  }

  func perform(_ action: PersonAction, for profile: SocialProfile) async {
    do {
      try await action.perform(on: repository, profileID: profile.id)
      await refresh()
      await search()
      errorMessage = nil
    } catch {
      errorMessage = error.localizedDescription
    }
  }
}

enum PersonAction: Equatable {
  case send
  case accept
  case decline
  case withdraw
  case removeFriend
  case block
  case unblock

  func perform(on repository: any SocialRepository, profileID: UUID) async throws {
    switch self {
    case .send:
      try await repository.sendFriendRequest(to: profileID)
    case .accept:
      try await repository.acceptFriendRequest(from: profileID)
    case .decline:
      try await repository.declineFriendRequest(from: profileID)
    case .withdraw:
      try await repository.withdrawFriendRequest(to: profileID)
    case .removeFriend:
      try await repository.removeFriend(profileID)
    case .block:
      try await repository.block(profileID)
    case .unblock:
      try await repository.unblock(profileID)
    }
  }
}

struct PersonRow: View {
  let profile: SocialProfile

  var body: some View {
    HStack(spacing: 13) {
      ProfileMonogram(profile: profile, size: 48)
      VStack(alignment: .leading, spacing: 3) {
        Text(profile.displayName)
          .font(.headline)
          .foregroundStyle(TunedInDesign.primaryText)
        Text("@\(profile.username)")
          .font(.subheadline)
          .foregroundStyle(TunedInDesign.mutedText)
      }
      Spacer(minLength: 0)
      RelationshipPill(relationship: profile.relationship)
      Image(systemName: "chevron.right")
        .font(.caption.weight(.bold))
        .foregroundStyle(TunedInDesign.mutedText)
    }
    .padding(13)
    .background(TunedInDesign.cardBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .strokeBorder(TunedInDesign.cardBorder.opacity(0.72))
    }
    .accessibilityElement(children: .combine)
  }
}

private struct FriendSearchResultRow: View {
  let profile: SocialProfile

  var body: some View {
    HStack(spacing: 12) {
      ProfileMonogram(profile: profile, size: 52)
      VStack(alignment: .leading, spacing: 2) {
        Text(profile.username)
          .font(.headline)
          .foregroundStyle(TunedInDesign.primaryText)
        Text(profile.displayName)
          .font(.subheadline)
          .foregroundStyle(TunedInDesign.mutedText)
      }
      Spacer(minLength: 0)
    }
    .padding(.vertical, 10)
    .contentShape(Rectangle())
    .accessibilityElement(children: .combine)
  }
}

private struct FriendRequestCard: View {
  let profile: SocialProfile
  let onAccept: () -> Void
  let onDecline: () -> Void

  var body: some View {
    TunedInGlassSection {
      HStack(spacing: 12) {
        ProfileMonogram(profile: profile, size: 46)
        VStack(alignment: .leading, spacing: 2) {
          Text(profile.displayName)
            .font(.headline)
            .foregroundStyle(TunedInDesign.primaryText)
          Text("@\(profile.username) wants in on your concert life.")
            .font(.caption)
            .foregroundStyle(TunedInDesign.mutedText)
            .lineLimit(2)
        }
      }

      HStack(spacing: 10) {
        Button("Not now", action: onDecline)
          .font(.subheadline.weight(.bold))
          .foregroundStyle(TunedInDesign.primaryText)
          .frame(maxWidth: .infinity)
          .padding(.vertical, 11)
          .background(TunedInDesign.raisedSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

        Button("Accept", action: onAccept)
          .font(.subheadline.weight(.bold))
          .foregroundStyle(TunedInDesign.actionForeground)
          .frame(maxWidth: .infinity)
          .padding(.vertical, 11)
          .background(TunedInDesign.accent, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
      }
      .buttonStyle(.plain)
    }
  }
}

struct ProfileMonogram: View {
  let profile: SocialProfile
  let size: CGFloat

  var body: some View {
    Text(String(profile.displayName.prefix(1)).uppercased())
      .font(.system(size: size * 0.38, weight: .black, design: .rounded))
      .foregroundStyle(TunedInDesign.actionForeground)
      .frame(width: size, height: size)
      .background {
        LinearGradient(
          colors: [TunedInDesign.accent, TunedInDesign.ticketRose],
          startPoint: .topLeading,
          endPoint: .bottomTrailing
        )
      }
      .clipShape(Circle())
      .accessibilityLabel("\(profile.displayName) avatar")
  }
}

struct RelationshipPill: View {
  let relationship: RelationshipState

  var body: some View {
    Text(title)
      .font(.caption2.weight(.bold))
      .foregroundStyle(foreground)
      .padding(.horizontal, 8)
      .padding(.vertical, 6)
      .background(background, in: Capsule())
  }

  private var title: String {
    switch relationship {
    case .none:
      "Discover"
    case .outgoing:
      "Sent"
    case .incoming:
      "Requested"
    case .friends:
      "Friends"
    case .declined:
      "Later"
    case .blocked:
      "Blocked"
    case .unavailable:
      "Private"
    }
  }

  private var foreground: Color {
    relationship == .friends ? TunedInDesign.actionForeground : TunedInDesign.primaryText
  }

  private var background: Color {
    relationship == .friends ? TunedInDesign.accent : TunedInDesign.raisedSurface
  }
}

// swiftlint:enable file_length
