# Runbooks

- [Supabase Development](./supabase-development.md) — provision and operate the shared hosted Development project.
- [Development Database Deployment](./development-database-deployment.md) — verify and explicitly deploy a requested branch's migrations to `tunedin-dev`.
- [MusicBrainz Catalog Gateway](./musicbrainz-catalog.md) — verify the fixture gateway and deploy the protected `music-catalog` Function separately from migrations.
- [Staging Promotion](./staging-promotion.md) — promote a reviewed `main` commit to the isolated Staging backend and `tunedIn Staging` TestFlight app.
- [Local Supabase iOS](./local-supabase-ios.md) — run the full disposable local iOS journey without touching `tunedin-dev`.
- [Worktree Simulators](./worktree-simulators.md) — create, run, inspect, and remove isolated iPhone 13 Simulators for concurrent Git worktrees.
- [Simulator Cache Reset](./cache-reset.md) — clear only the app-owned cache for cold-cache diagnosis in a booted Simulator.
- [Profile Images](./profile-images.md) — provision, verify, and recover private profile-photo storage.
- [PostHog Staging Observability](./posthog.md) — validate and operate the explicit Staging telemetry contract, dashboard, and dSYMs.
- [Community Event Integrity Operations](./community-event-integrity.md) — review and audit non-destructive event merge, tombstone, diary detach, and relink recovery.
