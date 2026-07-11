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
          List {
            introductionSection
            quickCaptureSection
            personalizationSection
          }
          .listStyle(.plain)
          .scrollContentBackground(.hidden)
          .background(TunedInDesign.pageBackground)
          .scrollDismissesKeyboard(.interactively)
          .navigationBarTitleDisplayMode(.inline)
          .safeAreaInset(edge: .bottom, spacing: 0) {
            saveBar
          }
          .toolbar {
            ToolbarItem(placement: .topBarLeading) {
              Button("Cancel", action: requestDismissal)
                .disabled(isSaving)
            }

            ToolbarItem(placement: .topBarTrailing) {
              if isShowingDetails, draft.artists.count > 1 || draft.setlist.count > 1 {
                EditButton()
              }
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
