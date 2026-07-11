#if DEBUG
  import Testing
  @testable import tunedIn

  struct DevelopmentScenarioTests {
    @Test
    func parsesKnownLaunchScenario() {
      let scenario = DevelopmentScenario.requested(
        arguments: ["tunedIn", "-TUNEDIN_DEVELOPMENT_SCENARIO", "onboarding"]
      )

      #expect(scenario == .onboarding)
    }

    @Test
    func rejectsUnknownLaunchScenario() {
      let scenario = DevelopmentScenario.requested(
        arguments: ["tunedIn", "-TUNEDIN_DEVELOPMENT_SCENARIO", "unknown"]
      )

      #expect(scenario == nil)
    }

    @MainActor
    @Test
    func onboardingScenarioRoutesToOnboarding() async {
      let session = DevelopmentScenario.onboarding.makeAppSession(
        authEmailDeliveryMode: .magicLink
      )

      await settle(session)

      guard case .needsOnboarding = session.phase else {
        Issue.record("Expected the Development onboarding scenario to require onboarding")
        return
      }
    }

    @MainActor
    @Test
    func profileScenarioRoutesToCompletedProfile() async {
      let session = DevelopmentScenario.profile.makeAppSession(
        authEmailDeliveryMode: .magicLink
      )

      await settle(session)

      guard case .signedIn = session.phase else {
        Issue.record("Expected the Development profile scenario to open the main tabs")
        return
      }
    }

    @MainActor
    @Test
    func profileErrorScenarioRoutesToFailure() async {
      let session = DevelopmentScenario.profileError.makeAppSession(
        authEmailDeliveryMode: .magicLink
      )

      await settle(session)

      guard case .profileUnavailable = session.phase else {
        Issue.record("Expected the Development profile-error scenario to show a failure")
        return
      }
    }

    @MainActor
    private func settle(_ session: AppSession) async {
      for _ in 0 ..< 100 {
        switch session.phase {
        case .restoring, .loadingProfile:
          try? await Task.sleep(for: .milliseconds(10))
        default:
          return
        }
      }
    }
  }
#endif
