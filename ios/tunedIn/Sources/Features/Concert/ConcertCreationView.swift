import PhotosUI
import SwiftUI

struct ConcertCreationView: View {
  let concertRepository: any ConcertRepository

  @Environment(\.dismiss) private var dismiss
  @Environment(\.telemetry) private var telemetry

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
                  .padding(.top, 18)
                detailsPrompt
                  .padding(.top, 16)
              }
              .padding(.bottom, 18)
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
          }
          .navigationBarTitleDisplayMode(.inline)
          .safeAreaInset(edge: .bottom, spacing: 0) {
            saveBar
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
    VStack(alignment: .leading, spacing: 6) {
      HStack {
        Text("tunedIn")
          .font(.caption.weight(.black))
          .foregroundStyle(TunedInDesign.accent)
          .textCase(.uppercase)
        Spacer()
        TunedInPrivacyBadge()
      }

      Text("Log a concert")
        .font(.system(size: 36, weight: .bold, design: .serif))
        .foregroundStyle(TunedInDesign.primaryText)
      Text("Artist, venue, date.")
        .font(.subheadline)
        .foregroundStyle(TunedInDesign.mutedText)
    }
  }

  private var quickCaptureCard: some View {
    VStack(alignment: .leading, spacing: 16) {
      VStack(spacing: 10) {
        PhotosPicker(selection: $selectedPhoto, matching: .images) {
          ZStack(alignment: .bottomTrailing) {
            Group {
              if let concertPhotoData, let image = UIImage(data: concertPhotoData) {
                Image(uiImage: image).resizable().scaledToFill()
              } else {
                ConcertArtworkImage(artistName: draft.artists[0].name)
              }
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(CGSize(width: 3, height: 4), contentMode: .fit)
            .clipped()
            Label(concertPhotoData == nil ? "Add main photo" : "Change photo", systemImage: "photo")
              .font(.caption.weight(.bold)).padding(10)
              .foregroundStyle(.white).background(.black.opacity(0.62), in: Capsule()).padding(10)
          }
          .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .disabled(isProcessingPhoto)
        if isProcessingPhoto {
          ProgressView("Optimizing photo…")
        }
      }

      TunedInTicketCard {
        Text("PRIVATE CONCERT")
          .font(.caption.weight(.bold))
          .foregroundStyle(.white.opacity(0.82))

        VStack(alignment: .leading, spacing: 5) {
          Text("Who did you see?")
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.white)
          TextField(
            "",
            text: artistNameBinding(for: draft.artists[0].id),
            prompt: Text("Artist").foregroundStyle(.white.opacity(0.54))
          )
          .font(.title2.weight(.bold))
          .foregroundStyle(.white)
          .tint(.white)
          .textInputAutocapitalization(.words)
          .submitLabel(.next)
          .accessibilityLabel("Primary artist")
          if draft.hasAttemptedSave, !ConcertInput.isValidRequiredText(draft.artists[0].name, maximumLength: 160) {
            captureValidationLabel("Enter the artist you saw.")
          }
        }

        Divider().overlay(.white.opacity(0.24))

        VStack(alignment: .leading, spacing: 5) {
          Text("Where was it?")
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.white)
          TextField(
            "",
            text: $draft.venueName,
            prompt: Text("Venue").foregroundStyle(.white.opacity(0.54))
          )
          .font(.title3.weight(.semibold))
          .foregroundStyle(.white)
          .tint(.white)
          .textContentType(.location)
          .textInputAutocapitalization(.words)
          .submitLabel(.done)
          .accessibilityLabel("Venue")
          if draft.hasAttemptedSave, !ConcertInput.isValidRequiredText(draft.venueName, maximumLength: 160) {
            captureValidationLabel("Enter the venue.")
          }
        }

        Divider().overlay(.white.opacity(0.24))

        HStack {
          Label("When", systemImage: "calendar")
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.white)
          Spacer()
          DatePicker("Concert date", selection: $draft.concertDate, displayedComponents: .date)
            .datePickerStyle(.compact)
            .labelsHidden()
            .tint(.white)
        }
      }
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
          .font(.title3.weight(.bold))
          .foregroundStyle(TunedInDesign.actionForeground)
          .frame(width: 43, height: 43)
          .background(TunedInDesign.accent, in: Circle())
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
        Image(systemName: "arrow.up.right")
          .font(.subheadline.weight(.bold))
          .foregroundStyle(TunedInDesign.accent)
      }
      .padding(14)
      .background(TunedInDesign.cardBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
      .overlay {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
          .strokeBorder(TunedInDesign.cardBorder.opacity(0.72))
      }
    }
    .buttonStyle(.plain)
    .accessibilityHint("Add the lineup, context, and setlist")
  }

  private var detailsSummary: String {
    let additions = (draft.artists.count - 1) + draft.setlist.count
    if additions == 0, draft.city.isEmpty, draft.tour.isEmpty, !draft.hasStartTime {
      return "Lineup, setlist, time, and more"
    }
    return "\(additions) added detail\(additions == 1 ? "" : "s")"
  }

  private func captureValidationLabel(_ message: String) -> some View {
    Label(message, systemImage: "exclamationmark.circle.fill")
      .font(.caption)
      .foregroundStyle(.white.opacity(0.92))
  }

  private func artistNameBinding(for id: UUID) -> Binding<String> {
    Binding(
      get: { draft.artists.first(where: { $0.id == id })?.name ?? "" },
      set: { value in
        guard let index = draft.artists.firstIndex(where: { $0.id == id }) else { return }
        draft.artists[index].name = value
      }
    )
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
        savedPrimaryArtistName = input.artists.first(where: \.isPrimary)?.name ?? input.artists[0].name
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
}

private extension Duration {
  var creationTelemetryMilliseconds: Int {
    let components = self.components
    return Int(components.seconds * 1_000 + components.attoseconds / 1_000_000_000_000_000)
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
        Text("tunedIn")
          .font(.caption.weight(.black))
          .foregroundStyle(TunedInDesign.accent)
          .textCase(.uppercase)

        Text("Saved")
          .font(.system(size: 44, weight: .bold, design: .serif))
          .foregroundStyle(TunedInDesign.primaryText)

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
          .background(TunedInDesign.accent, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
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
