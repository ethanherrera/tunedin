// swiftlint:disable file_length

import Observation
import SwiftUI

struct FriendsListView: View {
  private enum Section: String, CaseIterable {
    case friends = "Friends"
    case requests = "Requests"
  }

  let profileUsername: String
  let currentUserID: UUID
  let currentUsername: String
  let socialRepository: any SocialRepository
  let postRepository: any PostRepository
  let eventRepository: any EventRepository
  let onOpenCommunityEvent: (CommunityEventSummary, UUID?) -> Void
  let onOpenProfile: ((SocialProfile) -> Void)?
  let onDismiss: (() -> Void)?
  let managesFloatingControls: Bool

  @State private var model: PeopleHubModel
  @State private var query = ""
  @State private var selectedSection: Section = .friends
  @State private var floatingControlOwner = UUID()
  @Namespace private var sectionSelectionNamespace
  @Environment(\.dismiss) private var dismiss
  @Environment(\.telemetry) private var telemetry
  @EnvironmentObject private var floatingControls: AppFloatingControls

  init(
    profileUsername: String? = nil,
    currentUserID: UUID,
    currentUsername: String,
    socialRepository: any SocialRepository,
    postRepository: any PostRepository,
    eventRepository: any EventRepository,
    onOpenCommunityEvent: @escaping (CommunityEventSummary, UUID?) -> Void,
    onOpenProfile: ((SocialProfile) -> Void)? = nil,
    onDismiss: (() -> Void)? = nil,
    managesFloatingControls: Bool = true
  ) {
    let requestedProfileUsername = profileUsername ?? currentUsername
    self.profileUsername = requestedProfileUsername
    self.currentUserID = currentUserID
    self.currentUsername = currentUsername
    self.socialRepository = socialRepository
    self.postRepository = postRepository
    self.eventRepository = eventRepository
    self.onOpenCommunityEvent = onOpenCommunityEvent
    self.onOpenProfile = onOpenProfile
    self.onDismiss = onDismiss
    self.managesFloatingControls = managesFloatingControls
    _model = State(
      initialValue: PeopleHubModel(
        repository: socialRepository,
        currentUsername: requestedProfileUsername
      )
    )
  }

  var body: some View {
    ZStack {
      TunedInDesign.pageBackground
        .ignoresSafeArea()

      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          if isOwnList {
            TunedInGlassBottomBar {
              HStack(spacing: 4) {
                ForEach(Section.allCases, id: \.self) { section in
                  Button {
                    withAnimation(.smooth(duration: 0.22)) { selectedSection = section }
                  } label: {
                    HStack(spacing: 6) {
                      Text(section.rawValue)
                      if section == .requests, !model.incomingRequests.isEmpty {
                        Text("\(model.incomingRequests.count)")
                          .font(.caption2.weight(.black))
                          .padding(.horizontal, 6)
                          .padding(.vertical, 3)
                          .background(.white.opacity(0.2), in: Capsule())
                      }
                    }
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(
                      selectedSection == section ? TunedInDesign.actionForeground : TunedInDesign.primaryText
                    )
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background {
                      if selectedSection == section {
                        Capsule()
                          .fill(TunedInDesign.accent)
                          .matchedGeometryEffect(id: "people-section", in: sectionSelectionNamespace)
                      }
                    }
                    .contentShape(.interaction, Capsule())
                  }
                  .buttonStyle(.plain)
                  .contentShape(.interaction, Capsule())
                }
              }
            }
          }

          TunedInGlassSearchField(text: $query, prompt: "Search friends")
            .opacity(selectedSection == .friends ? 1 : 0)
            .frame(height: selectedSection == .friends ? nil : 0)

          if model.isLoading, model.friends.isEmpty, model.incomingRequests.isEmpty {
            friendsSkeleton
          } else if let errorMessage = model.errorMessage,
                    model.friends.isEmpty,
                    model.incomingRequests.isEmpty
          {
            ContentUnavailableView {
              Label("Couldn’t refresh friends", systemImage: "exclamationmark.triangle")
            } description: {
              Text(errorMessage)
            } actions: {
              Button("Try again") { Task { await model.refreshFriends() } }
            }
          } else if selectedSection == .requests {
            requestsContent
          } else if model.friends.isEmpty {
            ContentUnavailableView(
              "No friends yet",
              systemImage: "person.2",
              description: Text("There’s nobody to show here yet.")
            )
            .frame(maxWidth: .infinity)
            .padding(.top, 72)
          } else if filteredFriends.isEmpty {
            ContentUnavailableView(
              "No matching friends",
              systemImage: "magnifyingglass",
              description: Text("Try a different name or @username.")
            )
            .frame(maxWidth: .infinity)
            .padding(.top, 56)
          } else {
            LazyVStack(spacing: 10) {
              ForEach(filteredFriends) { profile in
                friendProfileLink(profile)
              }
            }
          }
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 32)
      }
      .refreshable {
        if isOwnList {
          await model.refresh()
        } else {
          await model.refreshFriends()
        }
      }
    }
    .navigationTitle("Friends")
    .navigationBarTitleDisplayMode(.inline)
    .navigationBarBackButtonHidden()
    .task {
      model.telemetry = telemetry
      if isOwnList {
        await model.load()
      } else {
        await model.loadFriends()
      }
    }
    .onAppear {
      guard managesFloatingControls else { return }
      Task { @MainActor in
        await Task.yield()
        floatingControls.configureBackOnly(title: "Friends", owner: floatingControlOwner) {
          floatingControls.reset()
          close()
        }
      }
    }
    .onDisappear {
      guard managesFloatingControls else { return }
      floatingControls.resetBackOnly(owner: floatingControlOwner)
    }
    .tunedInEdgeSwipeBack {
      floatingControls.reset()
      close()
    }
  }

  private func close() {
    if let onDismiss {
      onDismiss()
    } else {
      dismiss()
    }
  }

  @ViewBuilder
  private var requestsContent: some View {
    if model.incomingRequests.isEmpty {
      ContentUnavailableView {
        Label("You’re all caught up", systemImage: "checkmark.circle")
      } description: {
        Text("New friend requests will appear here.")
      }
      .padding(.top, 48)
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

  private var friendsSkeleton: some View {
    VStack(spacing: 10) {
      ForEach(0 ..< 5, id: \.self) { _ in
        HStack(spacing: 13) {
          TunedInSkeletonBlock(cornerRadius: 24).frame(width: 48, height: 48)
          VStack(alignment: .leading, spacing: 7) {
            TunedInSkeletonBlock(cornerRadius: 5).frame(width: 150, height: 15)
            TunedInSkeletonBlock(cornerRadius: 5).frame(width: 100, height: 12)
          }
          Spacer()
        }
        .padding(13)
      }
    }
    .accessibilityLabel("Loading friends")
  }

  private var isOwnList: Bool {
    profileUsername.caseInsensitiveCompare(currentUsername) == .orderedSame
  }

  private func friendProfileLink(_ profile: SocialProfile) -> some View {
    Group {
      if let onOpenProfile {
        Button { onOpenProfile(profile) } label: {
          PersonRow(profile: profile)
        }
      } else {
        NavigationLink {
          PersonProfileView(
            profile: profile,
            currentUserID: currentUserID,
            currentUsername: currentUsername,
            socialRepository: socialRepository,
            postRepository: postRepository,
            eventRepository: eventRepository,
            onOpenCommunityEvent: onOpenCommunityEvent
          )
        } label: {
          PersonRow(profile: profile)
        }
      }
    }
    .buttonStyle(.plain)
  }

  private var filteredFriends: [SocialProfile] {
    let normalizedQuery = ProfileInput.normalizedSearchQuery(query)
    guard !normalizedQuery.isEmpty else { return model.friends }

    return model.friends.filter { profile in
      profile.displayName.localizedCaseInsensitiveContains(normalizedQuery)
        || profile.username.localizedCaseInsensitiveContains(normalizedQuery)
    }
  }
}

struct FriendRequestsView: View {
  let socialRepository: any SocialRepository
  let postRepository: any PostRepository
  let currentUsername: String

  @State private var model: PeopleHubModel
  @Environment(\.telemetry) private var telemetry

  init(
    socialRepository: any SocialRepository,
    postRepository: any PostRepository,
    currentUsername: String
  ) {
    self.socialRepository = socialRepository
    self.postRepository = postRepository
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

          if let errorMessage = model.errorMessage, model.incomingRequests.isEmpty {
            ContentUnavailableView {
              Label("Couldn’t refresh requests", systemImage: "exclamationmark.triangle")
            } description: {
              Text(errorMessage)
            }
          } else if model.incomingRequests.isEmpty {
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
      .refreshable {
        await model.refresh()
      }
    }
    .navigationBarTitleDisplayMode(.inline)
    .task {
      model.telemetry = telemetry
      await model.load()
    }
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
  private(set) var isLoading = false
  private(set) var errorMessage: String?
  var telemetry: AppTelemetryClient?

  private let repository: any SocialRepository
  private let currentUsername: String

  init(repository: any SocialRepository, currentUsername: String) {
    self.repository = repository
    self.currentUsername = currentUsername
  }

  func loadFriends() async {
    await loadFriends(policy: .automatic)
  }

  func refreshFriends() async {
    await loadFriends(policy: .refresh)
  }

  private func loadFriends(policy: CacheReadPolicy) async {
    isLoading = true
    defer { isLoading = false }
    do {
      friends = try await repository.friends(username: currentUsername, policy: policy)
      errorMessage = nil
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  func load() async {
    await load(policy: .automatic)
  }

  func refresh() async {
    await load(policy: .refresh)
  }

  private func load(policy: CacheReadPolicy) async {
    isLoading = true
    defer { isLoading = false }
    do {
      async let friendValues = repository.friends(username: currentUsername, policy: policy)
      async let incomingValues = repository.incomingFriendRequests(policy: policy)
      let (loadedFriends, loadedIncoming) = try await (friendValues, incomingValues)
      friends = loadedFriends
      incomingRequests = loadedIncoming
      errorMessage = nil
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  func search() async {
    await search(policy: .automatic)
  }

  func refreshSearch() async {
    await search(policy: .refresh)
  }

  private func search(policy: CacheReadPolicy) async {
    let requestedQuery = ProfileInput.normalizedSearchQuery(query)
    guard !requestedQuery.isEmpty else {
      isSearching = false
      searchResults = []
      errorMessage = nil
      return
    }

    isSearching = true
    defer {
      if ProfileInput.normalizedSearchQuery(query) == requestedQuery {
        isSearching = false
      }
    }
    do {
      let results = try await repository.searchProfiles(
        usernamePrefix: requestedQuery,
        policy: policy
      )
      try Task.checkCancellation()
      guard ProfileInput.normalizedSearchQuery(query) == requestedQuery else { return }
      searchResults = results
      errorMessage = nil
    } catch is CancellationError {
      return
    } catch {
      guard ProfileInput.normalizedSearchQuery(query) == requestedQuery else { return }
      errorMessage = error.localizedDescription
    }
  }

  func perform(_ action: PersonAction, for profile: SocialProfile) async {
    let startedAt = ContinuousClock.now
    do {
      try await action.perform(on: repository, profileID: profile.id)
      switch action {
      case .send:
        telemetry?.capture(
          .friendRequestSent,
          properties: [.durationMilliseconds: .integer(startedAt.duration(to: .now).socialTelemetryMilliseconds)]
        )
      case .accept:
        telemetry?.capture(
          .friendRequestAccepted,
          properties: [.durationMilliseconds: .integer(startedAt.duration(to: .now).socialTelemetryMilliseconds)]
        )
      case .decline, .withdraw, .removeFriend, .block, .unblock:
        break
      }
      await refresh()
      await refreshSearch()
      errorMessage = nil
    } catch {
      let failure = AppFailure(error)
      let operation: TelemetryOperation? = switch action {
      case .send: .sendFriendRequest
      case .accept: .acceptFriendRequest
      case .decline, .withdraw, .removeFriend, .block, .unblock: nil
      }
      if failure.shouldReportToTelemetry, let operation {
        telemetry?.captureOperation(
          operation,
          outcome: .failed,
          duration: startedAt.duration(to: .now),
          failure: failure
        )
      }
      errorMessage = error.localizedDescription
    }
  }
}

private extension Duration {
  var socialTelemetryMilliseconds: Int {
    let components = components
    return Int(components.seconds * 1000 + components.attoseconds / 1_000_000_000_000_000)
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
      ProfileAvatarView(profile: profile, size: 48)
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
    .background(
      TunedInDesign.cardBackground,
      in: RoundedRectangle(cornerRadius: TunedInDesign.mediumCornerRadius, style: .continuous)
    )
    .accessibilityElement(children: .combine)
  }
}

struct PeopleSearchResultRow: View {
  let profile: SocialProfile

  var body: some View {
    HStack(spacing: 12) {
      ProfileAvatarView(profile: profile, size: 52)
      VStack(alignment: .leading, spacing: 2) {
        Text("@\(profile.username)")
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
      SocialProfileButton(profile: profile) {
        HStack(spacing: 12) {
          ProfileAvatarView(profile: profile, size: 46)
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
