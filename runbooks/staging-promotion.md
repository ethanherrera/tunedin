# Staging Promotion

## Purpose

Promote one reviewed `main` commit to the isolated tunedIn Staging environment from the GitHub Actions UI. A successful promotion applies forward-only Supabase migrations, deploys tracked Edge Functions, and uploads the separately identified `tunedIn Beta` app to TestFlight.

Staging never receives copied Development users, database content, seeds, photos, or Storage objects.

## Prerequisites and permissions

- The selected commit is on `main`, and its pull-request iOS and Backend checks passed.
- Apple Developer Program membership is active.
- Apple Developer contains an explicit App ID for `com.ethanherrera.tunedin.staging`.
- App Store Connect contains a `tunedIn Beta` iOS app using that bundle identifier.
- The App Store Connect API key can manage signing and upload builds for that app.
- A fresh Supabase project named `tunedin-staging` exists and has not been initialized through dashboard-authored schema changes.
- Supabase Auth permits the exact redirect `com.ethanherrera.tunedin.staging://auth-callback`.
- Custom SMTP is configured before inviting external testers; the built-in email allowance is not an external-beta authentication strategy.
- The GitHub `Staging` environment exists and contains the values below.

Environment variables:

- `SUPABASE_PROJECT_REF`
- `APPLE_DEVELOPMENT_TEAM`
- `APP_STORE_CONNECT_KEY_ID`
- `APP_STORE_CONNECT_ISSUER_ID`

Environment secrets:

- `SUPABASE_ACCESS_TOKEN`
- `SUPABASE_DB_PASSWORD`
- `SUPABASE_PUBLISHABLE_KEY`
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

- Display name: `tunedIn Beta`
- Bundle identifier: `com.ethanherrera.tunedin.staging`
- Callback: `com.ethanherrera.tunedin.staging://auth-callback`
- Build configuration: Release

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
3. Create an ephemeral ignored Staging configuration from protected values.
4. Archive and sign `tunedIn Beta` before changing the hosted backend.
5. Print the Staging migration dry run.
6. Apply pending migrations without seeds or reset.
7. Deploy tracked Edge Functions, if any.
8. Verify migration parity.
9. Upload the archived build to App Store Connect/TestFlight.
10. Record the commit and build number in the GitHub Actions summary.

## Expected result and verification

- GitHub records a successful deployment for the `Staging` environment and exact commit SHA.
- The workflow summary names `tunedIn Beta`, `com.ethanherrera.tunedin.staging`, and the uploaded build number.
- Supabase migration history matches the repository.
- App Store Connect finishes processing the uploaded build and makes it available to the intended internal TestFlight group.
- A tester can install Staging beside the Development/Production app, authenticate only against `tunedin-staging`, and exercise the core journey without seeing another environment's data.

After processing, exercise sign-in, profile, friends, concert creation/editing, collaboration, conversation, album upload/caption/deletion, archive sorting, activity, sign-out, and session restoration.

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
- Run a promotion only when a merged `main` commit is ready for integrated Staging and TestFlight testing; never on every merge.
