# Development Database Deployment

## Purpose

Safely apply forward-only Supabase database migrations from an explicitly requested branch to the shared hosted `tunedin-dev` project. Development is the shared integration environment between disposable Local and protected Staging, so the requested branch may be unmerged and its data/contracts may be in progress. The deployment is manually triggered and fully recorded in GitHub Actions.

This procedure applies database migrations only. It does **not** reset hosted data, load local seed data, push `supabase/config.toml`, deploy Edge Functions, or modify iOS configuration.

## Prerequisites and permissions

- The requested branch contains the intended migration commit.
- The workflow will repeat disposable reset, generated Swift type check, and pgTAP authorization tests before it can mutate Development.
- GitHub CLI is authenticated with permission to dispatch workflows for `ethanherrera/tunedin`.
- The GitHub `Development` environment contains `SUPABASE_ACCESS_TOKEN` and `SUPABASE_DB_PASSWORD`; neither value is printed or stored in the repository.
- Supabase CLI access belongs to Ethan's `tunedIn` organization and the workflow targets only project ref `dmrlpyxhqhunfndihvai`.

## One-time environment setup

Create the `Development` environment and add its two deploy-only secrets through GitHub's secret-management UI or an approved terminal session. The values are:

- `SUPABASE_ACCESS_TOKEN` — a Supabase personal access token with access to `tunedin-dev`.
- `SUPABASE_DB_PASSWORD` — the password from the macOS Keychain item `tunedin/supabase/dev/database`.

Do not create repository-wide copies of these secrets. Do not put a Supabase service-role key in the workflow or iOS app.

## Commands

From the repository root on the branch to test:

```sh
git fetch origin
git rebase origin/main
make dev-status
make dev-plan
make dev-deploy
```

`make dev-deploy` dispatches the manually confirmed `Deploy Development Database` workflow from the current branch. It does not wait for or poll the workflow.

## Expected result and verification

- The workflow recreates the schema in a disposable Docker Supabase stack, checks the seed and generated Swift DTOs, runs pgTAP, and exercises the Storage API before contacting the hosted database. If the local stack fails during startup or reset, verification destroys only that disposable stack and retries once from a clean state.
- It prints the remote migration plan, applies only pending migrations, then prints local/remote migration parity.
- Its GitHub Actions summary records the exact deployed commit and states the limited scope.
- Run the impacted real iOS journey against Development. For Auth, use `make simulator-live`, request a fresh magic link, and complete the [Development smoke test](./supabase-development.md#simulator-magic-link-smoke-test). For a migration affecting concert data, create and reopen a concert; for a relationship change, exercise the relevant request or visibility rule with real Development accounts.

## Recovery and rollback

- Never rewrite a migration already applied to `tunedin-dev`, and never run a destructive remote reset.
- If disposable verification still fails after its one clean retry, inspect that workflow step before rerunning it. The retry never contacts or resets hosted Development.
- Correct a defect with a new forward-only migration. Use expand → migrate → contract for incompatible schema changes.
- For a suspected data-loss incident, stop further deployments, preserve the GitHub Actions run URL and Supabase logs, and follow the backup/recovery decision process in the Supabase Development runbook.

## Audit and cadence

- GitHub Actions retains the deployment run, commit SHA, migration output, and actor as the primary audit record.
- Use Supabase Logs Explorer and the relevant pull request for investigation context.
- Run this procedure after Local verification when a branch needs shared Development testing. Run `make dev-status` before a planned deployment or when diagnosing a Development schema mismatch.
