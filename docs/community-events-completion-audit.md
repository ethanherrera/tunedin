# Community Events Completion Audit

Audit date: 2026-07-16

Scope: Phases 0–5 of `docs/community-events-implementation-plan.md` and the eight-part
product exit condition in `docs/community-events-product-design.md`. Provider ingestion
is intentionally outside this audit because Phase 6 is explicitly deferred.

## Result

All eight product-loop requirements have implementation, automated evidence, and an
interactive iPhone 13 pass in both the Development fixture and authenticated disposable
Local environments. Hosted Development has not been mutated.

## Product exit evidence

| Requirement | Implementation evidence | Behavioral evidence |
| --- | --- | --- |
| Search for or add one concert | Provider-neutral `catalog_events`, catalog-backed creation, exact identity, duplicate candidates, and Upcoming/Past search in the Phase 1 and product-exit migrations; Local iOS discovery and creation in `Features/Event` | `015_community_event_foundation.sql`, `020_catalog_event_product_exit.sql`, `SupabaseEventRepositoryTests.swift`, and the authenticated REST journey |
| Mark Going and see it in Plans | Independent audience-aware attendance, chronological Plans, calendar toggle, and profile Going in the Phase 2 and product-exit migrations and Local iOS repository | `016_catalog_event_attendance.sql`, `020_catalog_event_product_exit.sql`, Development repository tests, and the authenticated REST journey |
| Invite a friend and see permitted attendance | Friend-only invitation inbox and transactional accept-to-Going | `017_catalog_event_invitations_posts.sql` plus the two-session invitation/acceptance/profile-Going REST journey |
| Discuss the upcoming show | Friends/community posts, one-level replies, audience selection, rate limits, and read-only post-show behavior | `017_catalog_event_invitations_posts.sql`, Swift RPC contract tests, and the two-session reply/feed REST journey |
| Confirm Went without a diary | Went and Did not go remain independent of diary creation; Going never converts automatically | `016_catalog_event_attendance.sql`, `018_catalog_event_diaries.sql`, and `attendanceMutationDoesNotCreateADiary()` |
| Optionally publish a diary with score, review, or photo | One personal diary per person/event, independent diary audience, modular composer, and photo-only publication | `018_catalog_event_diaries.sql`, `020_catalog_event_product_exit.sql`, Storage integration, diary contract tests, and `aReadyPhotoCanBeTheOnlyDiaryContent()` |
| See permitted friend activity and diary previews from the shared event | Friend-only activity projection with audience-authorized diary preview; event Memories and direct diary routing | `017_catalog_event_invitations_posts.sql`, `018_catalog_event_diaries.sql`, `020_catalog_event_product_exit.sql`, and the authenticated REST journey |
| Retain attendance and diary history after cancellation, merge, or tombstone | Redirect-preserving merge, explicit attendance supersession, tombstone-safe history snapshots, forced-private detach, and audited relink recovery | `019_catalog_event_integrity_operations.sql`, its operator runbook, and the Phase 5 durability/conflict matrix |

## Cross-cutting guarantees

- MusicBrainz and tunedIn catalog UUIDs are the default identity path. Event mutation
  RPCs accept catalog IDs and structured dates, never authoritative artist or venue
  strings.
- Attendance, invitations, posts, and diaries have distinct privacy state. A diary can
  remain friends-visible while its owner's separate Went record is private; the
  authenticated REST journey proves that boundary through two ordinary user sessions.
- Quotas and authorization are enforced at the Postgres boundary. Ordinary clients do
  not receive direct table mutation grants.
- Event correction, cancellation, merge, tombstone, detach, and relink operations do
  not cascade-delete personal memories.
- Notification outbox rows contain opaque identifiers and action types, not post,
  review, caption, profile, or event text.
- The legacy shared concert archive remains operational and isolated from new personal
  diary records. The existing-data MusicBrainz upgrade runs before every full backend
  verification.
- Ticketmaster is absent from runtime code, credentials, migrations, jobs, and links.
  It remains an optional future `event_sources` adapter requiring its own persistence,
  licensing, refresh, attribution, and monitoring decision.

## Verification record

- `make backend-verify`: existing-data upgrade, fresh reset and seed, generated DTO
  freshness, 567 pgTAP checks across 20 files, authenticated two-session REST journey,
  and Local Storage authorization all passed.
- `supabase db lint --local --level warning`: only the repository's pre-existing
  warnings remain; no community-event migration warning was introduced.
- `make generate` and `make lint`: generation passed; lint reported 0 serious
  violations.
- `make test`: 184 tests across 39 suites passed on iPhone 13 Simulator.
- `make build-local`: the Local Supabase app build passed for iPhone 13 Simulator.
- Interactive fixture pass: the `community-events` Development scenario verified Feed,
  direct diary routing, diary comments, Plans, People, invitation state, Upcoming/Past
  discovery, profile Going/Went/Diaries, pre-show conversation, the modular diary
  composer, and cancelled-event presentation.
- Authenticated Local pass: after a fresh `make local-db-reset`, `make simulator-local`
  signed in through the seeded Local user flow and verified search filtering, shared
  event detail, friend previews versus the complete attendee list, Going in Plans,
  invitation state, posts and replies, activity feed, separate profile Going/Went/Diary
  history, direct diary routing, scores, audience, album action, and authorized comments.
- The interactive pass found and fixed two fixture integration gaps: diary activity now
  opens the selected personal diary directly, and community-diary fixture IDs can use
  the album/comment infrastructure without weakening legacy-concert visibility checks.

## Rollout boundary

This audit proves the implementation on a disposable Local stack only. The draft pull
request must remain unmerged until review, and hosted Development must advance only from
a reviewed `main` commit through the protected manual workflow. Phase 6 provider work,
Staging/TestFlight promotion, and broad community creation remain separate decisions.
