# Observability Guide

## Responsibility

This area owns tunedIn's explicit telemetry contract and vendor control-plane configuration. PostHog is active only for Staging today; Production remains a future separately approved target.

## Dependencies and boundaries

- The iOS app-owned telemetry wrapper is the only source of product events.
- Local and Development builds must never send PostHog traffic.
- This area may use Python's standard library and the PostHog Management API.
- Never add session replay, autocapture, automatic screen/tap/scroll tracking, user-created content, email addresses, usernames, filenames, raw URLs, or request/response bodies.
- Never target a PostHog project other than the exact project ID declared in the Staging manifest.

## Commands

- `make posthog-test` validates the contract and runs offline control-plane tests.
- `make posthog-plan` performs a read-only Staging drift check.
- `make posthog-verify` fails when Staging differs from the tracked contract.
- `POSTHOG_CONFIRM_APPLY=staging-507318 make posthog-apply` applies the tracked contract to Staging.

## Environment and secrets

- `POSTHOG_PERSONAL_API_KEY` is a protected secret in CI.
- Local commands may read the management key from macOS Keychain item `tunedin/posthog/management-api`.
- Project tokens are environment-scoped build secrets and must never be committed.

## Required verification

Run `make posthog-test`, `make workflow-lint`, and the Swift telemetry tests after changing this area or the iOS telemetry contract. Use `make posthog-plan` before applying hosted changes.
