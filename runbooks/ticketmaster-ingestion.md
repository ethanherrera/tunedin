# Ticketmaster Catalog Ingestion

## Purpose

Populate tunedIn's own catalog with Ticketmaster music events for San Francisco, California from
the current local date through the next 14 local calendar days. This removes Ticketmaster latency
from future app search and ranking without changing the iOS app in this release.

The MVP is intentionally narrow:

- one city (`San Francisco`), state (`CA`), and country (`US`);
- music events only, 20 events per Ticketmaster page, at most 50 pages/1,000 events per run;
- normalized event, venue, artist, provider identity, source link, and ingestion metrics only;
- no raw Ticketmaster response archive and no Ticketmaster image ingestion;
- no cross-source artist or event matching;
- manual Development operation, followed by Staging only after Development verification;
- two installed Cron schedules that remain inactive.

## Prerequisites and permissions

- The forward-only ingestion migration is deployed to the target Supabase project.
- The `ticketmaster-ingestion` Edge Function is deployed from the same reviewed commit.
- The protected GitHub environment has `SUPABASE_ACCESS_TOKEN` and the environment-specific
  `TICKETMASTER_DISCOVERY_API_KEY`.
- The operator can manually dispatch workflows for `ethanherrera/tunedin`.
- Ordinary clients cannot execute ingestion RPCs. The protected workflow resolves the project's
  default secret API key in memory, masks it immediately, and never prints or stores it.

Do not add a secret or service-role key to the repository, iOS configuration, ordinary GitHub
variables, or workflow inputs. Do not enable either Cron schedule in Development or Staging during
MVP verification.

## Deploy to Development

From the feature branch:

```sh
git fetch origin
git rebase origin/main
make functions-test
make backend-verify
make dev-plan
make dev-functions-plan
make dev-deploy
make dev-functions-deploy
```

Wait for the database workflow to succeed before the Function workflow. Both workflows repeat
disposable verification before touching Development and record the exact commit in GitHub Actions.

For the first feature-branch deployment only, GitHub cannot register the new dedicated ingestion
workflow until it reaches the default branch. Bootstrap that first audited run through the existing
Function deployment workflow by selecting ingestion operation `run`. After merge, use only the
dedicated commands below for routine operations.

## Manual operation

Start one idempotent run for today's San Francisco 14-day window:

```sh
make dev-ticketmaster-ingestion-run
```

Read its status:

```sh
make dev-ticketmaster-ingestion-status
```

A Function invocation processes at most 10 pages and 60 seconds. If status remains `running` with
queued pages, resume it:

```sh
make dev-ticketmaster-ingestion-resume
```

Repeat status then resume only while the queue contains expected pages. Starting `run` again for
the same active local-date window returns the existing run instead of duplicating it.

## Expected result and verification

The GitHub Actions summary is the primary operator view. A healthy terminal status is `completed`
with:

- `coverage_starts_at` and `coverage_ends_at` at San Francisco local midnight, 14 calendar days
  apart even across daylight-saving transitions;
- `pages_completed` equal to `upstream_total_pages`;
- `raw_events_received = valid_events_received + rejected_events`;
- `unique_events_seen = events_inserted + events_updated + events_unchanged`;
- `queue_depth = 0` and no new dead-letter messages.

`completed_with_rejections` preserves existing listings because a partially decoded provider
response cannot prove that an unseen event disappeared. A clean completed run safely unlists only
unseen, active, listed Ticketmaster events inside the exact San Francisco/date window. It never
deletes catalog rows or user history.

The manual workflow also reports only fixed rejection-reason counters (`event_shape`,
`event_dates`, `venue`, `lineup`, and `source_url`). These counters contain no provider payload,
event identity, artist, venue, address, or URL data and are the approved way to diagnose decoder
coverage.

For direct database diagnosis, use Supabase SQL Editor with an authorized operator session:

```sql
select public.get_ticketmaster_ingestion_status(null);

select jobname, schedule, active
from cron.job
where jobname in (
  'ticketmaster-ingestion-daily',
  'ticketmaster-ingestion-worker'
)
order by jobname;

select * from pgmq.metrics('ticketmaster_ingestion');
select * from pgmq.metrics('ticketmaster_ingestion_dead_letter');
```

Both Cron rows must report `active = false` throughout Development and Staging MVP verification.

## Recovery and rollback

- Retryable provider or network failure: wait for the recorded queue visibility delay, then dispatch
  `make dev-ticketmaster-ingestion-resume`.
- Terminal page failure: stop. Preserve the workflow URL, run ID, safe error code, and Function log
  timestamps. Fix forward-only and start a new run; do not edit queue tables or reset Development.
- Unexpected rejection count: inspect the decoder against a redacted provider shape, deploy a fix,
  and start a new run. Existing listings were intentionally preserved.
- Incorrect normalized data: correct normalization and rerun. Stable Ticketmaster IDs update the same
  tunedIn records.
- Exposed key: revoke only the affected Ticketmaster or Supabase credential, replace it in the
  protected environment/project, and redeploy the Function.
- Bad migration: never rewrite an applied migration and never reset a hosted project. Add a new
  forward-only corrective migration.

There is no destructive rollback. Durable IDs protect diary references; listing changes are
reversible on the next clean observation.

## Cadence and scheduling

During Development and Staging, run on demand only. The migration installs:

- `ticketmaster-ingestion-daily` at `12:15 UTC` (after midnight in San Francisco year-round);
- `ticketmaster-ingestion-worker` every five minutes.

Both are inactive. Activating them requires a separately reviewed forward-only migration after
Development and Staging data quality, quota, dead-letter behavior, and operational ownership are
accepted. That future change must provision environment-specific Vault secrets named
`ticketmaster_ingestion_project_url` and `ticketmaster_ingestion_operator_key` for the project URL
and default `sb_secret` API key. It must not be performed as an untracked dashboard edit.

## Audit and cost signals

GitHub Actions retains the actor, commit, operation, and safe JSON result. Supabase Function logs,
Postgres run/page counters, `pgmq.metrics`, and Ticketmaster request-gate records provide diagnosis.
Never log provider payloads, API keys, bearer headers, or request URLs with query strings.

At the MVP scope, each run uses one Ticketmaster request per page and stores only normalized rows
plus small observation/run records. The existing 4,500-call rolling safety budget remains the hard
provider boundary. Observation rows are the main recurring storage growth and can receive a
separately reviewed retention policy after real Development measurements exist.
