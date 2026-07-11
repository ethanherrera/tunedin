# Supabase Development

## Purpose

Operate the shared hosted `tunedin-dev` project used by local iOS Development builds. Its project ref is `dmrlpyxhqhunfndihvai` in `us-west-1`.

## Prerequisites and permissions

- A Supabase CLI session authenticated to Ethan’s `tunedIn` organization.
- The database password in the macOS Keychain item `tunedin/supabase/dev/database`; never print or commit it.
- A reviewed feature branch for configuration, migration, RLS, RPC, or Edge Function changes.

## Commands

```sh
cd ~/tunedin
supabase link --project-ref dmrlpyxhqhunfndihvai \
  --password "$(security find-generic-password -a "$USER" -s 'tunedin/supabase/dev/database' -w)"
supabase config push --project-ref dmrlpyxhqhunfndihvai
supabase db push
```

## Expected result and verification

- The CLI reports the linked `tunedin-dev` project and configuration update.
- `supabase projects list` lists `tunedin-dev` as `ACTIVE_HEALTHY` in `us-west-1`.
- `make supabase-types` is run against the migrated disposable local schema and its generated Swift DTO change is committed after every public-schema change. Set `SUPABASE_PROJECT_REF` only when an explicit hosted-schema comparison is needed.
- Before deploying a migration or RLS/RPC change, run `supabase test db` against the disposable local stack.

## Email delivery constraint

Development temporarily uses Supabase’s default magic-link template because the free provider cannot accept a custom OTP template. Before authentication acceptance or external testing, configure custom SMTP, restore code-only six-digit OTP delivery, verify the sending domain, and exercise the full iOS code-entry flow. Do not ship the magic-link fallback to beta.

### Simulator magic-link smoke test

1. Run tunedIn with the `tunedIn-Development` scheme in a booted iOS Simulator.
2. Request a sign-in email from the app.
3. In the email client, copy the **Sign in** button's link address without opening it on the Mac.
4. From the repository root, run `make simulator-auth-link`.
5. When iOS asks whether to open the link in tunedIn, choose **Open**.

The helper accepts only a hosted or local Supabase Auth verification URL, does not print the token, and asks the booted Simulator to open it. Supabase should verify the one-time link, redirect to `com.ethanherrera.tunedin://auth-callback`, and reopen tunedIn with an authenticated session. If it fails, request a fresh link, confirm tunedIn is installed, and confirm the hosted Auth URL allow-list contains the exact callback URL. The Supabase Auth log and local Xcode console are the audit locations for failures.

### Development UI scenarios

After installing the Development build in a booted Simulator, use these commands to inspect app-owned routing and UI without consuming an Auth email:

```sh
make simulator-signed-out
make simulator-onboarding
make simulator-profile
make simulator-profile-error
make simulator-live
```

The non-live scenarios inject deterministic in-memory authentication and profile repositories. They cannot access Supabase, do not prove authentication or authorization behavior, and must never substitute for the live magic-link smoke test or pgTAP RLS/RPC tests. `make simulator-live` removes the scenario argument and restores the normal Supabase-backed Development container. Reinstall the app if a scenario command reports that tunedIn is unavailable.

## Recovery and audit

- Never rewrite an applied migration. Ship a corrective migration after review.
- For a serious data-loss incident, use Supabase backups only after stopping affected deployment work and documenting the recovery decision.
- Record deployed migration/function commit SHAs in the pull request and retain Supabase platform logs for investigation.

## Cadence

Run before every intentional Development configuration or backend deployment. Review access and backup posture monthly while the project is active.
