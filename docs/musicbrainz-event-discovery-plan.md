# MusicBrainz Concert Discovery Plan

Status: approved for implementation
Decision date: 2026-07-25
Decision owner: Ethan

## Decision

tunedIn will add MusicBrainz Events as the first external concert-discovery
source. Discovery is write-through: eligible MusicBrainz results are normalized
and persisted in tunedIn's database during search, rather than being shown only
as live API results.

Each provider record is an individual concert in the MVP. tunedIn will not
attempt cross-source matching or merging. A MusicBrainz Event, a future
Ticketmaster Event, and a manually created tunedIn community concert may all
represent the same real-world performance and will remain distinct, visibly
attributed records until a later, explicit reconciliation product exists.

The sole external identity key is:

```text
(provider_key, external_event_id)
```

This key deduplicates only the same provider record. It never compares artist,
venue, date, title, coordinates, or start time across providers.

## Context

The existing community-event system already stores durable event occurrences,
supports discovery, attendance, posts, invitations, reports, and source-label
rendering. It currently assumes an occurrence is globally unique for a
headliner, venue, and date; that rule must become source-aware for this plan.

The existing authenticated `music-catalog` Edge Function already centralizes
MusicBrainz authentication, request validation, caching, quota enforcement,
request coalescing, and the application-wide rate gate. Event discovery extends
that gateway rather than adding a client-side MusicBrainz integration.

MusicBrainz Event data includes event IDs, a date, optional local time,
performer relationships, and place relationships. Places may include a city and
latitude/longitude, but MusicBrainz does not provide a canonical IANA time-zone
field. See [MusicBrainz Event search](https://musicbrainz.org/doc/MusicBrainz_API/Search),
[Event lookup examples](https://musicbrainz.org/doc/MusicBrainz_API/Examples),
and [Place fields](https://musicbrainz.org/doc/Place).

## MVP behavior

### Search

1. Search persisted tunedIn concerts first.
2. For a non-empty query, ask the MusicBrainz gateway for eligible Event
   candidates when the provider cache is stale (24 hours) or the user explicitly
   refreshes.
3. Validate and write-through upsert each eligible MusicBrainz result.
4. Return persisted tunedIn concert projections, with clear provider attribution.

The database is the durable concert catalog. MusicBrainz is a discovery and
refresh feed, not a runtime dependency for previously discovered concerts.

When MusicBrainz is unavailable, cached and stored concerts continue to appear.
The search experience reports that MusicBrainz results could not be refreshed
without hiding known local results.

### Eligibility

The first adapter accepts only MusicBrainz records that are:

- type `Concert`;
- single-day events with a complete begin date;
- related to at least one performer; and
- related to a venue/place.

Festivals, multi-day events, records without a performer, and records without a
venue are excluded from the first implementation. Tour and setlist import are
also out of scope.

### Source presentation

Every search row and detail screen displays its source, initially either:

- `tunedIn community`; or
- `MusicBrainz`.

An imported MusicBrainz concert includes an external `View on MusicBrainz` link.
The app will store a stable tunedIn UUID for every concert. Public tunedIn web
links and universal links are deferred, but that UUID is their future foundation.

## Source-specific persistence model

### Concert occurrence

`catalog_events` remains the durable tunedIn occurrence and social anchor. Add a
record origin that distinguishes community-created and provider-managed rows.

- Community rows retain a normal `created_by` owner and current edit behavior.
- Provider-managed rows have no importing-user owner and cannot be silently
  edited by ordinary users.
- Attendance, comments, posts, invitations, and reports attach to the tunedIn
  occurrence regardless of origin.

An importer must not become the owner of a provider record. This prevents a
single user from accidentally becoming the authority for a shared MusicBrainz
concert.

### Provider provenance

Add a private `catalog_event_sources` relation with at least:

```text
event_id
provider_key
external_event_id
external_url
source_updated_at
last_refreshed_at
source_status
```

Required invariants:

- unique `(provider_key, external_event_id)`;
- indexed `event_id` foreign key;
- no direct client read/write access;
- service-only ingestion/upsert path;
- no permanent storage of unbounded raw upstream responses.

The MVP write path creates one external source per imported concert. The schema
must allow several sources to reference one concert later, so a future reviewed
merge can reassign source rows instead of redesigning provenance.

Manual community concerts do not need a provider row; their source is a
synthetic `tunedIn community` attribution in the projection.

### Uniqueness and updates

Community-created concerts retain their current semantic duplicate policy inside
the tunedIn-community source. Provider-managed rows use a duplicate key derived
from `(provider_key, external_event_id)`, not their venue/date/headliner facts.

Refreshing an already stored MusicBrainz Event updates that same tunedIn concert
with changed provider facts such as title, place, local time, cancellation, or
source URL. It does not create a second MusicBrainz row.

## Time and calendar behavior

MusicBrainz supplies an event date and may supply a local wall-clock start time,
but it does not supply an authoritative IANA timezone. For this MVP, tunedIn
will preserve that source-local value rather than infer a timezone from
coordinates, city, or device settings.

```text
event_date          MusicBrainz calendar date, required
local_start_time    MusicBrainz wall-clock time, optional
starts_at           a storage instant used by existing calendar ordering only
time_zone_identifier tunedIn-created events only; never shown for MusicBrainz
```

MusicBrainz rows show the supplied time without a zone suffix (for example,
`8:00 PM`) alongside the venue and area, so the source location provides the
necessary context. The in-app calendar groups MusicBrainz rows by `event_date`,
not by a viewer-converted instant. There is no coordinate-to-timezone lookup,
and tunedIn must not claim a timezone it does not have.

tunedIn-created concerts retain the existing timezone-aware behavior: their
start instant is validated against the selected IANA venue timezone and is
displayed with that timezone. A future device-calendar export must use a timed
entry only when a source supplies or a verified owner confirms an IANA timezone;
until then MusicBrainz events are date/local-time information rather than an
exact instant.

## MusicBrainz gateway contract

Extend `music-catalog` with event-specific operations rather than treating an
Event as one of the existing reusable catalog entity kinds.

```text
search_events(query, cursor?)
resolve_event(musicbrainz_event_id)
```

The gateway must:

- require an authenticated, onboarded user;
- normalize and bound queries before building MusicBrainz search syntax;
- search Event, performer, venue, and area fields;
- use cached, validated, normalized candidates rather than return raw upstream
  payloads;
- preserve the existing shared MusicBrainz rate gate, cache, and request lease;
- resolve an Event authoritatively before it reaches the provider-import RPC;
- ingest provider facts only through a service-role-only database contract; and
- return a safe partial result when stored local concerts exist but MusicBrainz
  cannot be refreshed.

MusicBrainz calls remain serialized at the existing application-wide rate gate.
MusicBrainz publishes an average per-IP limit of one request per second and asks
for meaningful User-Agent contact information. See [MusicBrainz rate limiting](https://musicbrainz.org/doc/MusicBrainz_API/Rate_Limiting).

## iOS contract and experience

Replace the discovery-only `[CommunityEventSummary]` search contract with an
app-owned unified search item that can represent a stored concert or a provider
candidate while the provider write-through operation completes.

The UI should:

- show persisted community and MusicBrainz rows together in chronological,
  relevance-aware results;
- make provider attribution visible on every row;
- keep separate source records adjacent when their facts happen to match;
- preserve stored results if a provider refresh fails;
- show a non-blocking provider-refresh state; and
- open the persisted tunedIn concert detail after a provider candidate is
  resolved and written through.

The app must not contact MusicBrainz directly, construct MusicBrainz search
syntax, or decide source identity.

## Future sources and reconciliation

Ticketmaster, Songkick, and other sources will implement the same provider
search, resolution, and source-key contract. Their credentials, attribution,
retention, storage, and commercial terms must be reviewed individually before
they are enabled.

Future cross-source reconciliation is a separate product. It may use a review
queue and high-confidence signals such as provider IDs, venue location, date,
lineup, and time. It must never silently merge user social activity. Existing
event merge/tombstone/relink operations are a useful operational foundation, but
they are not invoked by this MVP.

Future verified venues, promoters, or subscription products are also sources,
not automatic global truth. Verified publishing and source claims require their
own permissions, audit trail, and moderation policy.

## Implementation order

1. Add the source-aware database model, central source projections, provenance
   constraints, source-local time, and service-only import RPC.
2. Extend the MusicBrainz Edge Function with Event search, lookup, validation,
   provider-source mapping, and write-through import.
3. Add app-owned discovery models and repository methods for combined persisted
   and provider-backed results.
4. Update the search and detail UI with source labels, source links, persisted
   result routing, and partial-refresh handling.
5. Update deterministic fixtures, local seeds, generated DTOs, database
   authorization tests, function tests, Swift tests, and iPhone 13 Simulator
   verification.

## Required verification

Implementation is not complete until it proves:

- the same MusicBrainz Event ID converges on one tunedIn concert under concurrent
  searches;
- different provider identities with matching facts remain separate;
- direct client writes cannot forge provider identity, provenance, or timezone;
- provider-managed rows are not editable as community-owned rows;
- source labels and external links are returned consistently across search,
  detail, plans, activity, invitations, and history projections;
- cached/stored results remain usable during MusicBrainz failure;
- coordinate-based timezone resolution yields the expected IANA timezone and
  daylight-saving-aware `starts_at`;
- unresolved timezones do not create incorrect timed calendar exports;
- the deterministic local seed contains community and MusicBrainz sourced
  concerts; and
- the affected search, import, calendar, and detail flow is visually inspected on
  the iPhone 13 Simulator.

## Explicit non-goals

- cross-source matching, fuzzy deduplication, or automated merging;
- bulk mirroring of whole provider catalogs;
- festivals, multi-day events, setlists, or tour ingestion;
- raw upstream payload archival without provider-specific approval;
- public tunedIn share URLs and universal links;
- ticketing, affiliate, or commerce flows; and
- verified organizer or paid source-publishing capabilities.

## Exit condition

The MVP is complete when an authenticated user can search MusicBrainz concerts,
receive persisted source-attributed tunedIn results for eligible past and upcoming
single-day concerts, reopen those results without a live MusicBrainz call, add
them correctly to plans/calendars when venue timezone resolution succeeds, and
see distinct source records without any cross-source merge.
