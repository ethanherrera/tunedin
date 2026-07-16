# Community Events UX Audit

Audit date: 2026-07-16

Status: implementation input; the audited Local journey is not the target UX

## Decision update

The first community-events implementation proved the data and authorization model, but
its interface stayed too close to tunedIn's existing card-and-form vocabulary. The next
iteration should use the strongest adjacent products as composition models, not merely
as a collection of small component ideas.

- Use **Beli** as the clearest model for one shared destination with independent personal
  entries, friend-first opinion browsing, a content-led feed, and a modular contribution
  flow.
- Use **Instagram** as the clearest model for author identity, edge-to-edge media, a
  caption/comment reading order, and a profile that becomes browsable content quickly.
- Continue using **DICE/Luma/Partiful** for the event-specific parts Beli and Instagram do
  not solve: factual show identity, Going, attendees, invitations, and plans.

This authorizes close structural borrowing when it makes the journey clearer. tunedIn
should not copy another product's logo, wording, proprietary artwork, or engagement
mechanics, but it should not preserve a weaker tunedIn layout merely to look different.

## References inspected directly

- [Beli recent activity](https://mobbin.com/flows/da9e92c0-0247-4e85-9f4a-9f1c84620442)
- [Beli feed](https://mobbin.com/flows/1f104d4c-33de-4d74-848d-0f7dc0a643c5)
- [Beli profile](https://mobbin.com/flows/e2d075bd-a5ab-4ab5-9b23-dfc0f1b86466)
- [Beli add-a-ranking](https://mobbin.com/flows/08b43844-b0d6-4238-87ef-7a6c9bf07bbb)
- [Beli add-visit-date](https://mobbin.com/flows/ce9be267-fb5a-4814-8ac0-690095346425)
- [Beli add-photo](https://mobbin.com/flows/bfdff0c1-01d0-48a1-bdaf-f42cb77ba833)
- [Beli personal notes/photos and friend opinions](https://mobbin.com/screens/fff7f8f1-b509-4810-bf1b-6529875c8d4b)
- [Instagram content-first post](https://mobbin.com/screens/f17c553c-5855-47f0-99e0-4df0e130f115)
- [Instagram profile grid](https://mobbin.com/screens/abeb5174-05b0-4d7f-863f-226c6b2eed2a)
- [Instagram profile-to-content flow](https://mobbin.com/flows/bfa2eee7-145b-475b-80d4-86ab6a389495)

## Journey audit

| Journey | Current Local behavior | Why it misses the plan/reference | Direction to implement |
| --- | --- | --- | --- |
| Feed | Every activity is a large outer card containing another full event or diary card. Going, posts, replies, creation, and correction all receive nearly the same visual weight. | Beli changes density by activity type. Instagram makes the authored content the post rather than wrapping it in dashboard chrome. The current repetition hides both the friend and the concert. | Use a compact author/action row. Render Going/invite/update activity as a short concert row. Render a published diary as the post itself: author, event, score, media when available, review, and comments affordance. Remove the explanatory Feed subtitle. |
| Search | Concert search works, but a large People-search card competes with results and every row repeats `Community added`. | Search is supposed to be a direct concert utility. Provider provenance is secondary and People is a scope, not a full promotional card. | Keep the search field first, make People an inline scope/action, remove repetitive provenance from normal rows, and keep `Add concert` subordinate to actual results or an empty search. |
| Upcoming event | A generic inset card duplicates date/venue facts, leads with `Community added`, calls Going `Added to my plans`, and spends prime space on a details table. | DICE/Luma put event identity, time/place, response, and friends together before secondary metadata. | Build a stronger poster-like event header, use `Going`/`I'm going`, keep audience understandable, promote friend faces and Invite, and collapse correction/provenance into secondary details. |
| People and invites | Attendees are an undifferentiated list. The invite sheet has useful status rows but no search, selected count, or explicit send step visible in the initial state. | The plan and Luma/Partiful references call for friends first, status filtering, multi-select, and one clear send action. | Separate Friends from Community, retain compact status chips, add search and selected state, and keep a persistent send action. |
| Plans | The list is functional, but the large header/subtitle and identical cards make it feel like an administrative calendar. | Luma's list is denser and lets state and social context do the explaining. | Keep chronological list as default, reduce instructional copy, use date grouping and friend faces, and treat calendar as a secondary visualization. |
| Past event | The hero still says a friend `is going`; the Event tab says `Start the conversation` after the show. | Both contradict the lifecycle contract. After unlock, attendance should read `went`, and event conversation is read-only; new discussion belongs to diaries. | Make phase-aware friend language, present old event posts as a read-only pre-show thread, and route post-show interaction into friend/community diaries. |
| Memories | Two diary cards are stacked under explanatory text with no visible Friends/Community separation and little media emphasis. | Beli makes friend opinions the useful layer under a shared place. The plan requires friends first and community as an explicit expansion. | Lead with visible friend score and friend diary posts, then a separate community section. Use richer, reusable diary posts and remove model-explaining copy. |
| Diary detail | The screen starts with `Your diary` and policy explanation, then repeats a card before showing an empty Photos section and comments. | Beli/Instagram use author + score, media, caption/review, and comments as the natural reading order. | Title the concert, show the author row, make the album the visual center when present, place score/review directly with it, then comments and audience. Remove policy prose from the content hierarchy. |
| Diary composer | Large switches and sliders consume the first screen; note, photos, audience, and Save fall below the contextual bar. | Beli asks for a simple reaction first, then exposes modular rows for optional additions. | Use a compact score control, then modular rows for performance, note, photos, and audience. Keep Save visible and allow any valid content combination. |
| Profile | Going, Went, and Diaries are followed immediately by the old `Kept` concert archive, producing two competing histories. The page explains the data model instead of becoming browsable content. | Beli/Instagram profiles lead with identity and social proof, then switch into content/history. Legacy implementation details should not define the main profile. | Use identity + counts, a Going/Went/Diaries switch, rich diary content/grid, and move legacy shared concerts to a clearly labeled secondary route rather than the main scroll. Apply the same structure to friend profiles. |
| MusicBrainz fallback | `Can't find it? Add to tunedIn catalog` appears before any meaningful query because it is present in Recent and every results list. | This violates the approved MusicBrainz-first fallback sequence. | Hide custom creation until a meaningful search returns no correct catalog identity; keep existing custom results visibly reusable when they genuinely match. |

## Confirmed outdated or broken paths

- `CommunityEventHero.friendLine` always uses `is/are going`, including past events.
- `EventOverviewPage` changes its heading after unlock but keeps an empty-state invitation
  to start an event conversation.
- `ConcertArchiveView` is embedded directly in both current-user and friend Profile flows
  even when the community-event diary model is enabled.
- `CatalogRecentSearchesView` and `CatalogResultsList` always expose custom catalog
  creation before a failed meaningful search.
- `CommunityActivityCard` nests complete cards, causing duplicated borders, padding,
  event identity, and state labels.
- `EventDiaryDetailView` reserves insufficient bottom content space for its persistent
  control bar and puts explanatory policy copy above the actual memory.

## Implementation order

1. Replace the Feed/Profile/Plans hierarchy and remove the legacy archive from the main
   profile journey.
2. Recompose upcoming and past event detail, fix lifecycle copy, and make friend/community
   context explicit.
3. Replace diary previews, detail, and composer with the Beli/Instagram content hierarchy.
4. Tighten discovery, creation wording, invitation interaction, and MusicBrainz fallback.
5. Repeat the fixture and authenticated Local journeys in the iPhone 13 Simulator after
   every UI-changing commit; do not continue editing if Simulator access is lost.
