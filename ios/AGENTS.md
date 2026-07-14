# iOS Client Guide

## Responsibility

`ios/` contains the SwiftUI iPhone app and its Xcode project definition. Support iOS 17+ with iPhone portrait layouts; validate UI work in an iPhone 13 Simulator.

## Architecture and dependencies

- Use Swift 6 strict concurrency, SwiftUI, Observation, typed `NavigationStack` routes, and one app-owned dependency container.
- Keep Supabase DTOs and SDK details behind repository protocols. Feature views receive app-owned domain models, not raw backend shapes.
- Use Apple frameworks and Swift Package Manager only. Do not add a third-party UI, state-management, persistence, or image-cache library without approval.
- Keep design-system primitives in `ios/tunedIn/Sources/Core/DesignSystem`; do not scatter appearance availability checks through feature views.
- Prefer adaptive system Liquid Glass for bottom screen traversal and contextual menus whenever available, falling back through design-system primitives on older iOS versions. Give back navigation its own glass control, group related page destinations in a central glass surface, and represent the contextual edit menu with a three-dot glass action rather than a pencil.
- Give scrollable server-backed read surfaces pull-to-refresh with `.refreshable`. Await every visible repository reload before ending the spinner, preserve already loaded content when a refresh fails, and keep forms, local-only settings, and mutation-only sheets exempt when refreshing could disrupt edits or misrepresent static data.
- Route cacheable server reads through the app-owned repository decorators and shared `AppDataCache`; do not add view-owned persistence or one-off feature caches. Normal navigation is cache-first, explicit refresh bypasses cached snapshots, later pagination and conflict-sensitive reads stay authoritative, Realtime marks affected data stale instead of forcing full refetches, and successful mutations patch or invalidate every dependent key.
- Load protected remote media through `CachedRemoteImage` and the shared `AppMediaCache`; do not add direct `AsyncImage` downloads or feature-owned image caches. Keep expiring signed URLs memory-only, persist media only under opaque versioned keys, never write upload bytes or signed URLs to SwiftData, and preserve the account/environment purge, storage-protection, and bounded-budget rules when adding media surfaces.

## Environment and verification

- `project.yml` is the source for the root `tunedIn.xcodeproj`; run `make generate` after changing it.
- Configuration files in `Config/` are ignored; only `.xcconfig.example` templates belong in Git.
- `tunedIn-Development` targets the shared hosted Development project. `tunedIn-Local` uses `Local.xcconfig` generated from the disposable Docker stack; `make simulator-local` refreshes it automatically, or use `make configure-local-supabase` directly. Never paste local keys into source or a committed configuration.
- Run `make lint` and `make test`. Use Xcode/Simulator for visual inspection, runtime logs, crashes, profiling, signing, or capabilities.
- When testing the temporary Development magic-link flow, copy the email button's link address and run `make simulator-auth-link` with tunedIn installed in a booted Simulator. Never paste, print, or commit the one-time Auth URL or token.
- Use `make simulator-onboarding`, `make simulator-profile`, and `make simulator-profile-error` for deterministic UI-only states, and `make simulator-live` for the real Supabase-backed flow. Scenario code must be compiled behind `DEBUG`, additionally require the Development environment, use app-owned in-memory repositories, and never access or bypass Supabase authorization.
- Use `make simulator-local` for a real app-to-local-Supabase journey. It is the integration path for creating users, profiles, concerts, friendships, and collaboration data without touching `tunedin-dev`.
- `make local-db-reset` also provisions the documented Local journey catalog: complete accounts, an onboarding account, friendship states, discoverable people, owned/shared concerts, comments, and activity. Prefer those valid backend states for manual local testing; update the seed and its verifier whenever a new local-testable journey is added or changed.
- The Local sign-in screen may offer a seeded-account picker only when Local configuration is loopback-constrained. It must call normal Supabase authentication for synthetic, non-privileged accounts; never fabricate a session, embed hosted credentials, or expose the picker in Development, Staging, or Production.
