# tunedIn

tunedIn is an iOS-native private-beta concert journal for shared memories. The MVP is a SwiftUI app backed by Supabase.

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
make simulator-onboarding
make simulator-profile
make simulator-profile-error
make simulator-live
make backend-verify
make dev-status
make dev-plan
make build-staging
make staging-status SUPABASE_PROJECT_REF=YOUR_STAGING_PROJECT_REF
make staging-plan SUPABASE_PROJECT_REF=YOUR_STAGING_PROJECT_REF
```

For the temporary Development magic-link flow, copy the email button's link address and run
`make simulator-auth-link` while tunedIn is installed in a booted Simulator. The helper validates
the clipboard URL and never prints the one-time token.

The `simulator-onboarding`, `simulator-profile`, and `simulator-profile-error` commands launch
Development-only deterministic UI fixtures without sending email. They do not create a Supabase
session or access protected backend data. Use `make simulator-live` for real Supabase integration.

After a reviewed migration reaches `main`, use `make dev-deploy` to manually dispatch the protected
Development migration workflow. It reruns disposable schema/type/pgTAP verification before applying
forward-only migrations; see the [Development Database Deployment runbook](runbooks/development-database-deployment.md).

When a reviewed `main` commit is ready for integrated beta testing, dispatch **Promote Staging** from
the GitHub Actions UI. It archives the separate `tunedIn Staging` app, promotes the isolated Staging
backend, and uploads the archive to TestFlight; see the [Staging Promotion runbook](runbooks/staging-promotion.md).

Use focused `feature/`, `fix/`, or `chore/` branches and open pull requests into `main`. Squash merge approved changes and tag external releases as `vMAJOR.MINOR.PATCH`.
