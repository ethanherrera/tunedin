# tunedIn

tunedIn is an iOS-native private-beta concert journal for shared memories. The MVP is a SwiftUI app backed by Supabase. Its product plan remains reference-only at `/Users/ethan/Work/tunedIn/tunedIn MVP Design.md`.

## Repository layout

- `ios/` — SwiftUI app, Xcode project definition, and unit tests.
- `supabase/` — versioned migrations, RLS/RPC tests, deterministic development seed data, and Edge Functions.
- `scripts/` — safe terminal helpers used by `make` and CI.
- `.github/` — pull-request checks and dependency updates.

## Local setup

Xcode 26.6 is the local baseline. Xcode is required for native builds, Simulator work, debugging, signing, and capability configuration; the rest of the setup is terminal-first.

```sh
brew bundle --file=Brewfile
make configure
make setup
make generate
make build
```

`make configure` creates ignored `.xcconfig` files from their tracked templates. Add the Development Supabase URL and publishable key only after the hosted project is provisioned. Never place service-role keys, database passwords, or other privileged values in the app or Git.

## Daily commands

```sh
make build
make test
make lint
make format
make simulator-auth-link
make supabase-types
make backend-test
```

For the temporary Development magic-link flow, copy the email button's link address and run
`make simulator-auth-link` while tunedIn is installed in a booted Simulator. The helper validates
the clipboard URL and never prints the one-time token.

Use focused `feature/`, `fix/`, or `chore/` branches and open pull requests into `main`. Squash merge approved changes and tag external releases as `vMAJOR.MINOR.PATCH`.
