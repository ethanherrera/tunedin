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
          Text("Archive")
            .font(.title2.weight(.bold))
            .foregroundStyle(TunedInDesign.primaryText)
          Text(isOwner ? "Every show you kept." : "The shows they chose to share.")
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
        HStack {
          ProgressView()
          Text("Finding the good nights…")
            .font(.subheadline)
            .foregroundStyle(TunedInDesign.mutedText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
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
              ConcertArchiveRow(preview: preview)
            }
            .buttonStyle(.plain)
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
      Text(query.searchText.isEmpty ? "Nothing saved here yet." : "No shows match that search.")
        .font(.headline)
        .foregroundStyle(TunedInDesign.primaryText)
      Text(
        query.searchText.isEmpty
          ? "The best nights tend to start with a small note."
          : "Try an artist, a room, or a city instead."
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

  private var dateLabel: String {
    let concertDate = preview.concert.concertDate
    return "\(ConcertDisplay.month(from: concertDate)) \(ConcertDisplay.day(from: concertDate))"
  }

  var body: some View {
    HStack(spacing: 14) {
      ZStack(alignment: .bottomLeading) {
        ConcertArtworkImage(artistName: preview.primaryArtistName)
          .frame(width: 70, height: 76)

        Text(dateLabel)
          .font(.caption2.weight(.black))
          .foregroundStyle(.white)
          .padding(.horizontal, 7)
          .padding(.vertical, 5)
          .background(.black.opacity(0.45), in: Capsule())
          .padding(6)
      }
      .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))

      VStack(alignment: .leading, spacing: 4) {
        Text(preview.primaryArtistName)
          .font(.headline)
          .foregroundStyle(TunedInDesign.primaryText)
          .lineLimit(1)
        Text([preview.concert.venueName, preview.concert.city].compactMap(\.self).joined(separator: " · "))
          .font(.subheadline)
          .foregroundStyle(TunedInDesign.mutedText)
          .lineLimit(1)
      }

      Spacer(minLength: 0)

      visibilityMark
      Image(systemName: "chevron.right")
        .font(.caption.weight(.bold))
        .foregroundStyle(TunedInDesign.mutedText)
    }
    .padding(14)
    .background(TunedInDesign.cardBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .strokeBorder(TunedInDesign.cardBorder.opacity(0.72))
    }
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

struct ConcertDetailView: View {
  let concertID: UUID
  let viewerID: UUID
  let viewerUsername: String
  let concertRepository: any ConcertRepository
  let socialRepository: any SocialRepository

  @Environment(\.dismiss) private var dismiss
  @State private var detail: ConcertDetail?
  @State private var errorMessage: String?
  @State private var isShowingEditor = false
  @State private var isShowingPeople = false
  @State private var isShowingComments = false
  @State private var isShowingDeleteConfirmation = false
  @State private var isShowingFinalDeleteConfirmation = false
  @State private var isDeleting = false

  var body: some View {
    ZStack {
      TunedInDesign.pageBackground
        .ignoresSafeArea()

      if let detail {
        ScrollView {
          VStack(alignment: .leading, spacing: 22) {
            concertHero(detail)
            momentActions(for: detail)

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

            detailSection(title: "Setlist", subtitle: "The songs that stayed.") {
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

            detailSection(title: "The room") {
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
            .background(
              TunedInDesign.raisedSurface.opacity(0.6),
              in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .accessibilityLabel("Concert history")
          }
          .padding(.horizontal, 20)
          .padding(.top, 18)
          .padding(.bottom, 36)
        }
      } else if let errorMessage {
        ContentUnavailableView {
          Label("This concert isn’t available", systemImage: "lock.trianglebadge.exclamationmark")
        } description: {
          Text(errorMessage)
        }
      } else {
        ProgressView("Opening concert…")
      }
    }
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      if viewerRole.canTransferOrDelete {
        ToolbarItem(placement: .topBarTrailing) {
          Menu {
            Button(role: .destructive) {
              isShowingDeleteConfirmation = true
            } label: {
              Label("Delete concert", systemImage: "trash")
            }
          } label: {
            Image(systemName: "ellipsis.circle")
              .font(.title3)
              .foregroundStyle(TunedInDesign.primaryText)
          }
          .accessibilityLabel("Concert options")
        }
      }
    }
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
        ConcertEditView(detail: detail, concertRepository: concertRepository) { _ in
          Task { await loadDetail() }
        }
      }
    }
    .sheet(isPresented: $isShowingPeople) {
      if let detail {
        ConcertPeopleSheet(
          detail: detail,
          viewerRole: viewerRole,
          viewerUsername: viewerUsername,
          socialRepository: socialRepository,
          concertRepository: concertRepository
        ) {
          Task { await loadDetail() }
        }
      }
    }
    .sheet(isPresented: $isShowingComments) {
      ConcertCommentsSheet(
        concertID: concertID,
        viewerID: viewerID,
        concertRepository: concertRepository
      )
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
      Text("Its setlist, notes, and history will disappear for everyone who can see it.")
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
      ConcertArtworkImage(artistName: artistName)
        .frame(maxWidth: .infinity)
        .frame(height: 410)
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

  private func momentActions(for detail: ConcertDetail) -> some View {
    HStack(spacing: 10) {
      if viewerRole.canEdit {
        momentAction("Shape", icon: "slider.horizontal.3") {
          isShowingEditor = true
        }
      }

      if viewerRole.canManagePeople {
        momentAction(
          detail.collaborators.isEmpty ? "People" : "People \(detail.collaborators.count)",
          icon: "person.2.fill"
        ) {
          isShowingPeople = true
        }
      }

      momentAction("Notes", icon: "text.bubble.fill") {
        isShowingComments = true
      }
    }
  }

  private func momentAction(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Label(title, systemImage: icon)
        .font(.subheadline.weight(.bold))
        .foregroundStyle(TunedInDesign.primaryText)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 13)
        .background(TunedInDesign.raisedSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
    .buttonStyle(.plain)
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
