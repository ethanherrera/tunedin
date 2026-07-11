# iOS Client Guide

## Responsibility

`ios/` contains the SwiftUI iPhone app and its Xcode project definition. Support iOS 17+ with iPhone portrait layouts; validate UI work in an iPhone 13 Simulator.

## Architecture and dependencies

- Use Swift 6 strict concurrency, SwiftUI, Observation, typed `NavigationStack` routes, and one app-owned dependency container.
- Keep Supabase DTOs and SDK details behind repository protocols. Feature views receive app-owned domain models, not raw backend shapes.
- Use Apple frameworks and Swift Package Manager only. Do not add a third-party UI, state-management, persistence, or image-cache library without approval.
- Keep design-system primitives in `ios/tunedIn/Sources/Core/DesignSystem`; do not scatter appearance availability checks through feature views.

## Environment and verification

- `project.yml` is the source for the root `tunedIn.xcodeproj`; run `make generate` after changing it.
- Configuration files in `Config/` are ignored; only `.xcconfig.example` templates belong in Git.
- Run `make lint` and `make test`. Use Xcode/Simulator for visual inspection, runtime logs, crashes, profiling, signing, or capabilities.
