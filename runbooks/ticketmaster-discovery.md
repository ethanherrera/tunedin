# Ticketmaster Discovery Gateway

## Purpose

Operate the Ticketmaster-only Discover feed and its write-through-on-open import path. Global
concert search remains on `music-catalog`; `event-discovery` must never call MusicBrainz or match
Ticketmaster identities to community or MusicBrainz identities.

## Credentials and environments

Ticketmaster Discovery API v2 uses one API key sent as the `apikey` query parameter. It does not
use an OAuth client secret for these endpoints.

Create a separate Ticketmaster developer application for each hosted tunedIn environment:

- Development: `tunedindev-App`
- Staging: `tunedin-staging`
- `tunedIn Production` when Production is provisioned

Store each value as the `TICKETMASTER_DISCOVERY_API_KEY` secret in the matching protected GitHub
Environment. Never add it to an iOS xcconfig, repository variable, source file, log, or PR.
Development and Staging must not share a key.

Only the approved Public APIs Consumer Key is used. Do not store the Consumer Secret or the
Ticketmaster OAuth redirect URI; this Discovery integration does not use the OAuth Product.

The default hosted base URL is fixed in code to
`https://app.ticketmaster.com/discovery/v2/`. Only Local accepts
`TICKETMASTER_DISCOVERY_BASE_URL`, and it must point to a loopback fixture server. Local fixture
keys are non-secret placeholders.

## What is written

Discovery list responses remain ephemeral cache entries. Opening a card refetches authoritative
event detail and then atomically writes a normal `catalog_events` record with:

- event origin `ticketmaster`;
- provider identity `(ticketmaster, external event ID)`;
- Ticketmaster-origin artist, place, and area identities;
- source label and URL;
- Ticketmaster event artwork as a remote provider cover.

No fuzzy matching, shared UUID, MusicBrainz lookup, or cross-source merge runs. Reopening the same
Ticketmaster event ID updates the same Ticketmaster event. Same-looking community or MusicBrainz
records remain separate.

## Cache, quota, and ejection

- Discovery pages: 10-minute freshness.
- Event detail: 30-minute freshness.
- Every provider-cache row: hard deletion no later than 24 hours after write.
- Per-profile gateway limit: 120 requests per rolling hour.
- Provider gate: at most 2 upstream requests per second.
- Provider safety budget: 4,500 upstream requests per rolling 24 hours, leaving headroom below the
  usual 5,000-call key quota.

Expired provider cache is pruned lazily by service-only cache reads. Durable tunedIn event and
identity rows are not cache records and are retained so attendance, posts, and invitations remain
stable.

## Verification

From the repository root:

```sh
make functions-test
make backend-verify
make generate
make lint
make test
```

`supabase/tests/025_ticketmaster_discovery.sql` proves that ordinary clients cannot import or read
provider cache, provider IDs are idempotent, Ticketmaster and MusicBrainz artists stay independent,
and cache rows receive the 24-hour hard-ejection boundary.

Use the `community-events` Development scenario to review the Discover UI without a real key:

```sh
make simulator-community-events
```

After deploying Development, exercise the real hosted path with an existing Development session:

```sh
make simulator-live
```

Open Discover, confirm live Ticketmaster artwork and events appear, open one card, and confirm the
detail identifies Ticketmaster and offers `View on Ticketmaster`. Reopen that card and verify its
provider identity still maps to one `catalog_events` row. Review the `event-discovery` Function and
Data API logs if the feed or write-through fails.

## Development deployment

After the migrations and Function are reviewed and merged to `main`, add the Development
environment secret, run the normal Development database deployment, and then manually dispatch
`Deploy Development Functions` with its confirmation value. The allow-list deploys and verifies
only `music-catalog` and `event-discovery`.

Read-only checks:

```sh
make dev-status
make dev-plan
make dev-functions-status
make dev-functions-plan
```

## Staging promotion

Add a different `TICKETMASTER_DISCOVERY_API_KEY` to the protected Staging environment before
promotion. `Promote Staging` fails before backend mutation if it is missing, applies forward-only
migrations, deploys both allow-listed Functions, verifies both active versions, and then continues
the existing TestFlight promotion.

## Recovery

- Key exposed or suspected exposed: revoke it in Ticketmaster, create a replacement for only the
  affected environment, replace the protected GitHub Environment secret, and redeploy Functions.
- Provider quota exhausted: leave the gateway closed until the rolling provider window recovers;
  do not place the key in the app or bypass the database gate.
- Bad imported provider data: fix normalization and reopen the same provider event to update its
  existing Ticketmaster row. Do not merge it into a community or MusicBrainz row.
- Function deploy fails after migrations: rerun the protected Function workflow. Migrations and
  imports are forward-only and must not be reset.

GitHub Actions summaries and Supabase Function logs are the audit locations. Logs may contain
operation, outcome, duration, and safe error code only; they must never contain API keys, request
URLs with query strings, or provider payloads.
