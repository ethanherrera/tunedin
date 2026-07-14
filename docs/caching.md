# Server Data Caching

## Decision

tunedIn uses an app-owned, two-tier cache for server-backed read models:

- decoded values in actor-isolated memory;
- versioned SwiftData snapshots for selected first-page and detail resources; and
- Supabase as the authoritative source of truth behind repository protocols.

The cache is presentation state, never an authorization boundary. Postgres RLS remains responsible for access control.

## Read behavior

Repository decorators own cache policy so views do not depend on SwiftData.

- Normal navigation is cache-first. A usable snapshot renders without a request.
- Pull-to-refresh and visible update affordances bypass the snapshot, await Supabase, and replace it.
- Later pagination and conflict-sensitive editing remain network-only.
- Realtime events invalidate affected keys and expose an update affordance rather than immediately refetching a page.
- Concurrent reads of one cache key share a single underlying request.
- Refresh failure preserves the last usable snapshot.

Cache keys include the app environment, authenticated viewer, resource, normalized variant, and payload version. The persisted key is hashed so query inputs and identifiers are not stored in key text.

## Freshness and offline bounds

| Resource | Soft-stale age | Maximum offline reuse |
| --- | ---: | ---: |
| Relationship-sensitive data | 5 minutes | 24 hours |
| Feed, archive, concert detail, comments, and albums | 15 minutes | 24 hours |
| Signed-in user's own profile and owned concerts | 1 hour | 7 days |

Soft-stale data may continue rendering while the user decides when to refresh. Once the maximum bound is exceeded, the visible resource requires a successful server read.

Only first pages are persisted initially. Search prefixes remain in a bounded memory cache, signed URLs remain memory-only, and downloaded image bytes use a bounded HTTP response cache.

## Mutations and invalidation

Mutations stay network-first; there is no offline write queue. Successful mutations patch or invalidate all dependent keys. Removing a relationship, blocking a profile, losing access, signing out, changing accounts, or changing environments purges permission-sensitive data.

The cache never stores authentication material, OTPs, signed media URLs, upload bytes, feedback text, or unfinished form drafts. Corrupt snapshots are deleted; unknown-version snapshots are ignored as misses and removed by cache maintenance.

## Rollout and exit condition

GitHub issue #30 owns the initiative, with child issues for the foundation/Profile/Feed, social data, concert data, and media/privacy hardening. This decision is complete when those child issues meet their acceptance criteria, tests prove freshness and isolation behavior, and every affected flow has been exercised in the iPhone 13 Simulator.
