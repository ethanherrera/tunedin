// swiftlint:disable file_length

import SwiftUI
import UIKit

struct ConcertArchiveView: View {
  let profileID: UUID
  let viewerID: UUID
  let viewerUsername: String
  let isOwner: Bool
  let concertRepository: any ConcertRepository
  let socialRepository: any SocialRepository
  let refreshToken: Int

  @State private var query = ConcertHistoryQuery()
  @State private var concerts: [ConcertPreview] = []
  @State private var isLoading = false
  @State private var isLoadingMore = false
  @State private var canLoadMore = false
  @State private var errorMessage: String?

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack(alignment: .firstTextBaseline) {
        VStack(alignment: .leading, spacing: 3) {
          Text(isOwner ? "Kept" : "Concerts")
            .font(.title2.weight(.bold))
            .foregroundStyle(TunedInDesign.primaryText)
          Text(isOwner ? "Your saved concerts" : "Shared concerts")
            .font(.subheadline)
            .foregroundStyle(TunedInDesign.mutedText)
        }

        Spacer()

        Menu {
          Button("All saved shows") {
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
        } label: {
          HStack(spacing: 5) {
            Image(systemName: "line.3.horizontal.decrease.circle")
            Text(filterLabel)
          }
          .font(.caption.weight(.bold))
          .foregroundStyle(TunedInDesign.primaryText)
          .padding(.horizontal, 10)
          .padding(.vertical, 8)
          .background(TunedInDesign.raisedSurface, in: Capsule())
        }
        .accessibilityLabel("Filter archive")
      }

      TunedInGlassSearchField(text: $query.searchText, prompt: "Search artists, venues, cities")

      if isLoading, concerts.isEmpty {
        VStack(spacing: 10) {
          ForEach(0 ..< 3, id: \.self) { _ in
            TunedInSkeletonBlock(cornerRadius: 20)
              .frame(height: 142)
          }
        }
        .accessibilityLabel("Loading concerts")
      } else if let errorMessage {
        ContentUnavailableView {
          Label("Couldn’t load this archive", systemImage: "exclamationmark.triangle")
        } description: {
          Text(errorMessage)
        } actions: {
          Button("Try again") {
            Task { await reload() }
          }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
      } else if concerts.isEmpty {
        archiveEmptyState
      } else {
        LazyVStack(spacing: 10) {
          ForEach(concerts) { preview in
            NavigationLink {
              ConcertDetailView(
                concertID: preview.id,
                viewerID: viewerID,
                viewerUsername: viewerUsername,
                concertRepository: concertRepository,
                socialRepository: socialRepository
              )
            } label: {
              ConcertArchiveRow(preview: preview, repository: concertRepository)
            }
            .buttonStyle(.plain)
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .accessibilityLabel("Open \(preview.primaryArtistName)")
          }

          if canLoadMore {
            Button {
              Task { await loadMore() }
            } label: {
              HStack(spacing: 8) {
                if isLoadingMore {
                  ProgressView()
                }
                Text(isLoadingMore ? "Finding earlier nights…" : "Show earlier nights")
              }
              .font(.subheadline.weight(.bold))
              .foregroundStyle(TunedInDesign.primaryText)
              .frame(maxWidth: .infinity)
              .padding(.vertical, 14)
              .background(TunedInDesign.raisedSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(isLoadingMore)
          }
        }
      }
    }
    .task(id: refreshToken) {
      await reload()
    }
    .onChange(of: query.searchText) { _, searchText in
      Task {
        try? await Task.sleep(for: .milliseconds(250))
        guard searchText == query.searchText else { return }
        await reload()
      }
    }
  }

  private var filterLabel: String {
    switch query.visibility {
    case nil:
      "All"
    case .private:
      "Private"
    case .collaborators:
      "Collaborators"
    case .friends:
      "Friends"
    }
  }

  private var archiveEmptyState: some View {
    TunedInFormCard {
      Image(systemName: "music.quarternote.3")
        .font(.title2)
        .foregroundStyle(TunedInDesign.accent)
      Text(query.searchText.isEmpty ? "No concerts yet." : "No concerts match that search.")
        .font(.headline)
        .foregroundStyle(TunedInDesign.primaryText)
      Text(
        query.searchText.isEmpty
          ? "Use the plus button to log one."
          : "Try an artist, venue, or city."
      )
      .font(.subheadline)
      .foregroundStyle(TunedInDesign.mutedText)
    }
  }

  private func setVisibilityFilter(_ visibility: ConcertVisibility?) {
    query.visibility = visibility
    Task { await reload() }
  }

  private func reload() async {
    guard !isLoading else { return }
    isLoading = true
    errorMessage = nil

    do {
      let loaded = try await concertRepository.profileConcertHistory(
        profileID: profileID,
        query: query,
        cursor: nil
      )
      concerts = loaded
      canLoadMore = loaded.count == 30
    } catch {
      concerts = []
      canLoadMore = false
      errorMessage = error.localizedDescription
    }

    isLoading = false
  }

  private func loadMore() async {
    guard let lastConcert = concerts.last, !isLoadingMore else { return }
    isLoadingMore = true

    do {
      let loaded = try await concertRepository.profileConcertHistory(
        profileID: profileID,
        query: query,
        cursor: ConcertHistoryCursor(
          concertDate: lastConcert.concert.concertDate,
          concertID: lastConcert.id
        )
      )
      concerts.append(contentsOf: loaded)
      canLoadMore = loaded.count == 30
    } catch {
      errorMessage = error.localizedDescription
    }

    isLoadingMore = false
  }
}

private struct ConcertArchiveRow: View {
  let preview: ConcertPreview
  let repository: any ConcertRepository

  var body: some View {
    ZStack(alignment: .bottomLeading) {
      ConcertPhotoView(concert: preview.concert, artistName: preview.primaryArtistName, repository: repository)
        .frame(maxWidth: .infinity)
        .frame(height: 136)
        .overlay {
          LinearGradient(
            colors: [.clear, .black.opacity(0.14), .black.opacity(0.78)],
            startPoint: .top,
            endPoint: .bottom
          )
        }

      VStack(alignment: .leading, spacing: 4) {
        Text(ConcertDisplay.longDate(from: preview.concert.concertDate).uppercased())
          .font(.caption.weight(.bold))
          .foregroundStyle(.white.opacity(0.8))
        Text(preview.primaryArtistName)
          .font(.system(size: 24, weight: .bold, design: .serif))
          .foregroundStyle(.white)
          .lineLimit(1)
        Text([preview.concert.venueName, preview.concert.city].compactMap(\.self).joined(separator: " · "))
          .font(.subheadline.weight(.medium))
          .foregroundStyle(.white.opacity(0.9))
          .lineLimit(1)
      }
      .padding(15)

      visibilityMark
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
    }
    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 20, style: .continuous)
        .strokeBorder(.white.opacity(0.18))
    }
    .frame(maxWidth: .infinity)
    .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    .accessibilityElement(children: .combine)
  }

  @ViewBuilder
  private var visibilityMark: some View {
    switch preview.concert.visibility {
    case .private:
      Image(systemName: "lock.fill")
        .foregroundStyle(TunedInDesign.mutedText)
        .accessibilityLabel("Private")
    case .collaborators:
      Image(systemName: "person.2.fill")
        .foregroundStyle(TunedInDesign.mutedText)
        .accessibilityLabel("Collaborators")
    case .friends:
      Image(systemName: "heart.fill")
        .foregroundStyle(TunedInDesign.accent)
        .accessibilityLabel("Friends")
    }
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
  @EnvironmentObject private var concertFloatingControls: ConcertFloatingControls
  @State private var detail: ConcertDetail?
  @State private var errorMessage: String?
  @State private var isShowingEditor = false
  @State private var selectedPage: ConcertDetailPage = .concert
  @State private var isShowingDeleteConfirmation = false
  @State private var isShowingFinalDeleteConfirmation = false
  @State private var isDeleting = false

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
              Task { await loadDetail() }
            },
            pageHeader: AnyView(concertHeader(detail, artworkStyle: .preview))
          )
        case .photos:
          ConcertAlbumView(
            detail: detail,
            viewerID: viewerID,
            viewerRole: viewerRole,
            concertRepository: concertRepository,
            pageHeader: AnyView(concertHeader(detail, artworkStyle: .preview))
          )
        }
      } else if let errorMessage {
        ContentUnavailableView {
          Label("This concert isn’t available", systemImage: "lock.trianglebadge.exclamationmark")
        } description: {
          Text(errorMessage)
        }
      } else {
        ScrollView {
          VStack(alignment: .leading, spacing: 18) {
            TunedInSkeletonBlock(cornerRadius: 24)
              .aspectRatio(CGSize(width: 3, height: 4), contentMode: .fit)
            TunedInSkeletonBlock(cornerRadius: 7).frame(width: 150, height: 20)
            TunedInSkeletonBlock(cornerRadius: 18).frame(height: 140)
            TunedInSkeletonBlock(cornerRadius: 18).frame(height: 110)
          }
          .padding(.horizontal, 20)
          .padding(.top, 14)
          .padding(.bottom, 120)
        }
        .accessibilityLabel("Opening concert")
      }
    }
    .toolbar(.hidden, for: .navigationBar)
    .onAppear { configureFloatingControls() }
    .onChange(of: viewerRole) { _, _ in configureFloatingControls() }
    .onDisappear { concertFloatingControls.reset() }
    .task(id: concertID) {
      await loadDetail()
    }
    .task(id: concertID) {
      for await _ in concertRepository.observeConcert(id: concertID) {
        await loadDetail()
      }
    }
    .sheet(isPresented: $isShowingEditor) {
      if let detail {
        ConcertEditView(
          detail: detail,
          canMakePrivate: viewerRole == .owner,
          viewerRole: viewerRole,
          viewerUsername: viewerUsername,
          socialRepository: socialRepository,
          concertRepository: concertRepository,
          loadLatestDetail: {
            try await concertRepository.fetchConcertDetail(id: concertID, viewerID: viewerID)
          },
          onSaved: { _ in
            Task { await loadDetail() }
          }
        )
      }
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
        .aspectRatio(CGSize(width: 3, height: 4), contentMode: .fit)
        .overlay {
          LinearGradient(
            colors: [.clear, .black.opacity(0.14), .black.opacity(0.76)],
            startPoint: .top,
            endPoint: .bottom
          )
        }

      VStack(alignment: .leading, spacing: 7) {
        Text(ConcertDisplay.longDate(from: detail.concert.concertDate).uppercased())
          .font(.caption.weight(.bold))
          .foregroundStyle(.white.opacity(0.84))
        Text(artistName)
          .font(.system(size: 39, weight: .bold, design: .serif))
          .foregroundStyle(.white)
          .lineLimit(2)
        Text(detail.concert.venueName)
          .font(.title3.weight(.semibold))
          .foregroundStyle(.white.opacity(0.94))
      }
      .padding(20)
    }
    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
  }

  private func concertPreview(_ detail: ConcertDetail) -> some View {
    let artistName = detail.artists.first(where: \.isPrimary)?.name ?? "A saved night"

    return ZStack(alignment: .bottomLeading) {
      ConcertPhotoView(concert: detail.concert, artistName: artistName, repository: concertRepository)
        .frame(maxWidth: .infinity)
        .frame(height: 148)
        .overlay {
          LinearGradient(
            colors: [.clear, .black.opacity(0.72)],
            startPoint: .top,
            endPoint: .bottom
          )
        }

      VStack(alignment: .leading, spacing: 3) {
        Text(ConcertDisplay.longDate(from: detail.concert.concertDate).uppercased())
          .font(.caption2.weight(.bold))
          .foregroundStyle(.white.opacity(0.84))
        Text(artistName)
          .font(.title2.weight(.bold))
          .foregroundStyle(.white)
          .lineLimit(1)
        Text(detail.concert.venueName)
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(.white.opacity(0.92))
          .lineLimit(1)
      }
      .padding(16)
    }
    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
  }

  private func concertContent(_ detail: ConcertDetail) -> some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 18) {
        concertHeader(detail, artworkStyle: .full)

        if let tour = detail.concert.tour {
          Label(tour, systemImage: "sparkles")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(TunedInDesign.accent)
            .padding(.horizontal, 4)
        }

        if detail.artists.count > 1 {
          detailSection(title: "Lineup") {
            ForEach(detail.artists) { artist in
              HStack {
                Text(artist.isPrimary ? "Headliner" : "With")
                  .font(.caption.weight(.bold))
                  .foregroundStyle(artist.isPrimary ? TunedInDesign.accent : TunedInDesign.mutedText)
                  .frame(width: 66, alignment: .leading)
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
              HStack(alignment: .top, spacing: 12) {
                Text("\(entry.position)")
                  .font(.caption.weight(.bold))
                  .foregroundStyle(TunedInDesign.accent)
                  .frame(width: 22, alignment: .leading)
                Text(entry.title)
                  .foregroundStyle(TunedInDesign.primaryText)
              }
            }
          }
        }

        detailSection(title: "Venue") {
          Label(detail.concert.venueName, systemImage: "mappin.and.ellipse")
            .font(.headline)
            .foregroundStyle(TunedInDesign.primaryText)
          if let city = detail.concert.city {
            Text(city)
              .font(.subheadline)
              .foregroundStyle(TunedInDesign.mutedText)
          }
        }

        DisclosureGroup("History") {
          VStack(alignment: .leading, spacing: 14) {
            ForEach(detail.history) { event in
              HStack(alignment: .top, spacing: 12) {
                Circle()
                  .fill(TunedInDesign.accent)
                  .frame(width: 8, height: 8)
                  .padding(.top, 5)
                VStack(alignment: .leading, spacing: 3) {
                  Text(event.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(TunedInDesign.primaryText)
                  Text(ConcertDisplay.longDateTime(event.occurredAt))
                    .font(.caption)
                    .foregroundStyle(TunedInDesign.mutedText)
                }
              }
            }
          }
        }
        .font(.headline)
        .foregroundStyle(TunedInDesign.primaryText)
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
          TunedInDesign.raisedSurface.opacity(0.6),
          in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .accessibilityLabel("Concert history")

        VStack(alignment: .leading, spacing: 12) {
          Text("Moments")
            .font(.title2.weight(.bold))
            .foregroundStyle(TunedInDesign.primaryText)
          ConcertCommentsView(
            concertID: concertID,
            viewerID: viewerID,
            concertRepository: concertRepository,
            pageHeader: AnyView(EmptyView())
          )
        }
        .padding(.top, 4)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, 20)
      .padding(.top, 10)
      .padding(.bottom, 36)
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
    TunedInFormCard {
      Text(title)
        .font(.headline)
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

  private func loadDetail() async {
    do {
      detail = try await concertRepository.fetchConcertDetail(id: concertID, viewerID: viewerID)
    } catch {
      errorMessage = error.localizedDescription
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
