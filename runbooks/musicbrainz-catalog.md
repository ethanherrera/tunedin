# MusicBrainz Catalog Gateway

## Purpose

Operate tunedIn's authenticated `music-catalog` Supabase Edge Function. The gateway
searches reusable tunedIn catalog records first, including write-through MusicBrainz
entities and creator-owned custom fallbacks, uses committed fixtures for
routine Local/CI verification, and is the only application component permitted to
call the public MusicBrainz API.

The procedure keeps database migration deployment separate from Function deployment.
It never resets or seeds a hosted project, and the Local fixture path never contacts
MusicBrainz or a hosted Supabase project.

## Prerequisites and permissions

- Deno 2, Docker Desktop, Supabase CLI 2.109.1, `curl`, Git, and GitHub CLI are
  installed. Run `make setup` for the complete repository toolchain.
- For Local integration, the disposable Supabase stack contains the current
  migrations and deterministic development seed. `make local-db-reset` recreates it.
- Development changes are merged to reviewed `main`, the Backend and iOS checks are
  green, and the additive database migration has already been applied through
  `Deploy Development Database`.
- The protected GitHub `Development` environment contains
  `SUPABASE_ACCESS_TOKEN` and a variable named `MUSICBRAINZ_USER_AGENT`. The latter
  uses a contactable form such as `tunedIn/<version> (mailto:<contact>)` or
  `tunedIn/<version> (https://<contact-page>)`.
- The protected `Staging` environment has the same `MUSICBRAINZ_USER_AGENT` variable
  in addition to the values required by the Staging promotion runbook.
- Confirm tunedIn's non-commercial eligibility or arrange the appropriate MetaBrainz
  commercial account before any revenue-bearing Production release.

Do not put the User-Agent contact, Supabase tokens, service-role key, database
password, or Function environment files in Git. Supabase injects its service-role key
at runtime; the workflows never copy that key into repository or app configuration.

## Local deterministic operation

Rebuild the disposable schema and seed after a migration, then start and verify the
gateway:

```sh
make musicbrainz-upgrade-test
make local-db-reset
make functions-test
make local-catalog-verify
make local-catalog-status
```

`make musicbrainz-upgrade-test` first resets the disposable Local database through
the last pre-catalog migration, loads two valid legacy concerts, applies the catalog
migration, and verifies that snapshot text and row identity survive while reusable
legacy catalog links are populated. It also proves the pre-existing deferred lineup
checks are executed before the migration changes table constraints. The command is
part of `make backend-verify`; run `make local-db-reset` afterward to restore the
normal development journey seed.

`make local-catalog-verify` starts/reuses two tracked processes:

- a Deno MusicBrainz stub on host port 18081 using committed JSON fixtures; and
- `supabase functions serve` with `TUNEDIN_ENVIRONMENT=Local`, where the Edge Runtime
  reaches the stub only through `host.docker.internal`.

It creates a normal password session for the synthetic Local Listener, exercises
authenticated search and resolution for artist, place/area, song/Work, and tour, and
proves the resolved place returns a tunedIn area UUID. It does not print the local
token or publishable key. Ignored lifecycle state and logs live under
`supabase/.temp/music-catalog/`.

Launch the Local iOS app with the same real database/function boundary:

```sh
make simulator-catalog
```

The target prints the fixture-only queries for empty, 429, 503, malformed, and timeout
states. Normal artist, place, song, and tour searches use the committed ambiguous
fixtures. Stop only the tracked Function/stub processes when finished:

```sh
make local-catalog-stop
```

This does not stop or reset Local Supabase.

## Optional live MusicBrainz schema smoke

Routine tests and CI must not call the live service. When an upstream contract change
is suspected, explicitly provide the approved contactable User-Agent and run:

```sh
MUSICBRAINZ_USER_AGENT='tunedIn/manual-smoke (mailto:APPROVED_CONTACT)' \
  make musicbrainz-smoke
```

The command performs one search for each entity kind and waits 1.1 seconds between
requests. It is intentionally absent from `make check`, pull-request CI, deployment
preflight, and local reset. Do not paste its URLs or response data into tickets or
logs; only the fixed per-kind success lines are expected.

## Development deployment

Inspect the read-only state and plan:

```sh
make dev-functions-status
make dev-functions-plan
```

After the reviewed migration is deployed from `main`, dispatch the separate protected
Function workflow:

```sh
make dev-functions-deploy
```

`Deploy Development Functions` performs, in order:

1. Deno format, lint, type, decoder, transport, cache, coalescing, and handler tests;
2. a disposable database reset, generated DTO check, pgTAP authorization tests, and
   Storage integration test;
3. the authenticated Local fixture gateway verification;
4. validation and reconciliation of the protected Function runtime values;
5. deployment of only the `music-catalog` allow-list entry; and
6. strict verification of its active deployed version plus the exact commit in the
   Actions summary.

It does not invoke `supabase db push`, reset or seed Development, deploy
`supabase/config.toml`, or deploy unrelated Functions. The existing Development
database workflow remains migrations-only.

## Expected result and verification

- `make functions-test` passes without network access and covers authentication,
  profile completion, request bounds, Lucene escaping, five entity decoders,
  Recording/Work and credit identity, place/area derivation, redirects, 429/503,
  malformed/oversized/timeout responses, safe logs, hashed cache keys, quota use,
  combined pagination, single-flight behavior, and hosted/Local configuration gates.
- `make local-catalog-verify` reports only
  `Local music catalog fixture gateway verified.` and resolves stable tunedIn UUIDs.
- Development Actions lists `music-catalog` with its deployed version and records the
  source SHA. The database migration history is unchanged by that workflow.
- A normal Development account can search and resolve an artist and place, observe the
  place-derived city, resolve a song and tour, create a reusable custom fallback, save
  a concert, reopen it, and edit it without submitting authoritative display strings.
- Supabase Function logs contain only fixed operation/outcome/error category and
  duration if operational logging is enabled. They must not contain raw search text,
  names, addresses, MBIDs, user IDs, authorization, response bodies, URLs with query
  strings, or setlist content.

## Recovery and rollback

- Local: run `make local-catalog-stop`, then `make local-db-reset` and
  `make local-catalog-verify`. Only ignored local processes/data are replaced.
- Verification failure before deployment: no hosted Function or database state was
  changed. Correct the branch in a PR and redispatch after merge.
- Existing-data migration failure: confirm the failed transaction left the migration
  absent from every shared environment before amending it. If any shared environment
  recorded it, preserve the applied file and add a new forward-only corrective
  migration instead. Reproduce the path with `make musicbrainz-upgrade-test`.
- Runtime configuration failure: correct the protected environment variable; never
  add a fallback contact or non-official hosted base URL in source.
- Function defect after deployment: redeploy the last known-good reviewed `main`
  version of `music-catalog`, or disable the Function while the client presents its
  retryable unavailable state. Keep the additive catalog schema and compatibility RPCs
  in place.
- Database/function partial rollout: database migrations remain forward-only. Never
  reset a hosted database or rewrite an applied migration. Apply a corrective migration
  first when the Function contract requires it, then redeploy the Function.
- Upstream pressure: the database lease, single-flight claim, per-user quota, and global
  request-slot allocator fail closed. Do not bypass them with an instance-local or
  direct-client request path.

## Audit and cadence

- Pull-request checks and committed fixtures are the deterministic contract record.
- GitHub Actions and the protected environment deployment history record actor, commit,
  Function version, and runtime reconciliation for Development/Staging.
- Supabase Function logs and database cache/gate rows are the operational audit source;
  inspect only sanitized fixed fields and retain raw diagnostics for at most 30 days.
- Run Local verification after Function/RPC/fixture changes. Deploy Development only
  after the corresponding reviewed migration. Run the opt-in live smoke only when
  checking a suspected MusicBrainz schema change. Staging Function deployment remains
  part of a manually approved full Staging promotion.
