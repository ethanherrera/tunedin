import SwiftUI

struct EventAttendanceDirectoryView: View {
  let event: CommunityEventSummary
  let viewerID: UUID
  let repository: any EventRepository
  let onDismiss: () -> Void

  @State private var attendances: [EventAttendance] = []
  @State private var cursor: EventAttendanceCursor?
  @State private var hasMore = true
  @State private var isLoading = false
  @State private var didLoad = false
  @State private var errorMessage: String?

  var body: some View {
    ZStack {
      TunedInDesign.pageBackground.ignoresSafeArea()

      ScrollView {
        VStack(alignment: .leading, spacing: 24) {
          VStack(alignment: .leading, spacing: 5) {
            Text(event.phase() == .memories ? "Who went" : "Who’s going")
              .font(.largeTitle.weight(.bold))
              .foregroundStyle(TunedInDesign.primaryText)
            Text(event.title)
              .font(.subheadline.weight(.semibold))
              .foregroundStyle(TunedInDesign.mutedText)
          }

          if !friendAttendances.isEmpty {
            attendanceSection(title: "Friends", attendances: friendAttendances)
          }

          if !communityAttendances.isEmpty {
            attendanceSection(title: "Community", attendances: communityAttendances)
          }

          if attendances.isEmpty, !isLoading, errorMessage == nil {
            Text("No visible plans yet. Private attendance stays private.")
              .font(.subheadline)
              .foregroundStyle(TunedInDesign.mutedText)
              .frame(maxWidth: .infinity, minHeight: 180, alignment: .center)
          }

          paginationControls
        }
        .padding(.horizontal, 20)
        .padding(.top, 22)
        .padding(.bottom, 28)
      }

      EventScrollTopMask()
        .frame(maxHeight: .infinity, alignment: .top)
    }
    .safeAreaInset(edge: .bottom, spacing: 0) {
      EventCollectionBottomBar(title: event.title, onDismiss: onDismiss)
    }
    .task {
      guard !didLoad else { return }
      didLoad = true
      await loadMore()
    }
  }

  private var friendAttendances: [EventAttendance] {
    sortedAttendances.filter {
      $0.profile.id == viewerID || $0.profile.relationship == .friends
    }
  }

  private var communityAttendances: [EventAttendance] {
    sortedAttendances.filter {
      $0.profile.id != viewerID && $0.profile.relationship != .friends
    }
  }

  private var sortedAttendances: [EventAttendance] {
    attendances.sorted { lhs, rhs in
      let lhsRank = lhs.profile.id == viewerID ? 0 : (lhs.profile.relationship == .friends ? 1 : 2)
      let rhsRank = rhs.profile.id == viewerID ? 0 : (rhs.profile.relationship == .friends ? 1 : 2)
      if lhsRank != rhsRank { return lhsRank < rhsRank }
      return lhs.profile.displayName.localizedCaseInsensitiveCompare(rhs.profile.displayName)
        == .orderedAscending
    }
  }

  private func attendanceSection(
    title: String,
    attendances: [EventAttendance]
  ) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack(spacing: 7) {
        Text(title)
          .font(.headline)
          .foregroundStyle(TunedInDesign.primaryText)
        Text("\(attendances.count)")
          .font(.caption2.weight(.bold))
          .foregroundStyle(TunedInDesign.mutedText)
      }
      .padding(.bottom, 5)

      ForEach(attendances) { attendance in
        SocialProfileButton(profile: attendance.profile) {
          HStack(spacing: 12) {
            ProfileAvatarView(profile: attendance.profile, size: 48)
            VStack(alignment: .leading, spacing: 3) {
              Text(attendance.profile.id == viewerID ? "You" : attendance.profile.displayName)
                .font(.body.weight(.semibold))
                .foregroundStyle(TunedInDesign.primaryText)
              Text("@\(attendance.profile.username)")
                .font(.caption)
                .foregroundStyle(TunedInDesign.mutedText)
            }
            Spacer(minLength: 8)
            Text(attendance.status == .went ? "Went" : "Going")
              .font(.caption.weight(.bold))
              .foregroundStyle(TunedInDesign.accent)
          }
          .padding(.vertical, 9)
          .contentShape(Rectangle())
        }

        if attendance.id != attendances.last?.id {
          Divider().overlay(TunedInDesign.cardBorder)
            .padding(.leading, 60)
        }
      }
    }
  }

  @ViewBuilder
  private var paginationControls: some View {
    if let errorMessage {
      VStack(spacing: 10) {
        Text(errorMessage)
          .font(.caption)
          .foregroundStyle(TunedInDesign.mutedText)
          .multilineTextAlignment(.center)
        Button("Try again") { Task { await loadMore() } }
          .font(.subheadline.weight(.bold))
      }
      .frame(maxWidth: .infinity)
      .padding(.vertical, 12)
    } else if isLoading {
      ProgressView()
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    } else if hasMore {
      Button { Task { await loadMore() } } label: {
        Label("Load more people", systemImage: "chevron.down")
          .font(.subheadline.weight(.bold))
          .frame(maxWidth: .infinity)
          .padding(.vertical, 12)
      }
      .buttonStyle(.bordered)
      .buttonBorderShape(.capsule)
    }
  }

  @MainActor
  private func loadMore() async {
    guard !isLoading, hasMore else { return }
    isLoading = true
    defer { isLoading = false }
    do {
      let page = try await repository.eventAttendances(
        eventID: event.id,
        viewerID: viewerID,
        cursor: cursor,
        limit: 24
      )
      let existingIDs = Set(attendances.map(\.id))
      attendances.append(contentsOf: page.items.filter { !existingIDs.contains($0.id) })
      cursor = page.nextCursor
      hasMore = page.nextCursor != nil
      errorMessage = nil
    } catch {
      errorMessage = error.localizedDescription
    }
  }
}

struct EventPostGalleryView: View {
  let event: CommunityEventSummary
  let viewerID: UUID
  let repository: any EventRepository
  let concertRepository: (any ConcertRepository)?
  let onChanged: () -> Void
  let onDismiss: () -> Void

  @State private var posts: [EventDiaryPreview] = []
  @State private var cursor: EventDiaryCursor?
  @State private var hasMore = true
  @State private var isLoading = false
  @State private var didLoad = false
  @State private var errorMessage: String?
  @State private var selectedPost: EventDiaryPreview?

  private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 3)

  var body: some View {
    ZStack {
      TunedInDesign.pageBackground.ignoresSafeArea()

      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          VStack(alignment: .leading, spacing: 5) {
            Text("Posts")
              .font(.largeTitle.weight(.bold))
              .foregroundStyle(TunedInDesign.primaryText)
            Text("\(event.title) · \(event.diaryCount) visible")
              .font(.subheadline.weight(.semibold))
              .foregroundStyle(TunedInDesign.mutedText)
          }
          .padding(.horizontal, 20)

          if posts.isEmpty, !isLoading, errorMessage == nil {
            Text("No posts yet.")
              .font(.subheadline)
              .foregroundStyle(TunedInDesign.mutedText)
              .frame(maxWidth: .infinity, minHeight: 180, alignment: .center)
              .padding(.horizontal, 20)
          } else if let concertRepository {
            LazyVGrid(columns: columns, spacing: 2) {
              ForEach(posts) { post in
                EventPostGridTile(
                  post: post,
                  viewerID: viewerID,
                  concertRepository: concertRepository,
                  onOpen: { selectedPost = post }
                )
              }
            }
          }

          paginationControls
            .padding(.horizontal, 20)
        }
        .padding(.top, 22)
        .padding(.bottom, 28)
      }

      EventScrollTopMask()
        .frame(maxHeight: .infinity, alignment: .top)
    }
    .safeAreaInset(edge: .bottom, spacing: 0) {
      EventCollectionBottomBar(title: "Posts", onDismiss: onDismiss)
    }
    .fullScreenCover(item: $selectedPost) { post in
      if let concertRepository {
        EventDiaryDetailView(
          event: event,
          diary: post,
          viewerID: viewerID,
          concertRepository: concertRepository,
          onChanged: onChanged,
          onDismiss: { selectedPost = nil }
        )
      }
    }
    .task {
      guard !didLoad else { return }
      didLoad = true
      await loadMore()
    }
  }

  @ViewBuilder
  private var paginationControls: some View {
    if let errorMessage {
      VStack(spacing: 10) {
        Text(errorMessage)
          .font(.caption)
          .foregroundStyle(TunedInDesign.mutedText)
          .multilineTextAlignment(.center)
        Button("Try again") { Task { await loadMore() } }
          .font(.subheadline.weight(.bold))
      }
      .frame(maxWidth: .infinity)
      .padding(.vertical, 12)
    } else if isLoading {
      ProgressView()
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    } else if hasMore {
      Button { Task { await loadMore() } } label: {
        Label("Load more posts", systemImage: "chevron.down")
          .font(.subheadline.weight(.bold))
          .frame(maxWidth: .infinity)
          .padding(.vertical, 12)
      }
      .buttonStyle(.bordered)
      .buttonBorderShape(.capsule)
    }
  }

  @MainActor
  private func loadMore() async {
    guard !isLoading, hasMore else { return }
    isLoading = true
    defer { isLoading = false }
    do {
      let page = try await repository.eventDiaries(
        eventID: event.id,
        viewerID: viewerID,
        cursor: cursor,
        limit: 24
      )
      let existingIDs = Set(posts.map(\.id))
      posts.append(contentsOf: page.items.filter { !existingIDs.contains($0.id) })
      cursor = page.nextCursor
      hasMore = page.nextCursor != nil
      errorMessage = nil
    } catch {
      errorMessage = error.localizedDescription
    }
  }
}
