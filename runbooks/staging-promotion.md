# Staging Promotion

## Purpose

Promote one reviewed `main` commit to the isolated tunedIn Staging environment from the GitHub Actions UI. A successful promotion applies forward-only Supabase migrations, deploys tracked Edge Functions, and uploads the separately identified `tunedIn Staging` app to TestFlight.

Staging never receives copied Development users, database content, seeds, photos, or Storage objects.

## Prerequisites and permissions

- The selected commit is on `main`, and its pull-request iOS and Backend checks passed.
- Apple Developer Program membership is active.
- Apple Developer contains an explicit App ID for `com.ethanherrera.tunedin.staging`.
- App Store Connect contains a `tunedIn Staging` iOS app using that bundle identifier.
- The App Store Connect API key can manage signing and upload builds for that app.
- A fresh Supabase project named `tunedin-staging` exists and has not been initialized through dashboard-authored schema changes.
- Supabase Auth permits the exact redirect `com.ethanherrera.tunedin.staging://auth-callback`.
- Custom SMTP is configured before inviting external testers; the built-in email allowance is not an external-beta authentication strategy.
- The GitHub `Staging` environment exists and contains the values below.

Environment variables:

- `SUPABASE_PROJECT_REF`
- `POSTHOG_PROJECT_ID` (must be `507318`)
- `APPLE_DEVELOPMENT_TEAM`
- `APP_STORE_CONNECT_KEY_ID`
- `APP_STORE_CONNECT_ISSUER_ID`

Environment secrets:

- `SUPABASE_ACCESS_TOKEN`
- `SUPABASE_DB_PASSWORD`
- `SUPABASE_PUBLISHABLE_KEY`
- `POSTHOG_PROJECT_TOKEN`
- `POSTHOG_PERSONAL_API_KEY`
- `POSTHOG_CLI_API_KEY`
- `APP_STORE_CONNECT_PRIVATE_KEY`

Never add a service-role key, database password, App Store Connect key, signing certificate, or provisioning profile to source control or ordinary repository variables.

## One-time local setup

Store the Staging database password in macOS Keychain for read-only status and plan commands:

```sh
security add-generic-password \
  -a "$USER" \
  -s tunedin/supabase/staging/database \
  -w
```

Do not place the password directly in shell history. Supply the non-secret project ref only for the command being run:

```sh
SUPABASE_PROJECT_REF=YOUR_STAGING_PROJECT_REF make staging-status
SUPABASE_PROJECT_REF=YOUR_STAGING_PROJECT_REF make staging-plan
```

The tracked Staging configuration template uses:

- Display name: `tunedIn Staging`
- Bundle identifier: `com.ethanherrera.tunedin.staging`
- Callback: `com.ethanherrera.tunedin.staging://auth-callback`
- Build configuration: Release
- Export compliance: the app declares that it does not use non-exempt encryption; this covers the confirmed system HTTPS-only implementation.

App Store Connect contains an internal TestFlight group named `Staging` with automatic distribution
and TestFlight feedback enabled. Keep at least one eligible App Store Connect user in that group. New
valid builds are available to the group automatically; do not also assign individual builds to an
all-builds internal group.

For a manual local archive, add `DEVELOPMENT_TEAM = YOUR_TEAM_ID` to the ignored
`ios/Config/Staging.xcconfig`, then run `make archive-staging`. The protected CI workflow supplies
the team from the GitHub Staging environment instead.

## Promotion through GitHub UI

1. Open the repository's **Actions** tab.
2. Select **Promote Staging**.
3. Choose **Run workflow**.
4. Select the `main` branch.
5. Enter `promote-staging` in the confirmation field.
6. Choose **Run workflow** and follow the workflow graph.
7. If the `Staging` environment requires review, inspect the commit and approve the waiting deployment.

The equivalent terminal dispatch is:

```sh
make staging-promote
```

The workflow performs these operations in order:

1. Rebuild and verify the disposable backend.
2. Regenerate, lint, test, and build the iOS project.
3. Validate the offline PostHog contract and print a read-only Staging drift plan.
4. Create an ephemeral ignored Staging configuration from protected values.
5. Create an unsigned device archive and verify its expanded Supabase, PostHog, callback, environment,
   and release values before changing hosted services. App Store Connect cloud-signs this same archive
   during export, so the clean runner does not need a registered device or a local distribution certificate.
6. Apply and verify the PostHog Staging contract and upload the archive's dSYMs without source files.
7. Print the Staging migration dry run.
8. Apply pending migrations without seeds or reset.
9. Deploy tracked Edge Functions, if any, and verify migration parity.
10. Cloud-sign and upload the archived build to App Store Connect/TestFlight.
11. Record the commit, observability target, and build number in the GitHub Actions summary.

## Expected result and verification

- GitHub records a successful deployment for the `Staging` environment and exact commit SHA.
- The workflow summary names `tunedIn Staging`, `com.ethanherrera.tunedin.staging`, and the uploaded build number.
- Supabase migration history matches the repository.
- App Store Connect finishes processing the uploaded build and makes it available to the intended internal TestFlight group.
- A tester can install Staging beside the Development/Production app, authenticate only against `tunedin-staging`, and exercise the core journey without seeing another environment's data.

After processing, exercise sign-in, profile, friends, concert creation/editing, collaboration, conversation, album upload/caption/deletion, archive sorting, activity, sign-out, and session restoration.

## First verified promotion

The first complete promotion succeeded on July 13, 2026:

- Source commit: `8fcdac3de59f8453e1db7a8d8fc30fca18ccf4d8`
- GitHub Actions run: [29247271831](https://github.com/ethanherrera/tunedin/actions/runs/29247271831)
- Supabase: migration parity and tracked Edge Function deployment succeeded for `tunedin-staging`.
- PostHog: project `507318` matched the tracked contract, and archive dSYMs uploaded without source files.
- TestFlight: version `0.1.0`, build `1004.1` processed as `VALID` and entered `IN_BETA_TESTING`.
- Internal distribution: the `Staging` group has automatic all-build access and contains the Account Holder tester.

The first attempts also verified the recovery boundaries: configuration and signing failures before
archive left hosted services unchanged, while an App Store metadata rejection after backend deployment
left the forward-only backend safe to retry. CI now validates the required `APPL` package type,
`AppIcon` declaration, export-compliance flag, and opaque 1024-pixel icon before promotion.

Build `1004.1` exposed a launch-time configuration failure after installation: the workflow's inline
Bash `%c` expression wrote `3(TUNEDIN_URL_SLASH)` instead of the literal xcconfig `$()` expansion,
so the packaged Supabase and PostHog URLs were invalid. Staging configuration generation now has an
offline regression test, and every promotion validates the expanded values in the archived app before
PostHog, Supabase, or TestFlight can be changed.

## Recovery and rollback

- If verification or archive fails, the hosted backend was not changed. Correct the failure in a PR and dispatch again after merge.
- If migration deployment fails, no app is uploaded. Never reset Staging or rewrite an applied migration; correct the problem with a new forward migration.
- If the backend succeeds but TestFlight upload fails, Staging remains forward-migrated. Keep migrations backward-compatible with the previously installed beta, correct signing/upload configuration, and rerun the promotion.
- Each dispatch receives a new monotonically increasing CI build number. Do not manually reuse or decrement it.
- If the wrong Supabase project ref is supplied, stop. The helper explicitly rejects the Development ref, but a new promotion must not proceed until the Staging environment value is corrected.

## Audit and cadence

- GitHub Actions and the `Staging` environment deployment history are the primary audit records.
- App Store Connect records uploaded builds and processing status.
- Supabase migration history and platform logs record backend changes.
- PostHog project activity and error-tracking symbols record observability changes for project `507318`.
- Run a promotion only when a merged `main` commit is ready for integrated Staging and TestFlight testing; never on every merge.
