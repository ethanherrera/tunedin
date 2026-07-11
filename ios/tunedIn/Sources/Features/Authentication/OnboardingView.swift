import SwiftUI

struct OnboardingView: View {
  let session: AppSession
  let user: AuthenticatedUser

  @State private var username = ""
  @State private var displayName = ""
  @State private var availability: UsernameAvailability = .idle
  @State private var availabilityTask: Task<Void, Never>?
  @State private var isCompleting = false
  @State private var errorMessage: String?

  var body: some View {
    NavigationStack {
      Form {
        Section {
          Text("Choose how friends will find you. You can update these details later.")
            .foregroundStyle(.secondary)
        }

        Section("Your profile") {
          TextField("Username", text: $username)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .onChange(of: username) { _, _ in
              evaluateUsername()
            }

          usernameStatus

          TextField("Display name", text: $displayName)
            .textContentType(.name)

          Text(
            "Usernames use 3–24 lowercase letters, numbers, and underscores. "
              + "Display names can be up to 50 characters."
          )
          .font(.footnote)
          .foregroundStyle(.secondary)
        }

        if let errorMessage {
          Section {
            Text(errorMessage)
              .font(.footnote)
              .foregroundStyle(.red)
          }
        }

        Section {
          Button {
            completeOnboarding()
          } label: {
            if isCompleting {
              ProgressView()
                .frame(maxWidth: .infinity)
            } else {
              Text("Finish setup")
                .frame(maxWidth: .infinity)
            }
          }
          .disabled(!canComplete)
        }
      }
      .navigationTitle("Set up your profile")
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button("Sign Out") {
            Task {
              await session.signOut()
            }
          }
        }
      }
    }
  }

  @ViewBuilder
  private var usernameStatus: some View {
    switch availability {
    case .idle:
      EmptyView()
    case .checking:
      Label("Checking username…", systemImage: "hourglass")
        .font(.footnote)
        .foregroundStyle(.secondary)
    case .available:
      Label("Username is available", systemImage: "checkmark.circle.fill")
        .font(.footnote)
        .foregroundStyle(.green)
    case .unavailable:
      Label("That username is unavailable", systemImage: "xmark.circle.fill")
        .font(.footnote)
        .foregroundStyle(.red)
    case .invalid:
      Label("Use the username format below", systemImage: "exclamationmark.circle")
        .font(.footnote)
        .foregroundStyle(.red)
    case .failed:
      Label("We couldn’t check that username. Try again.", systemImage: "wifi.exclamationmark")
        .font(.footnote)
        .foregroundStyle(.red)
    }
  }

  private var canComplete: Bool {
    !isCompleting
      && availability == .available
      && ProfileInput.isDisplayNameValid(displayName)
  }

  private func evaluateUsername() {
    availabilityTask?.cancel()
    errorMessage = nil

    let normalizedUsername = ProfileInput.normalizedUsername(username)
    guard normalizedUsername == username else {
      username = normalizedUsername
      return
    }

    guard ProfileInput.isUsernameValid(username) else {
      availability = username.isEmpty ? .idle : .invalid
      return
    }

    availability = .checking
    let usernameToCheck = username
    availabilityTask = Task {
      try? await Task.sleep(nanoseconds: 350_000_000)
      guard !Task.isCancelled else { return }

      do {
        let isAvailable = try await session.checkUsernameAvailability(usernameToCheck)
        guard !Task.isCancelled, username == usernameToCheck else { return }
        availability = isAvailable ? .available : .unavailable
      } catch {
        guard !Task.isCancelled, username == usernameToCheck else { return }
        availability = .failed
      }
    }
  }

  private func completeOnboarding() {
    isCompleting = true
    errorMessage = nil

    Task {
      do {
        try await session.completeOnboarding(username: username, displayName: displayName)
      } catch {
        errorMessage = error.localizedDescription
        availability = .failed
      }
      isCompleting = false
    }
  }
}

private enum UsernameAvailability: Equatable {
  case idle
  case checking
  case available
  case unavailable
  case invalid
  case failed
}
