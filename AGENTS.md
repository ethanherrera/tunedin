# tunedIn Repository Guide

## Responsibility

This repository contains the native tunedIn MVP: a SwiftUI iOS client and its Supabase backend. For structured artist, place, area, song, tour, and concert-entry behavior, use the checked-in `docs/musicbrainz-catalog-implementation-plan.md`.

## Boundaries

- Keep the iOS client in `ios/`, backend schema/RLS/RPC/Edge Function work in `supabase/`, CI in `.github/`, and terminal helpers in `scripts/`.
- Use Swift Package Manager only. The app may depend on Supabase Swift and Apple frameworks; add other runtime dependencies only with an explicit product need.
- Make schema evolution forward-only. All shared-environment changes are timestamped migrations; never edit an applied migration or use dashboard-only schema changes.
- Authorization belongs in Postgres RLS and narrowly scoped hardened RPCs, not client checks.
- Development launch scenarios may bypass email only by injecting deterministic in-memory client repositories. They must not create privileged Supabase sessions, weaken RLS, or be treated as backend/auth verification; use the live Development flow for integration testing.

## Git workflow

- Before starting implementation work and again immediately before creating or updating a pull request, fetch `origin` and rebase the focused feature branch onto the latest `origin/main`.
- Resolve every rebase or merge conflict locally before continuing, rerun the required verification after conflict resolution, and never create or update a pull request while conflicts remain.

## iPhone navigation

- For in-app sub-screens, use the contextual bottom liquid-glass control bar: the leftmost control returns to the previous screen and the remaining controls switch the relevant views or actions. Do not place back, close, or other in-app navigation controls in the top corners.
- Prioritize adaptive system Liquid Glass for screen and menu traversal whenever the platform supports it, with a material fallback for older supported iOS versions. Back controls and contextual menu actions should be glass controls too; keep primary page switching in a cohesive central glass group and use a three-dot glass action for edit menus.
- Animate contextual liquid-glass changes as one cohesive transition; selected segments should glide between positions instead of snapping or leaving an underlying control bar visible.

## Development database deployment

- The shared `tunedin-dev` project advances only through the manually dispatched `Deploy Development Database` workflow from an already reviewed `main` commit. Pull-request checks and merge-triggered workflows must remain non-mutating.
- Treat `make backend-verify` as the required disposable-schema proof before a hosted migration. `make dev-status` and `make dev-plan` are read-only; `make dev-deploy` only queues the protected workflow.
- The deployment path applies forward-only database migrations only. Never reset hosted Development, include local seed data, or push Supabase configuration/Edge Functions through this path.
- Treat `supabase/seeds/development.sql` as the deterministic, usable local journey catalog. When a local-testable user journey, relationship state, collaboration state, or concert lifecycle changes, update the seed and `make local-seed-verify` in the same change so a reset still covers the real valid state rather than a frozen UI fixture.

## Staging promotion

- Staging is a separate install named `tunedIn Staging` with bundle identifier `com.ethanherrera.tunedin.staging` and a separate hosted Supabase project. Never reuse Development or Production identity, sessions, users, data, or Storage objects.
- Promote Staging only through the manually dispatched `Promote Staging` workflow from `main`. The workflow must verify the selected commit, archive before backend mutation, apply forward-only migrations/functions, then upload that archive to TestFlight.
- Keep Staging credentials in the protected GitHub `Staging` environment. A workflow without the required environment values must fail before archive or deployment.
- Treat a partially completed promotion as retryable and forward-only: never reset Staging or rewrite an applied migration. Follow `runbooks/staging-promotion.md`.

## Configuration and secrets

- Copy `ios/Config/*.xcconfig.example` to ignored `.xcconfig` files for local configuration.
- Do not commit Supabase access tokens, service-role keys, database passwords, email/Apple credentials, PostHog credentials, or telemetry payload content.
- Development uses the hosted Supabase Development project. The `tunedIn-Local` scheme instead uses the disposable Docker Supabase stack for full local iOS integration; configure it only through `make configure-local-supabase`. Never point the Local scheme at a hosted project or deploy its data/migrations.

## Required verification

- Run `make generate`, `make lint`, and `make test` for iOS changes.
- After changing user interface behavior or layout, exercise the affected flow in the iPhone 13 Simulator with Computer Use and visually inspect the resulting state before handoff. A successful build alone is not sufficient UI verification.
- For an end-to-end local iOS path, run `make local-db-reset` once for the documented real local accounts and journeys, then use `make simulator-local` for subsequent launches. The simulator command starts/reuses Local Supabase and configures the ignored Local xcconfig without resetting data; the Local-only seeded-account picker creates normal Supabase sessions, while local Inbucket remains for email-auth testing.
- Run `supabase test db` for migrations, RLS, or RPC changes; add behavior-focused pgTAP authorization tests.
- Keep generated Swift database DTOs committed and current after a schema change.
- Work from focused branches and leave `main` to pull-request merges.
- Never merge a pull request or enable or schedule auto-merge without Ethan's explicit permission for that specific pull request. After required checks pass, stop and ask for permission.
