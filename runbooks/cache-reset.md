# Simulator Cache Reset

## Purpose

Clear tunedIn's app-owned structured-response and image-response caches in a booted iOS Simulator. Use this only to reproduce cold-cache behavior or recover from a suspected local cache problem; it does not alter Supabase, authentication, Keychain data, app preferences, or user-created records.

## Prerequisites and permissions

- Xcode command-line tools are installed.
- An iOS Simulator is booted.
- The Development/Local app (`com.ethanherrera.tunedin`) or Staging app (`com.ethanherrera.tunedin.staging`) is installed in that Simulator.
- No backend or GitHub permission is required.

## Commands

Reset the Development or Local app cache:

```sh
make cache-reset
```

Reset the Staging app cache:

```sh
TUNEDIN_CACHE_BUNDLE_ID=com.ethanherrera.tunedin.staging make cache-reset
```

The script accepts only those two bundle identifiers. It terminates the selected app before removing `Library/Caches/tunedIn/Cache` from that app's Simulator data container.

## Expected result

The command prints the selected bundle identifier and confirms that its app-owned cache was cleared. The next launch recreates protected cache directories and fetches server-backed content as each surface needs it.

## Verification

Relaunch the same app and open a server-backed profile, feed, concert, or album. The first visit should load from the configured server; subsequent visits should reuse the rebuilt cache until an explicit refresh, mutation, invalidation, expiry, or eviction applies.

## Recovery and rollback

Cached data is disposable, so there is no cache backup to restore. Relaunch the app and revisit the affected screens to repopulate it. If the command reports that the app is not installed, install it with `make simulator-local`, `make simulator-live`, or the appropriate Staging build and rerun the command.

## Audit and logs

This is a Simulator-only local operation. Its only audit record is terminal history/output; it does not emit telemetry or mutate a hosted environment.

## Cadence

Run on demand for development diagnosis and explicit cold-cache verification, not as part of routine builds or every app launch.
