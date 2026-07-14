# Staging Promotion

## Purpose

Promote one reviewed `main` commit to the isolated tunedIn Staging environment from the GitHub Actions UI. A successful promotion applies forward-only Supabase migrations, deploys tracked Edge Functions, and uploads the separately identified `tunedIn Staging` app to TestFlight.

Staging never receives copied Development users, database content, seeds, photos, or Storage objects.

## Prerequisites and permissions

- The selected commit is on `main`, and its pull-request iOS and Backend checks passed.
- Apple Developer Program membership is active.
- Apple Developer contains an explicit App ID for `com.ethanherrera.tunedin.staging`.
- App Store Connect contains a `tunedIn Staging` iOS app using that bundle identifier.
- The App Store Connect API key has an Admin role so it can manage the Staging Bundle ID capability,
  create distribution signing assets, and upload builds for that app.
- A fresh Supabase project named `tunedin-staging` exists and has not been initialized through dashboard-authored schema changes.
- A Google Cloud OAuth project contains an iOS client for `com.ethanherrera.tunedin.staging` and a Web client for Supabase token verification. The consent screen requests only `openid`, email, and profile.
- Supabase Auth is managed by the promotion workflow: Apple and Google are enabled, phone and manual identity linking remain disabled, and email sign-up is disabled after a successful TestFlight upload. No SMTP provider is required for Staging.
- The GitHub `Staging` environment exists and contains the values below.

Environment variables:

- `SUPABASE_PROJECT_REF`
- `POSTHOG_PROJECT_ID` (must be `507318`)
- `APPLE_DEVELOPMENT_TEAM`
- `APP_STORE_CONNECT_KEY_ID`
- `APP_STORE_CONNECT_ISSUER_ID`
- `GOOGLE_IOS_CLIENT_ID`
- `GOOGLE_SERVER_CLIENT_ID`
- `GOOGLE_REVERSED_CLIENT_ID`

Environment secrets:

- `SUPABASE_ACCESS_TOKEN`
- `SUPABASE_DB_PASSWORD`
- `SUPABASE_PUBLISHABLE_KEY`
- `POSTHOG_PROJECT_TOKEN`
- `POSTHOG_PERSONAL_API_KEY`
- `POSTHOG_CLI_API_KEY`
- `APP_STORE_CONNECT_PRIVATE_KEY`
- `GOOGLE_SERVER_CLIENT_SECRET`

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
- Authentication: native Sign in with Apple and Google only; Google OAuth client IDs are injected from the protected environment and no OAuth client secret is included in the app.
- Supabase Auth stores the Google Web and iOS client IDs as one comma-separated `external_google_client_id` value; the promotion verifier checks that canonical Management API representation.
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
5. Read the exact `com.ethanherrera.tunedin.staging` Bundle ID from App Store Connect and plan drift from
   the required primary-App-ID Sign in with Apple configuration.
6. Create an unsigned device archive and verify its expanded Supabase, PostHog, callback, environment,
   release values, and Sign in with Apple entitlement before changing hosted services. The runner applies
   an ad-hoc signature so the entitlement survives into the archive; App Store Connect replaces that
   signature during export, so the clean runner still needs no registered device or distribution certificate.
7. Enable or repair Sign in with Apple on that Bundle ID through the App Store Connect API and verify it is
   configured as a primary App ID (`APPLE_ID_AUTH_APP_CONSENT` / `PRIMARY_APP_CONSENT`).
8. Cloud-sign the archive, then inspect the exact IPA and embedded App Store distribution profile. Both must
   contain the default Sign in with Apple entitlement, the protected Apple team and Staging application ID,
   TestFlight beta reporting, no debugger access, and a valid non-device distribution profile. A bad IPA is
   rejected before upload or backend mutation.
9. Apply and verify the PostHog Staging contract and upload the archive's dSYMs without source files.
10. Verify current Supabase Auth drift, then enable the Apple and Google providers while leaving the existing email path available until upload succeeds.
11. Print the Staging migration dry run.
12. Apply pending migrations without seeds or reset.
13. Deploy tracked Edge Functions, if any, and verify migration parity.
14. Upload the already verified IPA to App Store Connect/TestFlight with Apple's `altool` and the protected API key.
15. Disable email and phone sign-up, keep manual identity linking disabled, and verify the complete Staging Auth contract.
16. Record the commit, observability target, authentication contract, and build number in the GitHub Actions summary.

## Expected result and verification

- GitHub records a successful deployment for the `Staging` environment and exact commit SHA.
- The workflow summary names `tunedIn Staging`, `com.ethanherrera.tunedin.staging`, and the uploaded build number.
- Supabase migration history matches the repository.
- App Store Connect finishes processing the uploaded build and makes it available to the intended internal TestFlight group.
- A tester can install Staging beside the Development/Production app, authenticate natively with Apple or Google only against `tunedin-staging`, and exercise the core journey without seeing another environment's data.

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

The first native-auth promotion showed that Supabase canonicalizes the Google Web and iOS client IDs
into one comma-separated `external_google_client_id` response value rather than returning the iOS ID
through `external_google_additional_client_ids`. The provider update succeeded, but the old verifier
rejected that valid response before migrations or TestFlight upload. The tracked payload, verifier, and
offline regression test now use the canonical representation, making the partially applied preparation
safe to retry.

Build `1007.1` then showed that disabling signing while creating the archive omitted the Sign in with
Apple entitlement from the processed TestFlight executable, even though the Xcode target and Apple App
ID were configured correctly. App Store Connect metadata and Supabase Auth logs isolated the failure:
Apple authorization stopped on-device and no Apple token reached Supabase. The workflow now ad-hoc
signs the archived app with the tracked entitlement before cloud export, and archive verification fails
before hosted mutation unless `com.apple.developer.applesignin` is present. A local export through
Apple's automatic distribution signing confirmed the final IPA retains the entitlement.

Build `1009.1` advanced to Apple's native account-creation sheet but ended with **Sign Up Not Completed**
before a credential reached the app or Supabase ([issue #28](https://github.com/ethanherrera/tunedin/issues/28)).
That proved the Swift token exchange was not the failing boundary, but the promotion still had two blind
spots: the workflow trusted a one-time dashboard statement about the App ID's primary-consent configuration,
and it did not inspect the distribution profile in the exact uploaded IPA. The workflow now reconciles and
verifies the primary App ID contract through Apple's API, exports the signed IPA before backend mutation,
and checks both its code-signing entitlement and embedded distribution profile before uploading that same file.

## Recovery and rollback

- If verification, archive, Apple capability reconciliation, or signed-IPA export fails, the hosted backend
  was not changed. The Apple App ID may have been safely advanced to the tracked primary-App-ID contract;
  correct the failure in a PR and dispatch again after merge.
- If provider preparation fails, email remains enabled and no app is uploaded. Correct the protected Google values or Apple/Supabase provider configuration, then rerun the promotion.
- If TestFlight upload succeeds but Auth finalization fails, Apple and Google remain enabled and email may remain temporarily enabled at the API boundary. The Staging app still shows only the two native providers; rerun the corrected promotion to finalize and verify the contract.
- If migration deployment fails, no app is uploaded. Never reset Staging or rewrite an applied migration; correct the problem with a new forward migration.
- If the backend succeeds but TestFlight upload fails, Staging remains forward-migrated. Keep migrations backward-compatible with the previously installed beta, correct signing/upload configuration, and rerun the promotion.
- Each dispatch receives a new monotonically increasing CI build number. Do not manually reuse or decrement it.
- If the wrong Supabase project ref is supplied, stop. The helper explicitly rejects the Development ref, but a new promotion must not proceed until the Staging environment value is corrected.

## Audit and cadence

- GitHub Actions and the `Staging` environment deployment history are the primary audit records.
- App Store Connect records uploaded builds and processing status.
- App Store Connect Bundle ID capability history and workflow logs record the verified primary-App-ID contract.
- Supabase migration history and platform logs record backend changes.
- Supabase Auth configuration history and the promotion summary record provider preparation/finalization without exposing OAuth secrets.
- PostHog project activity and error-tracking symbols record observability changes for project `507318`.
- Run a promotion only when a merged `main` commit is ready for integrated Staging and TestFlight testing; never on every merge.
