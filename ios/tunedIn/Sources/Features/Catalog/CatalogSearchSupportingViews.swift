import Foundation
import SwiftUI

enum CatalogRecentSearchStore {
  private static let maximumCount = 5

  static func values(
    for kind: CatalogEntityKind,
    defaults: UserDefaults = .standard
  ) -> [String] {
    defaults.stringArray(forKey: key(for: kind)) ?? []
  }

  static func record(
    _ value: String,
    for kind: CatalogEntityKind,
    defaults: UserDefaults = .standard
  ) -> [String] {
    let normalized = CatalogInput.normalizedText(value)
    guard !normalized.isEmpty else { return values(for: kind, defaults: defaults) }

    let retained = values(for: kind, defaults: defaults).filter {
      $0.caseInsensitiveCompare(normalized) != .orderedSame
    }
    let updated = Array(([normalized] + retained).prefix(maximumCount))
    defaults.set(updated, forKey: key(for: kind))
    return updated
  }

  private static func key(for kind: CatalogEntityKind) -> String {
    "tunedin.catalog.recent.\(kind.rawValue)"
  }
}

struct CatalogRecentSearchesView: View {
  let kind: CatalogEntityKind
  let values: [String]
  let onSelect: (String) -> Void
  let onAddCustom: () -> Void

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        VStack(alignment: .leading, spacing: 5) {
          Text(title)
            .font(.headline)
            .foregroundStyle(TunedInDesign.primaryText)
          Text("Pick up where you left off, or start a new search.")
            .font(.subheadline)
            .foregroundStyle(TunedInDesign.mutedText)
        }

        VStack(spacing: 8) {
          ForEach(values, id: \.self) { value in
            Button {
              onSelect(value)
            } label: {
              HStack(spacing: 12) {
                Image(systemName: "clock.arrow.circlepath")
                  .foregroundStyle(TunedInDesign.accent)
                Text(value)
                  .font(.body.weight(.semibold))
                  .foregroundStyle(TunedInDesign.primaryText)
                  .lineLimit(1)
                Spacer()
                Image(systemName: "arrow.up.left")
                  .font(.caption.weight(.bold))
                  .foregroundStyle(TunedInDesign.mutedText)
              }
              .padding(14)
              .background(TunedInDesign.cardBackground, in: RoundedRectangle(cornerRadius: 16))
            }
            .buttonStyle(.plain)
          }
        }

        CatalogCustomEntryAction(action: onAddCustom)
      }
      .padding(.horizontal, 20)
      .padding(.top, 12)
      .padding(.bottom, 28)
    }
  }

  private var title: String {
    switch kind {
    case .artist: "Recent artists"
    case .place: "Recently used venues"
    default: "Recent searches"
    }
  }
}

struct CatalogResultsList: View {
  let model: CatalogSearchModel
  let configuration: CatalogPickerConfiguration
  let isUsingArtistContext: Bool
  let onSelect: (CatalogResult) -> Void
  let onAddCustom: () -> Void

  var body: some View {
    List {
      if model.isPartial {
        Section {
          Label(
            "Live catalog is taking a minute. Showing saved tunedIn results.",
            systemImage: "wifi.exclamationmark"
          )
          .font(.caption)
          .foregroundStyle(TunedInDesign.mutedText)
        }
        .listRowBackground(TunedInDesign.raisedSurface)
      }

      if showsArtistContext {
        Section {
          Text("Prioritizing results for \(configuration.artistContext.map(\.displayName).joined(separator: ", ")).")
            .font(.caption)
            .foregroundStyle(TunedInDesign.mutedText)
        }
        .listRowBackground(TunedInDesign.raisedSurface)
      }

      resultSection(title: "Saved in tunedIn", results: tunedInResults)
      resultSection(title: "More results", results: musicBrainzResults)

      if model.isLoadingMore {
        HStack {
          Spacer()
          ProgressView("Loading more…")
          Spacer()
        }
        .listRowBackground(TunedInDesign.cardBackground)
      } else if let paginationErrorMessage = model.paginationErrorMessage {
        VStack(alignment: .leading, spacing: 8) {
          Text(paginationErrorMessage)
            .font(.caption)
            .foregroundStyle(TunedInDesign.mutedText)
          Button("Retry loading more") {
            Task { await model.loadMore() }
          }
          .font(.caption.weight(.semibold))
        }
        .listRowBackground(TunedInDesign.cardBackground)
      }

      Section {
        CatalogCustomEntryAction(action: onAddCustom)
      }
      .listRowBackground(TunedInDesign.raisedSurface)

      Section {
        VStack(alignment: .leading, spacing: 4) {
          Label("tunedIn catalog search", systemImage: "music.note")
            .font(.caption.weight(.semibold))
          Text("More results are saved to your tunedIn catalog when selected.")
            .font(.caption2)
        }
        .foregroundStyle(TunedInDesign.mutedText)
      }
      .listRowBackground(Color.clear)
    }
    .listStyle(.insetGrouped)
    .scrollContentBackground(.hidden)
    .background(TunedInDesign.pageBackground)
  }

  @ViewBuilder
  private func resultSection(title: String, results: [CatalogResult]) -> some View {
    if !results.isEmpty {
      Section(title) {
        ForEach(results) { result in
          Button {
            onSelect(result)
          } label: {
            CatalogResultRow(
              result: result,
              isResolving: model.resolvingResultID == result.id
            )
          }
          .buttonStyle(.plain)
          .disabled(model.resolvingResultID != nil)
          .onAppear {
            guard result.id == model.results.last?.id,
                  model.hasMore,
                  model.paginationErrorMessage == nil
            else { return }
            Task { await model.loadMore() }
          }
          .listRowBackground(TunedInDesign.cardBackground)
        }
      }
    }
  }

  private var tunedInResults: [CatalogResult] {
    model.results.filter { $0.origin != .musicBrainz }
  }

  private var showsArtistContext: Bool {
    !configuration.artistContext.isEmpty
      && configuration.kind == .song
      && isUsingArtistContext
  }

  private var musicBrainzResults: [CatalogResult] {
    model.results.filter { $0.origin == .musicBrainz }
  }
}

struct CatalogCustomEntryAction: View {
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Label("Can’t find it? Add to tunedIn catalog", systemImage: "plus.circle.fill")
        .font(.headline)
        .foregroundStyle(TunedInDesign.accent)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }
    .buttonStyle(.plain)
  }
}

struct CatalogResultRow: View {
  let result: CatalogResult
  let isResolving: Bool

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      VStack(alignment: .leading, spacing: 5) {
        Text(result.displayName)
          .font(.headline)
          .foregroundStyle(TunedInDesign.primaryText)
          .multilineTextAlignment(.leading)

        if let subtitle = result.subtitle, !subtitle.isEmpty {
          Text(subtitle)
            .font(.subheadline)
            .foregroundStyle(TunedInDesign.mutedText)
            .multilineTextAlignment(.leading)
        }
        if let disambiguation = result.disambiguation, !disambiguation.isEmpty {
          Text(disambiguation)
            .font(.caption)
            .foregroundStyle(TunedInDesign.mutedText)
            .multilineTextAlignment(.leading)
        }
      }
      Spacer(minLength: 8)
      if isResolving {
        ProgressView().controlSize(.small)
      } else {
        Image(systemName: "chevron.forward")
          .font(.caption.weight(.bold))
          .foregroundStyle(TunedInDesign.mutedText)
          .padding(.top, 4)
      }
    }
    .contentShape(.interaction, Rectangle())
    .padding(.vertical, 5)
  }
}
