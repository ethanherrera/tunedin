#if DEBUG
  import Foundation

  enum DevelopmentScenario: String, CaseIterable, Sendable {
    case live
    case signedOut = "signed-out"
    case onboarding
    case profile
    case profileError = "profile-error"

    private static let argumentName = "-TUNEDIN_DEVELOPMENT_SCENARIO"

    static func requested(arguments: [String] = ProcessInfo.processInfo.arguments) -> Self? {
      guard
        let argumentIndex = arguments.firstIndex(of: argumentName),
        arguments.indices.contains(argumentIndex + 1)
      else {
        return nil
      }

      return Self(rawValue: arguments[argumentIndex + 1])
    }

    @MainActor
    func makeAppSession(
      authEmailDeliveryMode: AuthEmailDeliveryMode,
      telemetry: AppTelemetryClient? = nil
    ) -> AppSession {
      let fixture = DevelopmentFixture()

      switch self {
      case .live:
        preconditionFailure("The live scenario must use Supabase repositories.")

      case .signedOut:
        return AppSession(
          authenticationRepository: DevelopmentAuthenticationRepository(user: nil),
          profileRepository: DevelopmentProfileRepository(result: .profile(fixture.incompleteProfile)),
          authEmailDeliveryMode: authEmailDeliveryMode,
          telemetry: telemetry ?? Self.makeTelemetry()
        )

      case .onboarding:
        return AppSession(
          authenticationRepository: DevelopmentAuthenticationRepository(user: fixture.user),
          profileRepository: DevelopmentProfileRepository(result: .profile(fixture.incompleteProfile)),
          authEmailDeliveryMode: authEmailDeliveryMode,
          telemetry: telemetry ?? Self.makeTelemetry()
        )

      case .profile:
        return AppSession(
          authenticationRepository: DevelopmentAuthenticationRepository(user: fixture.user),
          profileRepository: DevelopmentProfileRepository(result: .profile(fixture.completedProfile)),
          authEmailDeliveryMode: authEmailDeliveryMode,
          telemetry: telemetry ?? Self.makeTelemetry()
        )

      case .profileError:
        return AppSession(
          authenticationRepository: DevelopmentAuthenticationRepository(user: fixture.user),
          profileRepository: DevelopmentProfileRepository(result: .failure),
          authEmailDeliveryMode: authEmailDeliveryMode,
          telemetry: telemetry ?? Self.makeTelemetry()
        )
      }
    }

    @MainActor
    private static func makeTelemetry() -> AppTelemetryClient {
      AppTelemetryClient(
        configuration: .recording,
        release: ReleaseMetadata(
          version: "development-scenario",
          build: "local",
          gitSHA: "local",
          environment: .development
        )
      )
    }
  }

  private struct DevelopmentFixture {
    let userID = UUID(uuidString: "D0000000-0000-0000-0000-000000000001")!
    let createdAt = Date(timeIntervalSince1970: 1_735_689_600)

    var user: AuthenticatedUser {
      AuthenticatedUser(id: userID, email: "listener@development.test")
    }

    var incompleteProfile: Profile {
      Profile(
        id: userID,
        username: nil,
        displayName: nil,
        avatarObjectPath: nil,
        avatarVersion: 0,
        onboardingCompletedAt: nil,
        createdAt: createdAt,
        updatedAt: createdAt
      )
    }

    var completedProfile: Profile {
      Profile(
        id: userID,
        username: "dev_listener",
        displayName: "Development Listener",
        avatarObjectPath: nil,
        avatarVersion: 0,
        onboardingCompletedAt: createdAt,
        createdAt: createdAt,
        updatedAt: createdAt
      )
    }
  }

  private struct DevelopmentAuthenticationRepository: AuthenticationRepository {
    let user: AuthenticatedUser?

    var authenticationStateChanges: AsyncStream<AuthenticatedUser?> {
      AsyncStream { continuation in
        continuation.yield(user)
        continuation.finish()
      }
    }

    func sendEmailOTP(to _: String) async throws {
      throw DevelopmentScenarioError.liveAuthenticationRequired
    }

    func signInWithPassword(email _: String, password _: String) async throws {
      throw DevelopmentScenarioError.liveAuthenticationRequired
    }

    func verifyEmailOTP(email _: String, code _: String) async throws {
      throw DevelopmentScenarioError.liveAuthenticationRequired
    }

    func signIn(with _: NativeAuthCredentials) async throws {
      throw DevelopmentScenarioError.liveAuthenticationRequired
    }

    func signOut() async throws {}
    func handleAuthCallback(_: URL) async throws {}
  }

  private struct DevelopmentProfileRepository: ProfileRepository {
    enum Result: Sendable {
      case profile(Profile)
      case failure
    }

    let result: Result

    func fetchProfile(for _: UUID) async throws -> Profile {
      switch result {
      case let .profile(profile):
        profile
      case .failure:
        throw DevelopmentScenarioError.profileUnavailable
      }
    }

    func isUsernameAvailable(_ username: String) async throws -> Bool {
      ProfileInput.isUsernameValid(username) && username != "taken_username"
    }

    func completeOnboarding(username: String, displayName: String) async throws -> Profile {
      let fixture = DevelopmentFixture()
      return Profile(
        id: fixture.userID,
        username: ProfileInput.normalizedUsername(username),
        displayName: ProfileInput.normalizedDisplayName(displayName),
        avatarObjectPath: nil,
        avatarVersion: 0,
        onboardingCompletedAt: Date(),
        createdAt: fixture.createdAt,
        updatedAt: Date()
      )
    }

    func setAvatar(jpegData _: Data, for _: UUID) async throws -> Profile {
      throw DevelopmentScenarioError.liveAuthenticationRequired
    }

    func removeAvatar(for _: UUID) async throws -> Profile {
      throw DevelopmentScenarioError.liveAuthenticationRequired
    }

    func avatarURL(profileID _: UUID, objectPath _: String, version _: Int64) async throws -> URL {
      throw DevelopmentScenarioError.liveAuthenticationRequired
    }
  }

  private enum DevelopmentScenarioError: LocalizedError {
    case liveAuthenticationRequired
    case profileUnavailable

    var errorDescription: String? {
      switch self {
      case .liveAuthenticationRequired:
        "Use the live Development scenario to test Supabase authentication."
      case .profileUnavailable:
        "The Development profile scenario intentionally failed to load."
      }
    }
  }
#endif
