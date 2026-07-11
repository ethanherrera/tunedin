# tunedIn Repository Guide

## Responsibility

This repository contains the native tunedIn MVP: a SwiftUI iOS client and its Supabase backend. The source of product truth is the reference plan at `/Users/ethan/Work/tunedIn/tunedIn MVP Design.md`.

## Boundaries

- Keep the iOS client in `ios/`, backend schema/RLS/RPC/Edge Function work in `supabase/`, CI in `.github/`, and terminal helpers in `scripts/`.
- Use Swift Package Manager only. The app may depend on Supabase Swift and Apple frameworks; add other runtime dependencies only with an explicit product need.
- Make schema evolution forward-only. All shared-environment changes are timestamped migrations; never edit an applied migration or use dashboard-only schema changes.
- Authorization belongs in Postgres RLS and narrowly scoped hardened RPCs, not client checks.

## Configuration and secrets

- Copy `ios/Config/*.xcconfig.example` to ignored `.xcconfig` files for local configuration.
- Do not commit Supabase access tokens, service-role keys, database passwords, email/Apple credentials, PostHog credentials, or telemetry payload content.
- Development uses the hosted Supabase Development project; local Docker Supabase is only for disposable backend tests.

## Required verification

- Run `make generate`, `make lint`, and `make test` for iOS changes.
- Run `supabase test db` for migrations, RLS, or RPC changes; add behavior-focused pgTAP authorization tests.
- Keep generated Swift database DTOs committed and current after a schema change.
- Work from focused branches and leave `main` to pull-request merges.
