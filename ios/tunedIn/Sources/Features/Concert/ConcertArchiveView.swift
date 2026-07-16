// swiftlint:disable file_length

import Observation
import SwiftUI
import UIKit

struct ConcertArchiveView: View {
  let profileID: UUID
  let viewerID: UUID
  let viewerUsername: String
  let isOwner: Bool
  let concertRepository: any ConcertRepository
  let socialRepository: any SocialRepository
  let model: ConcertArchiveModel
  let refreshToken: Int

  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @Namespace private var concertTransitionNamespace

  var body: some View {
    @Bindable var model = model

    VStack(alignment: .leading, spacing: 16) {
      ViewThatFits(in: .horizontal) {
        HStack(alignment: .top, spacing: 16) {
          archiveHeading
          Spacer(minLength: 4)
          archiveFilterMenu
        }

        VStack(alignment: .leading, spacing: 12) {
          archiveHeading
          archiveFilterMenu
        }
      }

      TunedInGlassSearchField(text: $model.query.searchText, prompt: "Search artists, venues, cities")

      if model.isLoading, model.concerts.isEmpty {
        LazyVGrid(columns: archiveColumns, spacing: 12) {
          ForEach(0 ..< (dynamicTypeSize.isAccessibilitySize ? 3 : 4), id: \.self) { _ in
            TunedInSkeletonBlock(cornerRadius: 20)
              .frame(height: dynamicTypeSize.isAccessibilitySize ? 230 : 216)
          }
        }
        .accessibilityLabel("Loading concerts")
      } else if let errorMessage = model.errorMessage, model.concerts.isEmpty {
        ContentUnavailableView {
          Label("Couldn’t load this archive", systemImage: "exclamationmark.triangle")
        } description: {
          Text(errorMessage)
        } actions: {
          Button("Try again") {
            Task { await model.reload(policy: .refresh) }
          }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
      } else if model.concerts.isEmpty {
        archiveEmptyState
      } else {
        VStack(alignment: .leading, spacing: 12) {
          if let errorMessage = model.errorMessage {
            Label(errorMessage, systemImage: "exclamationmark.triangle")
              .font(.caption)
              .foregroundStyle(.orange)
              .frame(maxWidth: .infinity, alignment: .leading)
          }

          LazyVGrid(columns: archiveColumns, spacing: 12) {
            ForEach(model.concerts) { preview in
              NavigationLink {
                ConcertDetailView(
                  concertID: preview.id,
                  viewerID: viewerID,
                  viewerUsername: viewerUsername,
                  concertRepository: concertRepository,
                  socialRepository: socialRepository
                )
                .tunedInNavigationZoom(
                  sourceID: preview.id,
                  in: concertTransitionNamespace
                )
              } label: {
                ConcertArchiveRow(preview: preview, repository: concertRepository)
                  .tunedInMatchedNavigationSource(
                    id: preview.id,
                    in: concertTransitionNamespace
                  )
              }
              .buttonStyle(TunedInPosterButtonStyle())
              .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
              .accessibilityLabel("Open \(preview.primaryArtistName)")
            }
          }

          if model.canLoadMore {
            Button {
              Task { await model.loadMore() }
            } label: {
              HStack(spacing: 8) {
                if model.isLoadingMore {
                  ProgressView()
                }
                Text(model.isLoadingMore ? "Loading more concerts…" : "Show more concerts")
              }
              .font(.subheadline.weight(.bold))
              .foregroundStyle(TunedInDesign.primaryText)
              .frame(maxWidth: .infinity)
              .padding(.vertical, 14)
              .background(TunedInDesign.raisedSurface, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(model.isLoadingMore)
          }
        }
      }
    }
    .task(id: refreshToken) {
      await model.reload(policy: refreshToken == 0 ? .automatic : .refresh)
    }
    .onChange(of: model.query.searchText) { _, searchText in
      Task {
        try? await Task.sleep(for: .milliseconds(250))
        guard searchText == model.query.searchText else { return }
        await model.reload()
      }
    }
  }

  private var archiveHeading: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(isOwner ? "Kept" : "Concerts")
        .font(.largeTitle.weight(.bold))
        .foregroundStyle(TunedInDesign.primaryText)
      Text(isOwner ? "Your nights, remembered." : "Nights shared with you.")
        .font(.subheadline)
        .foregroundStyle(TunedInDesign.mutedText)
    }
    .accessibilityElement(children: .combine)
  }

  private var archiveFilterMenu: some View {
    Menu {
      Menu("Visibility") {
        Button("All visibility") {
          setVisibilityFilter(nil)
        }
        if isOwner {
          Button("Private") {
            setVisibilityFilter(.private)
          }
        }
        Button("Collaborators") {
          setVisibilityFilter(.collaborators)
        }
        Button("With friends") {
          setVisibilityFilter(.friends)
        }
      }

      Menu("Year") {
        Button("All years") {
          setYearFilter(nil)
        }
        ForEach(yearOptions, id: \.self) { year in
          Button(String(year)) {
            setYearFilter(year)
          }
        }
      }

      Section("Sort") {
        ForEach(ConcertHistorySort.allCases, id: \.self) { sort in
          Button {
            setSort(sort)
          } label: {
            if model.query.sort == sort {
              Label(sort.displayTitle, systemImage: "checkmark")
            } else {
              Text(sort.displayTitle)
            }
          }
        }
      }
    } label: {
      HStack(spacing: 7) {
        Image(systemName: "slider.horizontal.3")
        Text(archiveMenuLabel)
          .lineLimit(1)
      }
      .font(.subheadline.weight(.semibold))
      .foregroundStyle(TunedInDesign.primaryText)
      .padding(.horizontal, 13)
      .frame(minHeight: 40)
      .background(TunedInDesign.raisedSurface, in: Capsule())
    }
    .accessibilityLabel("Filter archive, \(archiveMenuLabel)")
  }

  private var archiveColumns: [GridItem] {
    let count = dynamicTypeSize.isAccessibilitySize ? 1 : 2
    return Array(
      repeating: GridItem(.flexible(minimum: 0), spacing: 12, alignment: .top),
      count: count
    )
  }

  private var archiveMenuLabel: String {
    let selections = [
      model.query.year.map(String.init),
      model.query.visibility?.archiveTitle,
      model.query.sort == .newest ? nil : model.query.sort.displayTitle
    ].compactMap(\.self)

    if selections.count == 1 {
      return selections[0]
    }
    return selections.isEmpty ? "All" : "\(selections.count) selected"
  }

  private var yearOptions: [Int] {
    let currentYear = Calendar.current.component(.year, from: .now)
    return Array((1950 ... currentYear + 1).reversed())
  }

  private var archiveEmptyState: some View {
    ContentUnavailableView {
      Label(
        model.query.searchText.isEmpty ? "No concerts yet" : "No matches",
        systemImage: model.query.searchText.isEmpty ? "music.quarternote.3" : "magnifyingglass"
      )
    } description: {
      Text(
        model.query.searchText.isEmpty
          ? "Use the plus button to remember your first night."
          : "Try an artist, venue, or city."
      )
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 28)
  }

  private func setVisibilityFilter(_ visibility: ConcertVisibility?) {
    model.query.visibility = visibility
    Task { await model.reload() }
  }

  private func setYearFilter(_ year: Int?) {
    model.query.year = year
    Task { await model.reload() }
  }

  private func setSort(_ sort: ConcertHistorySort) {
    model.query.sort = sort
    Task { await model.reload() }
  }
}

@MainActor
@Observable
final class ConcertArchiveModel {
  var query = ConcertHistoryQuery()
  private(set) var concerts: [ConcertPreview] = []
  private(set) var isLoading = false
  private(set) var isLoadingMore = false
  private(set) var canLoadMore = false
  private(set) var errorMessage: String?

  private let profileID: UUID
  private let concertRepository: any ConcertRepository

  init(profileID: UUID, concertRepository: any ConcertRepository) {
    self.profileID = profileID
    self.concertRepository = concertRepository
  }

  func reload(policy: CacheReadPolicy = .automatic) async {
    guard !isLoading else { return }
    isLoading = true
    errorMessage = nil

    var requestedQuery: ConcertHistoryQuery
    repeat {
      requestedQuery = query
      do {
        let loaded = try await concertRepository.profileConcertHistory(
          profileID: profileID,
          query: requestedQuery,
          cursor: nil,
          policy: policy
        )
        guard requestedQuery == query else { continue }
        concerts = loaded
        canLoadMore = loaded.count == 30
      } catch {
        guard requestedQuery == query else { continue }
        let failure = AppFailure(error)
        if failure == .permissionDenied || failure == .unavailable {
          concerts = []
        }
        canLoadMore = false
        errorMessage = error.localizedDescription
      }
    } while requestedQuery != query

    isLoading = false
  }

  func loadMore() async {
    guard let lastConcert = concerts.last, !isLoadingMore else { return }
    isLoadingMore = true

    do {
      let loaded = try await concertRepository.profileConcertHistory(
        profileID: profileID,
        query: query,
        cursor: ConcertHistoryCursor(preview: lastConcert, sort: query.sort),
        policy: .networkOnly
      )
      let existingIDs = Set(concerts.map(\.id))
      concerts.append(contentsOf: loaded.filter { !existingIDs.contains($0.id) })
      canLoadMore = loaded.count == 30
    } catch {
      errorMessage = error.localizedDescription
    }

    isLoadingMore = false
  }
}

private extension ConcertVisibility {
  var archiveTitle: String {
    switch self {
    case .private: "Private"
    case .collaborators: "Collaborators"
    case .friends: "Friends"
    }
  }
}

private struct ConcertArchiveRow: View {
  let preview: ConcertPreview
  let repository: any ConcertRepository

  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  var body: some View {
    ZStack(alignment: .bottomLeading) {
      ConcertPhotoView(concert: preview.concert, artistName: preview.primaryArtistName, repository: repository)
        .frame(maxWidth: .infinity)
        .frame(height: cardHeight)
        .overlay {
          LinearGradient(
            stops: [
              .init(color: .black.opacity(0.08), location: 0),
              .init(color: .clear, location: 0.34),
              .init(color: .black.opacity(0.82), location: 1)
            ],
            startPoint: .top,
            endPoint: .bottom
          )
        }

      VStack(alignment: .leading, spacing: 5) {
        Text(preview.primaryArtistName)
          .font(.title3.weight(.bold))
          .foregroundStyle(.white)
          .lineLimit(2)
        Text(ConcertDisplay.longDate(from: preview.concert.concertDate))
          .font(.caption.weight(.semibold))
          .foregroundStyle(.white.opacity(0.82))
          .lineLimit(1)
        Text([preview.concert.venueName, preview.concert.city].compactMap(\.self).joined(separator: " · "))
          .font(.caption)
          .foregroundStyle(.white.opacity(0.78))
          .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
      }
      .padding(14)

      visibilityMark
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
    }
    .frame(height: cardHeight)
    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    .shadow(color: .black.opacity(0.12), radius: 12, y: 6)
    .frame(maxWidth: .infinity)
    .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    .accessibilityElement(children: .combine)
  }

  private var cardHeight: CGFloat {
    dynamicTypeSize.isAccessibilitySize ? 236 : 224
  }

  private var visibilityMark: some View {
    Group {
      switch preview.concert.visibility {
      case .private:
        Image(systemName: "lock.fill")
          .foregroundStyle(.white)
          .accessibilityLabel("Private")
      case .collaborators:
        Image(systemName: "person.2.fill")
          .foregroundStyle(.white)
          .accessibilityLabel("Collaborators")
      case .friends:
        Image(systemName: "heart.fill")
          .foregroundStyle(.white)
          .accessibilityLabel("Friends")
      }
    }
    .font(.caption.weight(.bold))
    .frame(width: 30, height: 30)
    .background(.black.opacity(0.34), in: Circle())
  }
}

enum ConcertDetailPage: CaseIterable, Hashable {
  case concert
  case people
  case photos

  var title: String {
    switch self {
    case .concert: "Concert"
    case .people: "People"
    case .photos: "Photos"
    }
  }

  var icon: String {
    switch self {
    case .concert: "music.note"
    case .people: "person.2.fill"
    case .photos: "photo.on.rectangle.angled"
    }
  }
}

private struct ConcertHeroScrollPositionKey: PreferenceKey {
  static let defaultValue: CGFloat = 0

  static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
    value = nextValue()
  }
}

private struct ConcertHeroScrollTrackingModifier: ViewModifier {
  @Binding var progress: CGFloat

  @ViewBuilder
  func body(content: Content) -> some View {
    if #available(iOS 18.0, *) {
      content.onScrollGeometryChange(for: CGFloat.self) { geometry in
        max(geometry.contentOffset.y + geometry.contentInsets.top, 0)
      } action: { _, offset in
        progress = min(max(offset / 420, 0), 1)
      }
    } else {
      content.onPreferenceChange(ConcertHeroScrollPositionKey.self) { minY in
        progress = min(max(-minY / 420, 0), 1)
      }
    }
  }
}

// swiftlint:disable:next type_body_length
struct ConcertDetailView: View {
  private enum ArtworkStyle: Equatable {
    case full
    case preview
  }

  let concertID: UUID
  let viewerID: UUID
  let viewerUsername: String
  let concertRepository: any ConcertRepository
  let socialRepository: any SocialRepository

  @Environment(\.dismiss) private var dismiss
  @Environment(\.telemetry) private var telemetry
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @EnvironmentObject private var concertFloatingControls: ConcertFloatingControls
  @State private var detail: ConcertDetail?
  @State private var errorMessage: String?
  @State private var isShowingEditor = false
  @State private var isShowingMoments = false
  @State private var momentsDetent = PresentationDetent.medium
  @State private var selectedPage: ConcertDetailPage = .concert
  @State private var isShowingDeleteConfirmation = false
  @State private var isShowingFinalDeleteConfirmation = false
  @State private var isDeleting = false
  @State private var hasRemoteChanges = false
  @State private var isApplyingRemoteChanges = false
  @State private var albumRefreshToken = 0
  @State private var heroCollapseProgress: CGFloat = 0
  @State private var commentsModel: ConcertCommentsModel

  init(
    concertID: UUID,
    viewerID: UUID,
    viewerUsername: String,
    concertRepository: any ConcertRepository,
    socialRepository: any SocialRepository
  ) {
    self.concertID = concertID
    self.viewerID = viewerID
    self.viewerUsername = viewerUsername
    self.concertRepository = concertRepository
    self.socialRepository = socialRepository
    _commentsModel = State(
      initialValue: ConcertCommentsModel(concertID: concertID, concertRepository: concertRepository)
    )
  }

  var body: some View {
    ZStack {
      TunedInDesign.pageBackground
        .ignoresSafeArea()

      if let detail {
        switch selectedPage {
        case .concert:
          concertContent(detail)
        case .people:
          ConcertPeopleView(
            detail: detail,
            viewerRole: viewerRole,
            viewerID: viewerID,
            viewerUsername: viewerUsername,
            socialRepository: socialRepository,
            concertRepository: concertRepository,
            onChanged: {
              Task { await loadDetail(policy: .refresh) }
            },
            pageHeader: AnyView(concertHeader(detail, artworkStyle: .preview)),
            onRefresh: { await loadDetail(policy: .refresh) }
          )
        case .photos:
          ConcertAlbumView(
            detail: detail,
            viewerID: viewerID,
            viewerRole: viewerRole,
            concertRepository: concertRepository,
            pageHeader: AnyView(concertHeader(detail, artworkStyle: .preview)),
            refreshToken: albumRefreshToken,
            onRefresh: { await loadDetail(policy: .refresh) }
          )
        }
      } else if let errorMessage {
        ScrollView {
          ContentUnavailableView {
            Label("This concert isn’t available", systemImage: "lock.trianglebadge.exclamationmark")
          } description: {
            Text(errorMessage)
          } actions: {
            Button("Try again") {
              Task { await loadDetail(policy: .refresh) }
            }
          }
          .frame(minHeight: 520)
        }
        .refreshable { await loadDetail() }
      } else {
        ScrollView {
          VStack(alignment: .leading, spacing: 18) {
            TunedInSkeletonBlock(cornerRadius: 24)
              .aspectRatio(CGSize(width: 4, height: 5), contentMode: .fit)
            TunedInSkeletonBlock(cornerRadius: 7).frame(width: 150, height: 20)
            TunedInSkeletonBlock(cornerRadius: 18).frame(height: 140)
            TunedInSkeletonBlock(cornerRadius: 18).frame(height: 110)
          }
          .padding(.horizontal, 20)
          .padding(.bottom, TunedInDesign.scrollContentBottomInset + 24)
        }
        .accessibilityLabel("Opening concert")
      }
    }
    .overlay(alignment: .top) {
      VStack(spacing: 8) {
        if hasRemoteChanges {
          updatesAvailableButton
        }
        if let detail,
           selectedPage == .concert,
           heroCollapseProgress >= 0.82 {
          compactConcertIdentity(detail)
            .transition(
              TunedInMotion.compactIdentityTransition(reduceMotion: reduceMotion)
            )
        }
      }
      .padding(.horizontal, 20)
      .padding(.top, 10)
      .animation(
        TunedInMotion.navigation(reduceMotion: reduceMotion),
        value: heroCollapseProgress >= 0.82
      )
    }
    .toolbar(.hidden, for: .navigationBar)
    .onAppear { configureFloatingControls() }
    .onChange(of: viewerRole) { _, _ in configureFloatingControls() }
    .onDisappear { concertFloatingControls.reset() }
    .task(id: concertID) {
      await loadDetail(policy: .automatic)
    }
    .task(id: concertID) {
      for await _ in concertRepository.observeConcert(id: concertID) {
        hasRemoteChanges = true
      }
    }
    .sheet(isPresented: $isShowingEditor) {
      if let detail {
        ConcertEditView(
          detail: detail,
          canMakePrivate: viewerRole == .owner,
          concertRepository: concertRepository,
          loadLatestDetail: {
            try await concertRepository.fetchConcertDetail(
              id: concertID,
              viewerID: viewerID,
              policy: .networkOnly
            )
          },
          onSaved: { _ in
            Task { await loadDetail(policy: .refresh) }
          }
        )
      }
    }
    .sheet(isPresented: $isShowingMoments) {
      ConcertCommentsView(
        concertID: concertID,
        viewerID: viewerID,
        viewerUsername: viewerUsername,
        concertRepository: concertRepository,
        model: commentsModel,
        selectedDetent: $momentsDetent
      )
      .presentationDetents([.medium, .large], selection: $momentsDetent)
      .presentationDragIndicator(.visible)
      .presentationCornerRadius(30)
    }
    .confirmationDialog(
      "Delete this concert?",
      isPresented: $isShowingDeleteConfirmation,
      titleVisibility: .visible
    ) {
      Button("Continue", role: .destructive) {
        isShowingFinalDeleteConfirmation = true
      }
    } message: {
      Text(deleteImpactMessage)
    }
    .alert("Delete it permanently?", isPresented: $isShowingFinalDeleteConfirmation) {
      Button("Delete concert", role: .destructive) {
        deleteConcert()
      }
      Button("Keep it", role: .cancel) {}
    } message: {
      Text("This cannot be undone.")
    }
  }

  private func concertHero(_ detail: ConcertDetail) -> some View {
    let artistName = detail.artists.first(where: \.isPrimary)?.name ?? "A saved night"

    return ZStack(alignment: .bottomLeading) {
      ConcertPhotoView(concert: detail.concert, artistName: artistName, repository: concertRepository)
        .frame(maxWidth: .infinity)
        .aspectRatio(CGSize(width: 4, height: 5), contentMode: .fit)
        .overlay {
          LinearGradient(
            stops: [
              .init(color: .black.opacity(0.12), location: 0),
              .init(color: .clear, location: 0.36),
              .init(color: .black.opacity(0.86), location: 1)
            ],
            startPoint: .top,
            endPoint: .bottom
          )
        }

      VStack(alignment: .leading, spacing: 8) {
        Text(ConcertDisplay.longDate(from: detail.concert.concertDate))
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(.white.opacity(0.84))
        Text(artistName)
          .font(.system(.largeTitle, design: .serif).weight(.bold))
          .foregroundStyle(.white)
          .lineLimit(2)

        HStack(spacing: 7) {
          Image(systemName: "mappin")
            .font(.caption.weight(.bold))
          Text([detail.concert.venueName, detail.concert.city].compactMap(\.self).joined(separator: " · "))
            .lineLimit(2)
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.white.opacity(0.9))
      }
      .padding(.horizontal, 20)
      .padding(.bottom, 24)
    }
    .scaleEffect(
      x: 1 - (heroCollapseProgress * 0.045),
      y: 1 - (heroCollapseProgress * 0.045),
      anchor: .top
    )
    .opacity(1 - (heroCollapseProgress * 0.18))
    .accessibilityElement(children: .combine)
  }

  private func compactConcertIdentity(_ detail: ConcertDetail) -> some View {
    let artistName = detail.artists.first(where: \.isPrimary)?.name ?? "A saved night"
    let location = [detail.concert.venueName, detail.concert.city]
      .compactMap(\.self)
      .joined(separator: " · ")

    return TunedInGlassIdentitySurface {
      HStack(spacing: 10) {
        Image(systemName: "music.note")
          .font(.caption.weight(.bold))
          .foregroundStyle(TunedInDesign.selectedControlForeground)
          .frame(width: 28, height: 28)
          .background(TunedInDesign.accentTint, in: Circle())

        VStack(alignment: .leading, spacing: 1) {
          Text(artistName)
            .font(.subheadline.weight(.bold))
            .foregroundStyle(TunedInDesign.primaryText)
            .lineLimit(1)
          Text(location)
            .font(.caption2)
            .foregroundStyle(TunedInDesign.mutedText)
            .lineLimit(1)
        }
      }
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel("\(artistName), \(location)")
  }

  private func concertPreview(_ detail: ConcertDetail) -> some View {
    let artistName = detail.artists.first(where: \.isPrimary)?.name ?? "A saved night"

    return ZStack(alignment: .bottomLeading) {
      ConcertPhotoView(concert: detail.concert, artistName: artistName, repository: concertRepository)
        .frame(maxWidth: .infinity)
        .frame(height: 160)
        .overlay {
          LinearGradient(
            colors: [.clear, .black.opacity(0.82)],
            startPoint: .top,
            endPoint: .bottom
          )
        }

      VStack(alignment: .leading, spacing: 3) {
        Text(ConcertDisplay.longDate(from: detail.concert.concertDate).uppercased())
          .font(.caption2.weight(.bold))
          .foregroundStyle(.white.opacity(0.84))
        Text(artistName)
          .font(.system(.title2, design: .serif).weight(.bold))
          .foregroundStyle(.white)
          .lineLimit(1)
        Text(detail.concert.venueName)
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(.white.opacity(0.92))
          .lineLimit(1)
      }
      .padding(16)
    }
    .frame(height: 160)
    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    .accessibilityElement(children: .combine)
  }

  private func concertContent(_ detail: ConcertDetail) -> some View {
    ScrollViewReader { scrollProxy in
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 0) {
          concertHeader(detail, artworkStyle: .full)
            .id("concert-hero")
            .background {
              GeometryReader { proxy in
                Color.clear.preference(
                  key: ConcertHeroScrollPositionKey.self,
                  value: proxy.frame(in: .named("concert-detail-scroll")).minY
                )
              }
            }
          concertEditorialSections(detail) {
            openMoments(from: scrollProxy)
          }
          .padding(.horizontal, 20)
          .padding(.top, 24)
          .padding(.bottom, TunedInDesign.scrollContentBottomInset + 28)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      .coordinateSpace(name: "concert-detail-scroll")
      .modifier(ConcertHeroScrollTrackingModifier(progress: $heroCollapseProgress))
      .ignoresSafeArea(edges: .top)
      .refreshable {
        await loadDetail(policy: .refresh)
        await commentsModel.loadComments(policy: .refresh)
        if errorMessage == nil, commentsModel.loadErrorMessage == nil {
          hasRemoteChanges = false
        }
      }
    }
  }

  private func concertEditorialSections(
    _ detail: ConcertDetail,
    openMoments: @escaping () -> Void
  ) -> some View {
    VStack(alignment: .leading, spacing: 26) {
      if let tour = detail.concert.tour {
        HStack(spacing: 8) {
          Image(systemName: "sparkles")
          Text(tour)
            .lineLimit(2)
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(TunedInDesign.accent)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(TunedInDesign.accentTint, in: Capsule())
      }

      if detail.artists.count > 1 {
        detailSection(title: "Lineup") {
          ForEach(detail.artists) { artist in
            HStack(alignment: .firstTextBaseline, spacing: 12) {
              Text(artist.isPrimary ? "HEADLINER" : "WITH")
                .font(.caption2.weight(.bold))
                .foregroundStyle(artist.isPrimary ? TunedInDesign.accent : TunedInDesign.mutedText)
                .frame(width: 72, alignment: .leading)
              Text(artist.name)
                .font(.body.weight(.semibold))
                .foregroundStyle(TunedInDesign.primaryText)
            }
          }
        }
      }

      detailSection(title: "Setlist") {
        if detail.setlist.isEmpty {
          Text("No setlist saved for this night yet.")
            .font(.subheadline)
            .foregroundStyle(TunedInDesign.mutedText)
        } else {
          ForEach(detail.setlist) { entry in
            setlistRow(entry)
          }
        }
      }

      detailSection(title: "Venue") {
        venueRow(detail)
      }

      commentsSection(openMoments: openMoments)
    }
  }

  private func setlistRow(_ entry: SetlistEntry) -> some View {
    VStack(spacing: 11) {
      HStack(alignment: .firstTextBaseline, spacing: 12) {
        Text("\(entry.position)")
          .font(.caption.weight(.bold).monospacedDigit())
          .foregroundStyle(TunedInDesign.accent)
          .frame(width: 24, alignment: .leading)
        Text(entry.title)
          .font(.body.weight(.medium))
          .foregroundStyle(TunedInDesign.primaryText)
        Spacer(minLength: 0)
      }
      Divider()
        .overlay(TunedInDesign.cardBorder.opacity(0.45))
    }
  }

  private func venueRow(_ detail: ConcertDetail) -> some View {
    HStack(alignment: .center, spacing: 13) {
      Image(systemName: "mappin.and.ellipse")
        .font(.headline)
        .foregroundStyle(TunedInDesign.accent)
        .frame(width: 42, height: 42)
        .background(TunedInDesign.accentTint, in: Circle())

      VStack(alignment: .leading, spacing: 3) {
        Text(detail.concert.venueName)
          .font(.headline)
          .foregroundStyle(TunedInDesign.primaryText)
        if let city = detail.concert.city {
          Text(city)
            .font(.subheadline)
            .foregroundStyle(TunedInDesign.mutedText)
        }
      }
      Spacer(minLength: 0)
    }
  }

  private func commentsSection(openMoments: @escaping () -> Void) -> some View {
    VStack(alignment: .leading, spacing: 14) {
      Divider()
        .overlay(TunedInDesign.cardBorder.opacity(0.55))
      Button(action: openMoments) {
        HStack(spacing: 13) {
          Image(systemName: "bubble.left.and.bubble.right.fill")
            .font(.headline)
            .foregroundStyle(TunedInDesign.accent)
            .frame(width: 44, height: 44)
            .background(TunedInDesign.accentTint, in: Circle())

          VStack(alignment: .leading, spacing: 3) {
            Text("Moments")
              .font(.title3.weight(.bold))
              .foregroundStyle(TunedInDesign.primaryText)
            Text(momentsSummary)
              .font(.subheadline)
              .foregroundStyle(TunedInDesign.mutedText)
          }
          Spacer()
          Image(systemName: "chevron.up")
            .font(.caption.weight(.bold))
            .foregroundStyle(TunedInDesign.mutedText)
        }
        .padding(16)
        .background(TunedInDesign.cardBackground, in: RoundedRectangle(cornerRadius: 20))
      }
      .buttonStyle(.plain)
      .accessibilityHint("Opens the conversation while keeping this concert visible")
    }
  }

  private var momentsSummary: String {
    if commentsModel.isLoading {
      return "Open the conversation from this night."
    }

    let count = commentsModel.comments.count + commentsModel.optimisticComments.count
    return count == 0
      ? "Add the first detail from this night."
      : "\(count) \(count == 1 ? "moment" : "moments") shared from this night."
  }

  private func openMoments(from scrollProxy: ScrollViewProxy) {
    momentsDetent = .medium
    if reduceMotion {
      scrollProxy.scrollTo("concert-hero", anchor: .top)
      isShowingMoments = true
      return
    }

    withAnimation(TunedInMotion.navigation(reduceMotion: false)) {
      scrollProxy.scrollTo("concert-hero", anchor: .top)
    } completion: {
      isShowingMoments = true
    }
  }

  @ViewBuilder
  private func concertHeader(_ detail: ConcertDetail, artworkStyle: ArtworkStyle) -> some View {
    if artworkStyle == .full {
      concertHero(detail)
    } else {
      concertPreview(detail)
    }
  }

  private var viewerRole: ConcertViewerRole {
    guard let detail else { return .viewer }
    if detail.concert.ownerID == viewerID {
      return .owner
    }
    if detail.collaborators.contains(where: { $0.id == viewerID }) {
      return .editor
    }
    return .viewer
  }

  private func configureFloatingControls() {
    concertFloatingControls.configure(
      selectedPage: selectedPage,
      back: {
        concertFloatingControls.reset()
        dismiss()
      },
      selectPage: { page in selectedPage = page },
      edit: viewerRole.canEdit ? { isShowingEditor = true } : nil,
      delete: viewerRole.canTransferOrDelete ? { isShowingDeleteConfirmation = true } : nil
    )
  }

  private func detailSection(
    title: String,
    subtitle: String? = nil,
    @ViewBuilder content: () -> some View
  ) -> some View {
    VStack(alignment: .leading, spacing: 14) {
      Divider()
        .overlay(TunedInDesign.cardBorder.opacity(0.55))
      Text(title)
        .font(.title2.weight(.bold))
        .foregroundStyle(TunedInDesign.primaryText)
      if let subtitle {
        Text(subtitle)
          .font(.subheadline)
          .foregroundStyle(TunedInDesign.mutedText)
      }
      VStack(alignment: .leading, spacing: 12) {
        content()
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private func loadDetail(policy: CacheReadPolicy = .automatic) async {
    let startedAt = ContinuousClock.now
    errorMessage = nil
    do {
      detail = try await concertRepository.fetchConcertDetail(
        id: concertID,
        viewerID: viewerID,
        policy: policy
      )
      telemetry?.capture(
        .screenLoadCompleted,
        properties: [
          .screen: .string(TelemetryScreen.concertDetail.rawValue),
          .outcome: .string(TelemetryOutcome.succeeded.rawValue),
          .durationMilliseconds: .integer(startedAt.duration(to: .now).concertTelemetryMilliseconds)
        ]
      )
    } catch {
      errorMessage = error.localizedDescription
      let failure = AppFailure(error)
      if failure == .permissionDenied || failure == .unavailable {
        detail = nil
      }
      if failure.shouldReportToTelemetry {
        telemetry?.capture(
          .screenLoadCompleted,
          properties: [
            .screen: .string(TelemetryScreen.concertDetail.rawValue),
            .outcome: .string(TelemetryOutcome.failed.rawValue),
            .durationMilliseconds: .integer(startedAt.duration(to: .now).concertTelemetryMilliseconds),
            .failureCategory: .string(TelemetryFailureCategory(failure).rawValue),
            .retryable: .boolean(failure.allowsRetry)
          ]
        )
      }
    }
  }

  private var updatesAvailableButton: some View {
    Button {
      Task { await applyRemoteChanges() }
    } label: {
      HStack(spacing: 9) {
        if isApplyingRemoteChanges {
          ProgressView()
        } else {
          Image(systemName: "arrow.down.circle.fill")
        }
        Text(isApplyingRemoteChanges ? "Updating…" : "Updates available")
          .fontWeight(.bold)
        Spacer()
        Text("Refresh")
          .font(.caption.weight(.semibold))
      }
      .font(.subheadline)
      .foregroundStyle(TunedInDesign.primaryText)
      .padding(.horizontal, 14)
      .padding(.vertical, 11)
      .background(
        TunedInDesign.accentTint,
        in: RoundedRectangle(cornerRadius: 15, style: .continuous)
      )
    }
    .buttonStyle(.plain)
    .disabled(isApplyingRemoteChanges)
    .accessibilityHint("Loads the latest concert information from the server")
  }

  private func applyRemoteChanges() async {
    guard !isApplyingRemoteChanges else { return }
    isApplyingRemoteChanges = true
    defer { isApplyingRemoteChanges = false }

    await loadDetail(policy: .refresh)
    switch selectedPage {
    case .concert:
      await commentsModel.loadComments(policy: .refresh)
      guard commentsModel.loadErrorMessage == nil else { return }
    case .people:
      break
    case .photos:
      do {
        _ = try await concertRepository.albumPhotos(
          concertID: concertID,
          cursor: nil,
          policy: .refresh
        )
        albumRefreshToken += 1
      } catch {
        errorMessage = error.localizedDescription
        return
      }
    }
    if errorMessage == nil {
      hasRemoteChanges = false
    }
  }

  private func deleteConcert() {
    isDeleting = true
    Task {
      do {
        try await concertRepository.deleteConcert(id: concertID)
        dismiss()
      } catch {
        errorMessage = error.localizedDescription
      }
      isDeleting = false
    }
  }

  private var deleteImpactMessage: String {
    guard let detail else {
      return "Its setlist, comments, and history will disappear permanently."
    }

    let editorCount = detail.collaborators.filter { !$0.isOwner }.count
    let people = editorCount == 1 ? "1 collaborator will" : "\(editorCount) collaborators will"
    return "Its setlist, comments, and history will disappear permanently. \(people) lose access."
  }
}

private extension Duration {
  var concertTelemetryMilliseconds: Int {
    let components = components
    return Int(components.seconds * 1000 + components.attoseconds / 1_000_000_000_000_000)
  }
}

struct ConcertArtworkImage: View {
  let artistName: String

  var body: some View {
    if let image = UIImage(named: assetName) {
      Image(uiImage: image)
        .resizable()
        .scaledToFill()
        .clipped()
        .accessibilityLabel("Original show artwork for \(artistName)")
    } else {
      fallbackArtwork
    }
  }

  private var assetName: String {
    switch artistName.lowercased() {
    case "mitski", "japanese breakfast":
      "afterglow-stage"
    default:
      "midnight-theatre"
    }
  }

  private var fallbackArtwork: some View {
    LinearGradient(
      colors: [TunedInDesign.ticketViolet, TunedInDesign.ticketRose, TunedInDesign.ink],
      startPoint: .topLeading,
      endPoint: .bottomTrailing
    )
    .overlay {
      Text(artistName.prefix(1).uppercased())
        .font(.system(size: 96, weight: .black, design: .serif))
        .foregroundStyle(.white.opacity(0.24))
    }
  }
}

enum ConcertDisplay {
  static func month(from value: String) -> String {
    date(from: value).map { Self.monthFormatter.string(from: $0).uppercased() } ?? "SHOW"
  }

  static func day(from value: String) -> String {
    date(from: value).map { Self.dayFormatter.string(from: $0) } ?? "·"
  }

  static func longDate(from value: String) -> String {
    date(from: value).map { Self.longDateFormatter.string(from: $0) } ?? value
  }

  static func longDateTime(_ value: Date) -> String {
    longDateTimeFormatter.string(from: value)
  }

  static func relativeDate(_ value: Date) -> String {
    RelativeDateTimeFormatter().localizedString(for: value, relativeTo: Date())
  }

  private static func date(from value: String) -> Date? {
    storageDateFormatter.date(from: value)
  }

  private static let storageDateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .iso8601)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter
  }()

  private static let monthFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = .current
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "MMM"
    return formatter
  }()

  private static let dayFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = .current
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "d"
    return formatter
  }()

  private static let longDateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateStyle = .long
    formatter.timeStyle = .none
    return formatter
  }()

  private static let longDateTimeFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .short
    return formatter
  }()
}

// swiftlint:enable file_length
