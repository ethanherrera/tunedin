# PostHog Staging Observability

## Purpose

Operate tunedIn's explicit, privacy-restricted PostHog observability for Staging. Local and Development exercise the same app-owned telemetry wrapper with an in-memory inspector and never send PostHog network traffic. Production remains disabled until a separate project and release decision are approved.

The tracked contract is `observability/posthog/staging.json`. It targets only `tunedIn Staging`, project ID `507318`, in the US region.

## Prerequisites and permissions

- A PostHog project token with ingestion access for the Staging iOS build.
- A narrowly scoped personal API key with project settings, dashboard, and insight access for drift/apply operations.
- A separate PostHog CLI key with `error_tracking:write` for dSYM upload.
- Local management API key stored in macOS Keychain item `tunedin/posthog/management-api`.
- GitHub `Staging` environment variable `POSTHOG_PROJECT_ID=507318`.
- GitHub `Staging` secrets `POSTHOG_PROJECT_TOKEN`, `POSTHOG_PERSONAL_API_KEY`, and `POSTHOG_CLI_API_KEY`.

Never commit these keys or place them in ordinary repository variables. Never grant the keys access to another environment unless the key is intentionally rotated and scoped for that environment.

## Contract and permitted data

- Explicit allow-listed journey outcomes, screen-load outcomes, operation outcomes, bounded durations, fixed error categories, release/build/Git SHA, broad OS major, broad device class, and opaque authenticated UUID identity.
- Automatic crash capture is enabled for Staging, with sanitized stack context and no exception breadcrumbs.
- User-created content, feedback text, names, usernames, email addresses, filenames, photo metadata, contact details, raw URLs, query strings, and request/response bodies are prohibited.
- Autocapture, lifecycle capture, automatic screen/tap/scroll capture, session replay, surveys, heatmaps, web vitals, console capture, and feature flags are disabled.
- The native feedback form stores voluntary text in private Supabase rows with its own retention; PostHog receives only category and success/failure outcome.

## Commands

Offline validation, also run by pull-request CI:

```sh
make posthog-test
```

Read-only hosted drift plan and strict verification:

```sh
make posthog-plan
make posthog-verify
```

Apply the tracked contract only after reviewing the plan:

```sh
POSTHOG_CONFIRM_APPLY=staging-507318 make posthog-apply
```

The apply command hard-codes project ID `507318`, refuses every other project, updates restrictive project settings, and idempotently manages the `tunedIn Staging · MVP health` dashboard and its four insights.

## Expected result and verification

- `make posthog-test` reports that the JSON contract matches the Swift event/property sanitizer and all offline tests pass.
- `make posthog-verify` reports that Staging matches the tracked contract.
- The Staging dashboard shows activation, collaboration outcomes, blocking failures, and core screen-load latency after beta events arrive.
- Local and Development builds show records only in the Debug telemetry inspector and create no PostHog events.
- Every promoted TestFlight archive uploads dSYMs before the app upload; source files are not included.

Review the PostHog project settings after SDK or plan changes. Hosted raw-event retention is not currently enforceable to 30 days through the available project API; use the shortest dashboard/billing retention control available and review it monthly. Session replay remains disabled regardless of its separate retention setting.

## Recovery and rollback

- If validation fails, update the manifest and Swift allow-list together; do not bypass the check.
- If drift verification fails, inspect `make posthog-plan`, correct the tracked contract or apply it explicitly, then verify again.
- If a management or CLI key is exposed, revoke it in PostHog, replace the GitHub Staging secret and local Keychain item, then rerun verification.
- If an unintended event reaches Staging, disable diagnostics in the app, remove the event at the PostHog data-management boundary, fix the sanitizer in a PR, and rotate a project token if exposure is suspected.
- Never use this procedure against Development or Production.

## Audit and cadence

- Git diffs to the manifest, telemetry wrapper, and promotion workflow are the configuration audit record.
- GitHub Actions logs and Staging environment deployments record validation, apply, and dSYM upload outcomes without credentials.
- PostHog activity history records hosted project/dashboard changes.
- Review the dashboard and privacy/retention settings manually once per month during private beta and after every PostHog SDK or plan change.
