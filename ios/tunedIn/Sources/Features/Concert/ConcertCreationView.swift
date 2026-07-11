import SwiftUI

struct ConcertCreationView: View {
  let concertRepository: any ConcertRepository

  @Environment(\.dismiss) private var dismiss

  @State var draft = ConcertDraft()
  @State private var isSaving = false
  @State var isShowingDetails = false
  @State private var isShowingDiscardConfirmation = false
  @State private var saveError: String?
  @State private var savedConcert: Concert?
  @State private var savedPrimaryArtistName = ""

  var body: some View {
    Group {
      if let savedConcert {
        ConcertSavedView(
          concert: savedConcert,
          primaryArtistName: savedPrimaryArtistName,
          onDone: { dismiss() }
        )
        .transition(.opacity)
      } else {
        NavigationStack {
          ZStack {
            TunedInDesign.pageBackground
              .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
              captureHeader
              quickCaptureCard
                .padding(.top, 24)
              detailsPrompt
                .padding(.top, 16)
              Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
          }
          .navigationBarTitleDisplayMode(.inline)
          .safeAreaInset(edge: .bottom, spacing: 0) {
            saveBar
          }
          .toolbar {
            ToolbarItem(placement: .topBarLeading) {
              Button("Cancel", action: requestDismissal)
                .disabled(isSaving)
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
        }
      }
    }
    .tint(TunedInDesign.accent)
  }

  private var saveBar: some View {
    VStack {
      Button(action: save) {
        HStack(spacing: 8) {
          if isSaving {
            ProgressView()
              .tint(TunedInDesign.actionForeground)
          } else {
            Image(systemName: "lock.fill")
          }

          Text(draft.canSave ? "Save privately" : "Add artist and venue")
            .font(.headline)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
      }
      .buttonStyle(.plain)
      .foregroundStyle(draft.canSave && !isSaving ? TunedInDesign.actionForeground : TunedInDesign.mutedText)
      .background(
        draft.canSave && !isSaving ? TunedInDesign.accent : TunedInDesign.raisedSurface,
        in: RoundedRectangle(cornerRadius: 18, style: .continuous)
      )
      .overlay {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
          .strokeBorder(.white.opacity(draft.canSave && !isSaving ? 0 : 0.08))
      }
      .disabled(!draft.canSave || isSaving)
      .accessibilityHint("Saves this concert privately")
    }
    .padding(.horizontal, 20)
    .padding(.top, 12)
    .padding(.bottom, 8)
    .background(TunedInDesign.pageBackground.opacity(0.96))
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

      Text("Keep the night.")
        .font(.system(size: 36, weight: .bold, design: .serif))
        .foregroundStyle(TunedInDesign.primaryText)
      Text("Three things are enough. You can make it yours later.")
        .font(.subheadline)
        .foregroundStyle(TunedInDesign.mutedText)
    }
  }

  private var quickCaptureCard: some View {
    TunedInTicketCard {
      Text("YOUR PRIVATE NOTE")
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
          Text("Make it yours")
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
      return "Lineup, songs, time, and little details"
    }
    return "\(additions) detail\(additions == 1 ? "" : "s") held for this night"
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

    Task {
      do {
        let concert = try await concertRepository.createPrivateConcert(input)
        savedPrimaryArtistName = input.artists.first(where: \.isPrimary)?.name ?? input.artists[0].name
        savedConcert = concert
        isSaving = false
      } catch {
        isSaving = false
        saveError = error.localizedDescription
      }
    }
  }
}

private struct ConcertSavedView: View {
  let concert: Concert
  let primaryArtistName: String
  let onDone: () -> Void

  var body: some View {
    ZStack {
      TunedInDesign.pageBackground
        .ignoresSafeArea()

      VStack(alignment: .leading, spacing: 24) {
        Spacer()

        Text("tunedIn")
          .font(.subheadline.weight(.black))
          .foregroundStyle(TunedInDesign.accent)

        Text("Kept.")
          .font(.system(size: 46, weight: .bold, design: .serif))
          .foregroundStyle(TunedInDesign.primaryText)

        Text("One more night, safely yours.")
          .font(.title3)
          .foregroundStyle(TunedInDesign.mutedText)

        TunedInTicketCard {
          Label("PRIVATE ENTRY SAVED", systemImage: "checkmark.circle.fill")
            .font(.caption.weight(.bold))
            .foregroundStyle(.white.opacity(0.84))

          Text(primaryArtistName)
            .font(.title.weight(.bold))
            .foregroundStyle(.white)

          Text("\(concert.venueName)  •  \(formattedConcertDate)")
            .font(.subheadline)
            .foregroundStyle(.white.opacity(0.86))
        }

        Spacer()

        Button("Done", action: onDone)
          .font(.headline)
          .foregroundStyle(TunedInDesign.actionForeground)
          .frame(maxWidth: .infinity)
          .padding(.vertical, 16)
          .background(TunedInDesign.accent, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
      }
      .padding(24)
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
