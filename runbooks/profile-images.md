# Profile Images

## Purpose

Operate the private `images` bucket, fixed profile/main photos, and reserved concert album objects at `concerts/{concert-id}/album/{photo-id}.jpg`.

## Prerequisites and permissions

- Docker and Supabase CLI for Local verification.
- Local verification on the requested branch and protected Development environment access for hosted deployment.
- Never use the dashboard to create or change this bucket.

## Commands and expected result

Run `make backend-verify` to rebuild Local, verify the bucket/schema, regenerate types, and run authorization tests. Run `make simulator-local`; use Settings → Profile Photo and the concert creation/edit main-photo controls for real local flows. For shared Development testing, dispatch `make dev-deploy` from the requested branch; Staging remains the post-`main` environment.

## Verification

Confirm the bucket is private, has a 5 MB bucket limit, and accepts only `image/jpeg`. In the iPhone 13 Simulator, add, replace, relaunch, and remove both photo types. Concert photos are stored as optimized portrait 3:4 JPEGs. Confirm viewers can read only visible concert photos and cannot mutate photos unless they can edit that concert.

For albums, confirm `concert_album_policy()` reports policy version 1: 100 photos per concert, 30 per contributor, 10 reservations per rolling 24 hours, 10 picker items, 300 caption characters, 2 MB files, and one-hour pending reservations. Adjust any limit only in a new forward migration, updating both the policy RPC and matching enforcement tests together. Expired pending rows no longer consume album capacity and may be inspected with `select id, concert_id, uploader_id, expires_at from public.concert_photos where status = 'pending' and expires_at <= now();`; keep them as the rolling-rate audit record or remove them during an explicitly reviewed cleanup after 24 hours.

## Recovery and rollback

Migrations are forward-only. Correct a bad contract with a new migration. If removal clears profile metadata but Storage deletion fails, sign back in as the owner and retry deletion of the one fixed path through the Storage API; do not delete rows from `storage.objects` directly. Failed attachment cleanup is safe to retry at the same fixed path.

Album uploads retry the same reservation ID and object path. For a stuck deletion, list rows in `deleting` status, delete their exact objects through the authenticated Storage API, then call the matching finalize RPC. Concert deletion follows the same prepare → Storage API cleanup → finalize sequence, so rerunning it is safe after partial cleanup. Never finalize by directly deleting database or Storage metadata rows.

The iOS client bounds API requests at 30 seconds and whole-resource transfers at 60 seconds. A timeout is a terminal item failure, not an automatic retry: successful batch items remain attached, navigation unlocks after the batch resolves, and the user explicitly retries the failed item with its original photo ID and reservation path. Storage replacement is authorized only while that caller still owns a live pending reservation.

## Audit location and cadence

Git migrations and protected workflow logs are the provisioning audit trail. Review bucket bytes and ready/pending/deleting row counts monthly during the private beta and after reported deletion failures. Objects are environment-local and must never be copied between Local, Development, Staging, or Production.
