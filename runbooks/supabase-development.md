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
- `make supabase-types` is run and its generated Swift DTO change is committed after every public-schema change.
- Before deploying a migration or RLS/RPC change, run `supabase test db` against the disposable local stack.

## Email delivery constraint

Development temporarily uses Supabase’s default magic-link template because the free provider cannot accept a custom OTP template. Before authentication acceptance or external testing, configure custom SMTP, restore code-only six-digit OTP delivery, verify the sending domain, and exercise the full iOS code-entry flow. Do not ship the magic-link fallback to beta.

## Recovery and audit

- Never rewrite an applied migration. Ship a corrective migration after review.
- For a serious data-loss incident, use Supabase backups only after stopping affected deployment work and documenting the recovery decision.
- Record deployed migration/function commit SHAs in the pull request and retain Supabase platform logs for investigation.

## Cadence

Run before every intentional Development configuration or backend deployment. Review access and backup posture monthly while the project is active.
