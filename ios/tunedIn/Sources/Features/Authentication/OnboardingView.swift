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
    ZStack {
      TunedInDesign.pageBackground
        .ignoresSafeArea()

      ScrollView {
        VStack(alignment: .leading, spacing: 22) {
          VStack(alignment: .leading, spacing: 8) {
            Text("One last thing")
              .font(.caption.weight(.black))
              .tracking(1.1)
              .foregroundStyle(TunedInDesign.accent)
              .textCase(.uppercase)
            Text("Make your concert diary yours.")
              .font(.system(size: 34, weight: .bold, design: .rounded))
              .foregroundStyle(TunedInDesign.primaryText)
            Text("Choose how friends will find you. You can update these details later.")
              .font(.body)
              .foregroundStyle(TunedInDesign.mutedText)
          }

          TunedInFormCard {
            Text("Your profile")
              .font(.headline)
              .foregroundStyle(TunedInDesign.primaryText)

            VStack(alignment: .leading, spacing: 8) {
              Text("Username")
                .font(.caption.weight(.semibold))
                .foregroundStyle(TunedInDesign.mutedText)
              TextField("concert_friend", text: $username)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(.horizontal, 14)
                .frame(minHeight: 50)
                .background(
                  TunedInDesign.raisedSurface,
                  in: RoundedRectangle(cornerRadius: TunedInDesign.smallCornerRadius, style: .continuous)
                )
                .onChange(of: username) { _, _ in
                  evaluateUsername()
                }

              usernameStatus
            }

            VStack(alignment: .leading, spacing: 8) {
              Text("Display name")
                .font(.caption.weight(.semibold))
                .foregroundStyle(TunedInDesign.mutedText)
              TextField("Your name", text: $displayName)
                .textContentType(.name)
                .padding(.horizontal, 14)
                .frame(minHeight: 50)
                .background(
                  TunedInDesign.raisedSurface,
                  in: RoundedRectangle(cornerRadius: TunedInDesign.smallCornerRadius, style: .continuous)
                )
            }

            Text(
              "Usernames use 3–24 lowercase letters, numbers, and underscores. "
                + "Display names can be up to 50 characters."
            )
            .font(.footnote)
            .foregroundStyle(TunedInDesign.mutedText)
          }

          if let errorMessage {
            Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
              .font(.footnote)
              .foregroundStyle(.red)
          }

          Button {
            completeOnboarding()
          } label: {
            HStack(spacing: 9) {
              if isCompleting {
                ProgressView()
              }
              Text(isCompleting ? "Setting up…" : "Finish setup")
            }
            .font(.body.weight(.bold))
            .foregroundStyle(TunedInDesign.actionForeground)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(TunedInDesign.accent, in: Capsule())
          }
          .buttonStyle(.plain)
          .disabled(!canComplete)
          .opacity(canComplete ? 1 : 0.5)

          Button("Sign out and start over") {
            Task { await session.signOut() }
          }
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(TunedInDesign.mutedText)
          .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 20)
        .padding(.top, 28)
        .padding(.bottom, 32)
      }
    }
    .tint(TunedInDesign.accent)
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
