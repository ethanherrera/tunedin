# Development Database Deployment

## Purpose

Safely apply reviewed, forward-only Supabase database migrations from `main` to the shared hosted `tunedin-dev` project. The deployment is manually triggered and fully recorded in GitHub Actions.

This procedure applies database migrations only. It does **not** reset hosted data, load local seed data, push `supabase/config.toml`, deploy Edge Functions, or modify iOS configuration.

## Prerequisites and permissions

- The migration pull request is merged, and `main` contains its approved commit.
- The Backend pull-request check passed: disposable reset, generated Swift type check, and pgTAP authorization tests.
- GitHub CLI is authenticated with permission to dispatch workflows for `ethanherrera/tunedin`.
- The GitHub `Development` environment contains `SUPABASE_ACCESS_TOKEN` and `SUPABASE_DB_PASSWORD`; neither value is printed or stored in the repository.
- Supabase CLI access belongs to Ethan's `tunedIn` organization and the workflow targets only project ref `dmrlpyxhqhunfndihvai`.

## One-time environment setup

Create the `Development` environment and add its two deploy-only secrets through GitHub's secret-management UI or an approved terminal session. The values are:

- `SUPABASE_ACCESS_TOKEN` — a Supabase personal access token with access to `tunedin-dev`.
- `SUPABASE_DB_PASSWORD` — the password from the macOS Keychain item `tunedin/supabase/dev/database`.

Do not create repository-wide copies of these secrets. Do not put a Supabase service-role key in the workflow or iOS app.

## Commands

From the repository root, after updating local `main`:

```sh
git switch main
git pull --ff-only
make dev-status
make dev-plan
make dev-deploy
```

`make dev-deploy` dispatches the manually confirmed `Deploy Development Database` workflow from `main`. It does not wait for or poll the workflow.

## Expected result and verification

- The workflow recreates the schema in a disposable Docker Supabase stack, checks generated Swift DTOs, and runs pgTAP before contacting the hosted database.
- It prints the remote migration plan, applies only pending migrations, then prints local/remote migration parity.
- Its GitHub Actions summary records the exact deployed commit and states the limited scope.
- Run the impacted real iOS journey against Development. For Auth, use `make simulator-live`, request a fresh magic link, and complete the [Development smoke test](./supabase-development.md#simulator-magic-link-smoke-test). For a migration affecting concert data, create and reopen a concert; for a relationship change, exercise the relevant request or visibility rule with real Development accounts.

## Recovery and rollback

- Never rewrite a migration already applied to `tunedin-dev`, and never run a destructive remote reset.
- Correct a defect with a new forward-only migration. Use expand → migrate → contract for incompatible schema changes.
- For a suspected data-loss incident, stop further deployments, preserve the GitHub Actions run URL and Supabase logs, and follow the backup/recovery decision process in the Supabase Development runbook.

## Audit and cadence

- GitHub Actions retains the deployment run, commit SHA, migration output, and actor as the primary audit record.
- Use Supabase Logs Explorer and the relevant pull request for investigation context.
- Run this procedure after every merged database migration. Run `make dev-status` before a planned deployment or when diagnosing a Development schema mismatch.
