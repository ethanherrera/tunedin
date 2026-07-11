import SwiftUI

struct ConcertCreationView: View {
  let concertRepository: any ConcertRepository

  @Environment(\.dismiss) private var dismiss

  @State var draft = ConcertDraft()
  @State private var isSaving = false
  @State private var isShowingDiscardConfirmation = false
  @State private var saveError: String?

  var body: some View {
    NavigationStack {
      List {
        essentialsSection
        lineupSection
        detailsSection
        setlistSection
        visibilitySection
      }
      .listStyle(.insetGrouped)
      .scrollContentBackground(.hidden)
      .background(TunedInDesign.pageBackground)
      .navigationTitle("New concert")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button("Cancel", action: requestDismissal)
            .disabled(isSaving)
        }

        ToolbarItem(placement: .topBarTrailing) {
          Button {
            save()
          } label: {
            if isSaving {
              ProgressView()
            } else {
              Text("Save")
                .fontWeight(.semibold)
            }
          }
          .disabled(!draft.canSave || isSaving)
          .accessibilityHint("Saves this concert privately")
        }

        if draft.artists.count > 1 || draft.setlist.count > 1 {
          ToolbarItem(placement: .bottomBar) {
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
        _ = try await concertRepository.createPrivateConcert(input)
        isSaving = false
        dismiss()
      } catch {
        isSaving = false
        saveError = error.localizedDescription
      }
    }
  }
}
