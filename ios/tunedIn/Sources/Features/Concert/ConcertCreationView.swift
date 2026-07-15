import PhotosUI
import SwiftUI

// swiftlint:disable:next type_body_length
struct ConcertCreationView: View {
  let concertRepository: any ConcertRepository

  @Environment(\.dismiss) private var dismiss
  @Environment(\.telemetry) private var telemetry
  @Environment(\.musicCatalogRepository) private var musicCatalogRepository

  @State var draft = ConcertDraft()
  @State private var isSaving = false
  @State var isShowingDetails = false
  @State private var isShowingDiscardConfirmation = false
  @State private var saveError: String?
  @State private var savedConcert: Concert?
  @State private var savedPrimaryArtistName = ""
  @State private var selectedPhoto: PhotosPickerItem?
  @State private var concertPhotoData: Data?
  @State private var isProcessingPhoto = false
  @State private var catalogPickerTarget: ConcertCatalogPickerTarget?

  var body: some View {
    Group {
      if let savedConcert {
        ConcertSavedView(
          concert: savedConcert,
          primaryArtistName: savedPrimaryArtistName,
          concertRepository: concertRepository,
          onDone: { dismiss() }
        )
        .transition(.opacity)
      } else {
        NavigationStack {
          ZStack {
            TunedInDesign.pageBackground
              .ignoresSafeArea()

            ScrollView {
              VStack(alignment: .leading, spacing: 0) {
                captureHeader
                quickCaptureCard
                  .padding(.top, 22)
                detailsPrompt
                  .padding(.top, 12)
              }
              .padding(.bottom, 24)
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
          }
          .navigationBarTitleDisplayMode(.inline)
          .safeAreaInset(edge: .bottom, spacing: 0) {
            TunedInPersistentControlRegion {
              saveBar
            }
          }
          .alert("Discard this concert?", isPresented: $isShowingDiscardConfirmation) {
            Button("Keep Editing", role: .cancel) {}
            Button("Discard", role: .destructive) {
              dismiss()
            }
          } message: {
            Text("Your unsaved concert details will be lost.")
          }
          .alert("Couldn’t save your concert", isPresented: isShowingSaveError) {
            Button("OK", role: .cancel) {}
          } message: {
            Text(saveError ?? "Please try again.")
          }
          .sheet(isPresented: $isShowingDetails) {
            ConcertCreationDetailsView(draft: $draft)
          }
          .fullScreenCover(item: $catalogPickerTarget) { target in
            catalogPicker(for: target)
          }
          .onChange(of: selectedPhoto) { _, item in
            guard let item else { return }
            Task { await processPhoto(item) }
          }
        }
      }
    }
    .tint(TunedInDesign.accent)
    .tunedInKeyboardManaged()
  }

  private var saveBar: some View {
    TunedInGlassTraversalLayout {
      TunedInGlassIconButton(
        systemImage: "chevron.backward",
        accessibilityLabel: "Cancel concert"
      ) {
        requestDismissal()
      }
      .disabled(isSaving)
    } center: {
      EmptyView()
    } trailing: {
      TunedInFloatingAction(
        systemImage: isSaving ? "ellipsis" : "checkmark",
        accessibilityLabel: isSaving ? "Saving concert" : "Save concert privately",
        accessibilityHint: draft.canSave
          ? "Saves this concert privately"
          : "Enter an artist and venue to save this concert",
        action: save
      )
      .disabled(!draft.canSave || isSaving)
      .opacity(draft.canSave && !isSaving ? 1 : 0.45)
    }
    .padding(.horizontal, TunedInDesign.bottomControlHorizontalInset)
    .padding(.top, 8)
    .padding(.bottom, TunedInDesign.bottomControlInset)
  }

  private var isShowingSaveError: Binding<Bool> {
    Binding(
      get: { saveError != nil },
      set: { isPresented in
        if !isPresented {
          saveError = nil
        }
      }
    )
  }

  private var captureHeader: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Label("Private by default", systemImage: "lock.fill")
          .font(.caption.weight(.bold))
          .foregroundStyle(TunedInDesign.accent)
        Spacer()
        TunedInPrivacyBadge()
      }

      Text("New concert")
        .font(.system(size: 38, weight: .bold, design: .rounded))
        .foregroundStyle(TunedInDesign.primaryText)
      Text("Start with the night. Add the memories when you want.")
        .font(.body)
        .foregroundStyle(TunedInDesign.mutedText)
    }
  }

  private var quickCaptureCard: some View {
    VStack(alignment: .leading, spacing: 12) {
      VStack(alignment: .leading, spacing: 10) {
        PhotosPicker(selection: $selectedPhoto, matching: .images) {
          ZStack(alignment: .bottomTrailing) {
            Group {
              if let concertPhotoData, let image = UIImage(data: concertPhotoData) {
                Image(uiImage: image).resizable().scaledToFill()
              } else {
                ConcertArtworkImage(artistName: draft.primaryArtist?.displayName ?? "Concert")
              }
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(CGSize(width: 3, height: 4), contentMode: .fit)
            .clipped()
            Label(concertPhotoData == nil ? "Add a photo" : "Change photo", systemImage: "photo")
              .font(.caption.weight(.bold))
              .padding(.horizontal, 11)
              .padding(.vertical, 9)
              .foregroundStyle(.white)
              .background(.black.opacity(0.62), in: Capsule())
              .padding(12)
          }
          .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
          .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .disabled(isProcessingPhoto)
        if isProcessingPhoto {
          ProgressView("Preparing photo…")
            .font(.caption)
            .foregroundStyle(TunedInDesign.mutedText)
        }
      }

      VStack(spacing: 0) {
        VStack(alignment: .leading, spacing: 5) {
          Text("ARTIST")
            .font(.caption2.weight(.black))
            .foregroundStyle(TunedInDesign.accent)
          catalogSelectionButton(
            value: draft.artists[0].selection?.displayName,
            placeholder: "Who did you see?",
            font: .system(size: 28, weight: .bold, design: .serif)
          ) {
            catalogPickerTarget = .artist(draft.artists[0].id)
          }
          .accessibilityLabel("Primary artist")
          if draft.hasAttemptedSave, draft.artists[0].selection == nil {
            captureValidationLabel("Choose the artist you saw.")
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)

        Divider()
          .overlay(TunedInDesign.cardBorder.opacity(0.55))
          .padding(.leading, 18)

        HStack(alignment: .top, spacing: 12) {
          Image(systemName: "mappin.and.ellipse")
            .font(.body.weight(.semibold))
            .foregroundStyle(TunedInDesign.accent)
            .frame(width: 24, height: 28)
          VStack(alignment: .leading, spacing: 5) {
            catalogSelectionButton(
              value: draft.place?.displayName,
              placeholder: "Venue",
              font: .title3.weight(.semibold)
            ) {
              catalogPickerTarget = .place
            }
            .accessibilityLabel("Venue")
            if let areaName = draft.place?.areaName {
              Text(areaName)
                .font(.caption)
                .foregroundStyle(TunedInDesign.mutedText)
            }
            if draft.hasAttemptedSave, draft.place == nil {
              captureValidationLabel("Choose the venue.")
            }
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)

        Divider()
          .overlay(TunedInDesign.cardBorder.opacity(0.55))
          .padding(.leading, 18)

        HStack {
          Label("When", systemImage: "calendar")
            .font(.body.weight(.semibold))
            .foregroundStyle(TunedInDesign.primaryText)
          Spacer()
          DatePicker("Concert date", selection: $draft.concertDate, displayedComponents: .date)
            .datePickerStyle(.compact)
            .labelsHidden()
            .tint(TunedInDesign.accent)
        }
        .padding(18)
      }
      .background(
        TunedInDesign.cardBackground,
        in: RoundedRectangle(cornerRadius: 22, style: .continuous)
      )
    }
  }

  private func processPhoto(_ item: PhotosPickerItem) async {
    isProcessingPhoto = true
    defer { isProcessingPhoto = false }
    do {
      guard let data = try await item.loadTransferable(type: Data.self) else { return }
      concertPhotoData = try await AvatarImageProcessor.processConcertPhoto(data)
    } catch { saveError = error.localizedDescription }
  }

  private var detailsPrompt: some View {
    Button {
      isShowingDetails = true
    } label: {
      HStack(spacing: 13) {
        Image(systemName: "sparkles")
          .font(.body.weight(.semibold))
          .foregroundStyle(TunedInDesign.accent)
          .frame(width: 36, height: 36)
          .background(TunedInDesign.accentTint, in: Circle())
        VStack(alignment: .leading, spacing: 2) {
          Text("More details")
            .font(.headline)
            .foregroundStyle(TunedInDesign.primaryText)
          Text(detailsSummary)
            .font(.subheadline)
            .foregroundStyle(TunedInDesign.mutedText)
            .lineLimit(1)
        }
        Spacer()
        Image(systemName: "chevron.forward")
          .font(.subheadline.weight(.bold))
          .foregroundStyle(TunedInDesign.mutedText)
      }
      .padding(.horizontal, 6)
      .padding(.vertical, 12)
    }
    .buttonStyle(.plain)
    .accessibilityHint("Add the lineup, context, and setlist")
  }

  private var detailsSummary: String {
    let additions = (draft.artists.count - 1) + draft.setlist.count
    if additions == 0, draft.tour == nil, !draft.hasStartTime {
      return "Lineup, setlist, time, and more"
    }
    return "\(additions) added detail\(additions == 1 ? "" : "s")"
  }

  private func captureValidationLabel(_ message: String) -> some View {
    Label(message, systemImage: "exclamationmark.circle.fill")
      .font(.caption)
      .foregroundStyle(.red)
  }

  private func requestDismissal() {
    if draft.hasEnteredContent {
      isShowingDiscardConfirmation = true
    } else {
      dismiss()
    }
  }

  private func save() {
    draft.hasAttemptedSave = true

    guard let input = draft.creationInput else { return }
    isSaving = true
    let startedAt = ContinuousClock.now

    Task {
      do {
        var concert = try await concertRepository.createPrivateConcert(input)
        if let concertPhotoData {
          concert = try await concertRepository.setConcertPhoto(concertPhotoData, concertID: concert.id)
        }
        savedPrimaryArtistName = draft.primaryArtist?.displayName ?? "Concert"
        savedConcert = concert
        telemetry?.capture(
          .concertCreated,
          properties: [.durationMilliseconds: .integer(startedAt.duration(to: .now).creationTelemetryMilliseconds)]
        )
        isSaving = false
      } catch {
        let failure = AppFailure(error)
        if failure.shouldReportToTelemetry {
          telemetry?.captureOperation(
            .createConcert,
            outcome: .failed,
            duration: startedAt.duration(to: .now),
            failure: failure
          )
        }
        isSaving = false
        saveError = error.localizedDescription
      }
    }
  }

  private func catalogSelectionButton(
    value: String?,
    placeholder: String,
    font: Font,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      HStack {
        Text(value ?? placeholder)
          .font(font)
          .foregroundStyle(value == nil ? TunedInDesign.mutedText : TunedInDesign.primaryText)
          .multilineTextAlignment(.leading)
        Spacer()
        Image(systemName: "magnifyingglass")
          .foregroundStyle(TunedInDesign.accent)
      }
      .contentShape(.interaction, Rectangle())
    }
    .buttonStyle(.plain)
  }

  @ViewBuilder
  private func catalogPicker(for target: ConcertCatalogPickerTarget) -> some View {
    switch target {
    case let .artist(id):
      CatalogPickerView(
        repository: musicCatalogRepository,
        configuration: CatalogPickerConfiguration(
          kind: .artist,
          title: "Choose headliner",
          currentSelectionName: draft.artists.first(where: { $0.id == id })?.selection?.displayName
        )
      ) { entity in
        guard case let .artist(artist) = entity else { return }
        draft.setArtist(artist, for: id)
        catalogPickerTarget = nil
      }
    case .place:
      CatalogPickerView(
        repository: musicCatalogRepository,
        configuration: CatalogPickerConfiguration(
          kind: .place,
          title: "Choose venue",
          currentSelectionName: draft.place?.displayName
        )
      ) { entity in
        guard case let .place(place) = entity else { return }
        draft.place = place
        catalogPickerTarget = nil
      }
    case .song, .tour:
      EmptyView()
    }
  }
}

private extension Duration {
  var creationTelemetryMilliseconds: Int {
    let components = components
    return Int(components.seconds * 1000 + components.attoseconds / 1_000_000_000_000_000)
  }
}

private struct ConcertSavedView: View {
  let concert: Concert
  let primaryArtistName: String
  let concertRepository: any ConcertRepository
  let onDone: () -> Void

  var body: some View {
    ZStack {
      TunedInDesign.pageBackground
        .ignoresSafeArea()

      VStack(alignment: .leading, spacing: 14) {
        Text("Saved")
          .font(.system(size: 42, weight: .bold, design: .rounded))
          .foregroundStyle(TunedInDesign.primaryText)
        Text("Your concert is private until you decide to share it.")
          .font(.subheadline)
          .foregroundStyle(TunedInDesign.mutedText)

        ZStack(alignment: .bottomLeading) {
          ConcertPhotoView(concert: concert, artistName: primaryArtistName, repository: concertRepository)
            .frame(maxWidth: .infinity)
            .aspectRatio(CGSize(width: 3, height: 4), contentMode: .fit)
            .overlay {
              LinearGradient(
                colors: [.clear, .black.opacity(0.1), .black.opacity(0.82)],
                startPoint: .top,
                endPoint: .bottom
              )
            }

          VStack(alignment: .leading, spacing: 5) {
            Label("Private concert", systemImage: "checkmark.circle.fill")
              .font(.caption.weight(.bold))
              .foregroundStyle(.white.opacity(0.86))
            Text(primaryArtistName)
              .font(.system(size: 32, weight: .bold, design: .serif))
              .foregroundStyle(.white)
              .lineLimit(2)
            Text("\(concert.venueName) · \(formattedConcertDate)")
              .font(.subheadline.weight(.semibold))
              .foregroundStyle(.white.opacity(0.9))
              .lineLimit(1)
          }
          .padding(18)
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))

        Spacer()

        Button("Done", action: onDone)
          .font(.headline)
          .foregroundStyle(TunedInDesign.actionForeground)
          .frame(maxWidth: .infinity)
          .padding(.vertical, 16)
          .background(TunedInDesign.accent, in: Capsule())
      }
      .padding(.horizontal, 20)
      .padding(.top, 18)
      .padding(.bottom, 8)
    }
  }

  private var formattedConcertDate: String {
    guard let date = Self.storageDateFormatter.date(from: concert.concertDate) else {
      return concert.concertDate
    }

    return Self.displayDateFormatter.string(from: date).uppercased()
  }

  private static let storageDateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .iso8601)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter
  }()

  private static let displayDateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .iso8601)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "MMM d, yyyy"
    return formatter
  }()
}
