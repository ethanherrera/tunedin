import Foundation
import Testing
@testable import tunedIn

struct AppSessionSignOutTests {
  @MainActor
  @Test
  func explicitSignOutClearsLocalStateBeforeRemoteCleanupCompletes() async throws {
    let user = try makeUser("A0000000-0000-0000-0000-000000000001", email: "account-a@example.test")
    let repository = ControlledAuthenticationRepository(
      initialUser: user,
      signInUser: nil,
      signOutBehavior: .suspended
    )
    let google = GoogleAuthenticationClientSpy(credentials: googleCredentials)
    let session = makeSession(
      authenticationRepository: repository,
      googleAuthenticationClient: google,
      profiles: [user.id: makeProfile(for: user, displayName: "Account A")]
    )
    await settle(session)

    let signOutTask = Task { await session.signOut() }
    await repository.waitUntilSignOutStarted()

    guard case .signedOut = session.phase else {
      Issue.record("Expected local signed-out state before remote cleanup finished")
      return
    }
    #expect(google.signOutCallCount == 1)
    #expect(await repository.signOutCallCount == 1)

    await repository.emit(user)
    await settleEvents()
    guard case .signedOut = session.phase else {
      Issue.record("A stale account event must not restore the explicitly signed-out user")
      return
    }

    await repository.resumeSignOut()
    await signOutTask.value
    await repository.emit(user)
    await settleEvents()
    guard case .signedOut = session.phase else {
      Issue.record("The signed-out account must remain blocked after remote cleanup")
      return
    }
  }

  @MainActor
  @Test
  func failedRemoteSignOutStillPurgesViewerState() async throws {
    let user = try makeUser("A0000000-0000-0000-0000-000000000002", email: "offline@example.test")
    let repository = ControlledAuthenticationRepository(
      initialUser: user,
      signInUser: nil,
      signOutBehavior: .failure(.offline)
    )
    let google = GoogleAuthenticationClientSpy(credentials: googleCredentials)
    let responseCache = URLCache(memoryCapacity: 1_024_000, diskCapacity: 0)
    let mediaCache = AppMediaCache(
      environment: .development,
      urlCache: responseCache,
      dataLoader: UnavailableMediaDataLoader()
    )
    let dataCache = try AppDataCache.inMemory(mediaCache: mediaCache)
    let telemetry = makeTelemetry()
    let session = makeSession(
      authenticationRepository: repository,
      googleAuthenticationClient: google,
      profiles: [user.id: makeProfile(for: user, displayName: "Offline Account")],
      dataCache: dataCache,
      telemetry: telemetry
    )
    await settle(session)

    let (dataResource, mediaResource) = try await populateViewerCaches(
      dataCache: dataCache,
      mediaCache: mediaCache,
      responseCache: responseCache,
      userID: user.id
    )

    await session.signOut()

    guard case .signedOut = session.phase else {
      Issue.record("Remote cleanup failure must not restore the previous account")
      return
    }
    #expect(session.lastSignOutFailure == .offline)
    #expect(google.signOutCallCount == 1)
    #expect(await dataCache.state(for: dataResource, freshness: .init(freshFor: 60, maximumStale: 300)) == .missing)
    #expect(await mediaCache.contains(mediaResource) == false)
    #expect(await mediaCache.signedURLs.entryCount() == 0)
    #expect(telemetry.recentRecords.filter { $0.kind == .identity && $0.name == "reset" }.count == 1)
  }

  @MainActor
  @Test
  func userInitiatedGoogleSignInCanSelectAccountB() async throws {
    let accountA = try makeUser("A0000000-0000-0000-0000-000000000003", email: "a@example.test")
    let accountB = try makeUser("B0000000-0000-0000-0000-000000000003", email: "b@example.test")
    let repository = ControlledAuthenticationRepository(
      initialUser: accountA,
      signInUser: accountB,
      signOutBehavior: .immediate
    )
    let google = GoogleAuthenticationClientSpy(credentials: googleCredentials)
    let session = makeSession(
      authenticationRepository: repository,
      googleAuthenticationClient: google,
      profiles: [
        accountA.id: makeProfile(for: accountA, displayName: "Account A"),
        accountB.id: makeProfile(for: accountB, displayName: "Account B")
      ]
    )
    await settle(session)
    await session.signOut()

    let credentials = try await session.googleCredentials()
    #expect(google.restorePolicies == [false])
    try await session.signIn(with: credentials)
    await settle(session)

    guard case let .signedIn(user, profile) = session.phase else {
      Issue.record("Expected the deliberately selected Google account B to open")
      return
    }
    #expect(user == accountB)
    #expect(profile.displayName == "Account B")

    await repository.emit(accountA)
    await settleEvents()
    guard case let .signedIn(userAfterStaleEvent, _) = session.phase else {
      Issue.record("Expected account B to remain visible")
      return
    }
    #expect(userAfterStaleEvent == accountB)
  }

  @MainActor
  @Test
  func explicitSignOutInvalidatesAnOlderNativeSignInExchange() async throws {
    let accountB = try makeUser("B0000000-0000-0000-0000-000000000004", email: "b@example.test")
    let repository = ControlledAuthenticationRepository(
      initialUser: nil,
      signInUser: accountB,
      signInBehavior: .suspended,
      signOutBehavior: .immediate
    )
    let session = makeSession(
      authenticationRepository: repository,
      googleAuthenticationClient: GoogleAuthenticationClientSpy(credentials: googleCredentials),
      profiles: [accountB.id: makeProfile(for: accountB, displayName: "Account B")]
    )
    await settle(session)

    let signInTask = Task {
      try await session.signIn(with: googleCredentials)
    }
    await repository.waitUntilSignInStarted()
    guard await waitUntilSignedIn(session) else {
      Issue.record("Expected the repository event to expose the in-flight account")
      return
    }

    await session.signOut()
    await repository.resumeSignIn()
    await #expect(throws: CancellationError.self) {
      try await signInTask.value
    }
    await repository.emit(accountB)
    await settleEvents()

    guard case .signedOut = session.phase else {
      Issue.record("An older sign-in result must not resurrect an explicitly signed-out account")
      return
    }
  }

  @MainActor
  @Test
  func explicitSignOutInvalidatesAnOlderProfileMutation() async throws {
    let user = try makeUser("A0000000-0000-0000-0000-000000000005", email: "a@example.test")
    let profile = makeProfile(for: user, displayName: "Account A")
    let profileRepository = SuspendedProfileMutationRepository(profile: profile)
    let session = makeSession(
      authenticationRepository: ControlledAuthenticationRepository(
        initialUser: user,
        signInUser: nil,
        signOutBehavior: .immediate
      ),
      googleAuthenticationClient: GoogleAuthenticationClientSpy(credentials: googleCredentials),
      profiles: [:],
      profileRepository: profileRepository
    )
    await settle(session)

    let mutation = Task {
      try await session.completeOnboarding(username: "account_a", displayName: "Account A")
    }
    await profileRepository.waitUntilMutationStarted()
    await session.signOut()
    await profileRepository.finishMutation()

    await #expect(throws: CancellationError.self) {
      try await mutation.value
    }
    guard case .signedOut = session.phase else {
      Issue.record("A late profile mutation must not restore the signed-out account")
      return
    }
  }

  @MainActor
  private func makeSession(
    authenticationRepository: any AuthenticationRepository,
    googleAuthenticationClient: any GoogleAuthenticationClient,
    profiles: [UUID: Profile],
    profileRepository: (any ProfileRepository)? = nil,
    dataCache: AppDataCache? = nil,
    telemetry: AppTelemetryClient? = nil
  ) -> AppSession {
    let resolvedProfileRepository: any ProfileRepository = profileRepository
      ?? ProfilesByUserRepository(profiles: profiles)
    return AppSession(
      authenticationRepository: authenticationRepository,
      googleAuthenticationClient: googleAuthenticationClient,
      profileRepository: resolvedProfileRepository,
      dataCache: dataCache,
      nativeSocialAuthConfiguration: NativeSocialAuthConfiguration(
        googleIOSClientID: "ios.apps.googleusercontent.com",
        googleServerClientID: "server.apps.googleusercontent.com"
      ),
      telemetry: telemetry ?? makeTelemetry()
    )
  }

  @MainActor
  private func makeTelemetry() -> AppTelemetryClient {
    AppTelemetryClient(
      configuration: .recording,
      release: ReleaseMetadata(
        version: "test",
        build: "test",
        gitSHA: "test",
        environment: .development
      )
    )
  }

  private func makeUser(_ id: String, email: String) throws -> AuthenticatedUser {
    try AuthenticatedUser(id: #require(UUID(uuidString: id)), email: email)
  }

  private func makeProfile(for user: AuthenticatedUser, displayName: String) -> Profile {
    Profile(
      id: user.id,
      username: displayName.lowercased().replacingOccurrences(of: " ", with: "_"),
      displayName: displayName,
      onboardingCompletedAt: Date(timeIntervalSince1970: 1),
      createdAt: Date(timeIntervalSince1970: 0),
      updatedAt: Date(timeIntervalSince1970: 1)
    )
  }

  private var googleCredentials: NativeAuthCredentials {
    NativeAuthCredentials(
      provider: .google,
      idToken: "interactive-id-token",
      accessToken: "interactive-access-token",
      nonce: nil
    )
  }

  private func populateViewerCaches(
    dataCache: AppDataCache,
    mediaCache: AppMediaCache,
    responseCache: URLCache,
    userID: UUID
  ) async throws -> (AppCacheResource, AppMediaResource) {
    let dataResource = AppCacheResource(name: "sign-out-test", variant: "viewer")
    try await dataCache.store(42, for: dataResource)
    let mediaResource = AppMediaResource.avatar(profileID: userID, version: 1)
    try responseCache.storeCachedResponse(
      CachedURLResponse(
        response: URLResponse(
          url: #require(mediaResource.cacheRequest.url),
          mimeType: "image/jpeg",
          expectedContentLength: 1,
          textEncodingName: nil
        ),
        data: Data([0x01])
      ),
      for: mediaResource.cacheRequest
    )
    _ = try await mediaCache.signedURLs.value(for: .avatar(profileID: userID, version: 1)) {
      URL(string: "https://storage.example.test/avatar.jpg?token=private")!
    }
    return (dataResource, mediaResource)
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

  private func settleEvents() async {
    try? await Task.sleep(for: .milliseconds(50))
  }

  @MainActor
  private func waitUntilSignedIn(_ session: AppSession) async -> Bool {
    for _ in 0 ..< 100 {
      if case .signedIn = session.phase {
        return true
      }
      try? await Task.sleep(for: .milliseconds(10))
    }
    return false
  }
}

@MainActor
private final class GoogleAuthenticationClientSpy: GoogleAuthenticationClient {
  let credentialsValue: NativeAuthCredentials
  private(set) var restorePolicies: [Bool] = []
  private(set) var signOutCallCount = 0

  init(credentials: NativeAuthCredentials) {
    credentialsValue = credentials
  }

  func credentials(
    configuration _: NativeSocialAuthConfiguration,
    allowsPreviousSignInRestore: Bool
  ) async throws -> NativeAuthCredentials {
    restorePolicies.append(allowsPreviousSignInRestore)
    return credentialsValue
  }

  func signOut() {
    signOutCallCount += 1
  }
}

private actor ControlledAuthenticationRepository: AuthenticationRepository {
  enum SignInBehavior: Sendable {
    case immediate
    case suspended
  }

  enum SignOutBehavior: Sendable {
    case immediate
    case suspended
    case failure(AppFailure)
  }

  nonisolated let authenticationStateChanges: AsyncStream<AuthenticatedUser?>
  private let continuation: AsyncStream<AuthenticatedUser?>.Continuation
  private let signInUser: AuthenticatedUser?
  private let signInBehavior: SignInBehavior
  private let signOutBehavior: SignOutBehavior
  private var signInContinuation: CheckedContinuation<Void, Never>?
  private var signOutContinuation: CheckedContinuation<Void, Never>?
  private(set) var signInCallCount = 0
  private(set) var signOutCallCount = 0

  init(
    initialUser: AuthenticatedUser?,
    signInUser: AuthenticatedUser?,
    signInBehavior: SignInBehavior = .immediate,
    signOutBehavior: SignOutBehavior
  ) {
    let stream = AsyncStream<AuthenticatedUser?>.makeStream()
    authenticationStateChanges = stream.stream
    continuation = stream.continuation
    self.signInUser = signInUser
    self.signInBehavior = signInBehavior
    self.signOutBehavior = signOutBehavior
    continuation.yield(initialUser)
  }

  func emit(_ user: AuthenticatedUser?) {
    continuation.yield(user)
  }

  func waitUntilSignOutStarted() async {
    while signOutCallCount == 0 {
      await Task.yield()
    }
  }

  func waitUntilSignInStarted() async {
    while signInCallCount == 0 {
      await Task.yield()
    }
  }

  func resumeSignIn() {
    signInContinuation?.resume()
    signInContinuation = nil
  }

  func resumeSignOut() {
    signOutContinuation?.resume()
    signOutContinuation = nil
  }

  func sendEmailOTP(to _: String) async throws {}
  func signInWithPassword(email _: String, password _: String) async throws {}
  func verifyEmailOTP(email _: String, code _: String) async throws {}

  func signIn(with _: NativeAuthCredentials) async throws -> AuthenticatedUser {
    guard let signInUser else { throw AppFailure.unavailable }
    signInCallCount += 1
    continuation.yield(signInUser)
    switch signInBehavior {
    case .immediate:
      break
    case .suspended:
      await withCheckedContinuation { continuation in
        signInContinuation = continuation
      }
    }
    return signInUser
  }

  func signOut() async throws {
    signOutCallCount += 1
    switch signOutBehavior {
    case .immediate:
      break
    case .suspended:
      await withCheckedContinuation { continuation in
        signOutContinuation = continuation
      }
    case let .failure(failure):
      throw failure
    }
    continuation.yield(nil)
  }

  func handleAuthCallback(_: URL) async throws {}
}

private struct ProfilesByUserRepository: ProfileRepository {
  let profiles: [UUID: Profile]

  func fetchProfile(for userID: UUID) async throws -> Profile {
    guard let profile = profiles[userID] else { throw AppFailure.unavailable }
    return profile
  }

  func isUsernameAvailable(_: String) async throws -> Bool {
    true
  }

  func completeOnboarding(username _: String, displayName _: String) async throws -> Profile {
    throw AppFailure.unavailable
  }

  func setAvatar(jpegData _: Data, for _: UUID) async throws -> Profile {
    throw AppFailure.unavailable
  }

  func removeAvatar(for _: UUID) async throws -> Profile {
    throw AppFailure.unavailable
  }

  func avatarURL(profileID _: UUID, objectPath _: String, version _: Int64) async throws -> URL {
    throw AppFailure.unavailable
  }
}

private actor SuspendedProfileMutationRepository: ProfileRepository {
  let profile: Profile
  private var mutationContinuation: CheckedContinuation<Profile, Never>?

  init(profile: Profile) {
    self.profile = profile
  }

  func fetchProfile(for _: UUID) async throws -> Profile {
    profile
  }

  func isUsernameAvailable(_: String) async throws -> Bool {
    true
  }

  func completeOnboarding(username _: String, displayName _: String) async throws -> Profile {
    await withCheckedContinuation { continuation in
      mutationContinuation = continuation
    }
  }

  func waitUntilMutationStarted() async {
    while mutationContinuation == nil {
      await Task.yield()
    }
  }

  func finishMutation() {
    mutationContinuation?.resume(returning: profile)
    mutationContinuation = nil
  }

  func setAvatar(jpegData _: Data, for _: UUID) async throws -> Profile {
    throw AppFailure.unavailable
  }

  func removeAvatar(for _: UUID) async throws -> Profile {
    throw AppFailure.unavailable
  }

  func avatarURL(profileID _: UUID, objectPath _: String, version _: Int64) async throws -> URL {
    throw AppFailure.unavailable
  }
}

private struct UnavailableMediaDataLoader: AppMediaDataLoading {
  func data(for _: URLRequest) async throws -> (Data, URLResponse) {
    throw AppFailure.unavailable
  }
}
