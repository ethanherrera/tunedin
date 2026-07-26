# Worktree Simulators

## Purpose

Give every tunedIn Git worktree its own persistent iPhone 13 Simulator, app containers, and Derived
Data so parallel agents can build, test, install, and launch without selecting the same device or
overwriting another worktree's app. The helper uses the worktree's canonical path—not its branch or
commit—as the stable identity.

## Prerequisites and permissions

- Run on macOS with the repository in a Git worktree.
- Install Xcode, finish its first-launch setup, select it with `xcode-select`, and install an iOS
  runtime that supports iPhone 13.
- Allow Terminal or the agent to control CoreSimulator and open Simulator when macOS asks.
- No Apple Developer Program membership, signing identity, backend credential, or GitHub permission
  is required.

## Commands

From each worktree root:

```sh
make simulator-create
make simulator-status
make simulator-live
make simulator-onboarding
make simulator-local
make simulator-delete
```

Run the same commands concurrently from other worktree roots. Each helper derives a name such as
`tunedIn Worktree <worktree-label>-<path-hash>`, creates it with `xcrun simctl create` when absent, and thereafter
targets that UUID. Device creation is protected by a per-worktree lock so concurrent commands in
one workspace do not create duplicates.

Build and test commands write to the worktree's ignored `DerivedData/` and pass the worktree UUID as
the `xcodebuild` destination. CI or a deliberate one-off command can override both with
`DESTINATION` and `DERIVED_DATA_PATH`, for example:

```sh
make test DESTINATION='platform=iOS Simulator,name=iPhone 17'
```

These helpers intentionally leave generated development state behind so a worktree can be resumed:
`DerivedData/`, ignored Xcode configuration, and `supabase/.temp/worktrees/<path-hash>/` contain
only local build/configuration/database state and are not Git changes. The fixture worker keeps its
ignored logs and PID files under `supabase/.temp/music-catalog/`. Before removing a worktree, run
`make simulator-delete` and `./scripts/worktree-local-supabase.sh stop`; then remove that worktree's
exact ignored `DerivedData/` and `supabase/.temp/` entries if disk cleanup is desired. Git worktree
removal itself does not run application cleanup hooks.

The Local Supabase stack is isolated by the same worktree path. `make local-db-start` creates a
generated ignored Supabase project with a unique project ID, Docker volume namespace, port block,
database, Auth, Storage, Inbucket, and Edge Function runtime. `make configure-local-supabase` reads
only that stack's loopback URLs and writes them to this worktree's ignored `ios/Config/Local.xcconfig`.
The fixture-only MusicBrainz stub and its function worker use the same worktree's unique port.

Hosted Development and Staging are intentionally shared environments. Use `tunedIn-Development`
for explicitly coordinated hosted integration; use `tunedIn-Local` for isolated parallel mutation
and RLS testing.

## Expected result

- `make simulator-status` prints the canonical worktree path, deterministic device name, UUID, and
  current state.
- A launch command boots and opens that worktree's Simulator window even when other devices are
  already booted.
- Installs, sessions, Keychain items, app preferences, caches, and local media remain inside that
  device's containers.
- Build products and intermediates remain under the current worktree's ignored `DerivedData/`.
- Auth-link and cache-reset helpers target the same UUID rather than whichever Simulator happens to
  be booted last.
- Local database, Auth, Storage, Inbucket, Edge Functions, and MusicBrainz fixture requests stay
  inside the current worktree's disposable stack.

## Verification

From two worktrees, run `make simulator-live`, then confirm:

```sh
xcrun simctl list devices | rg 'tunedIn Worktree'
make simulator-status
```

Both named devices should have different UUIDs and be booted, with each showing the build launched
from its own worktree. Run `make simulator-script-test` to exercise creation reuse, UUID targeting,
boot/open selection, Derived Data isolation, CI overrides, and scoped deletion with a fake
CoreSimulator. Run `make local-seed-verify` from each worktree after `make local-db-reset` to prove
that each disposable database has its own seeded catalog and Storage state.

## Recovery and rollback

- If a device is stuck, run `make simulator-delete` and rerun a launch command. The helper recreates
  the device on the newest compatible installed iOS runtime.
- If Xcode no longer supports the device's runtime, delete only this worktree's device and recreate
  it; do not use `simctl delete all`.
- If a worktree was removed before cleanup, find its `tunedIn Worktree ...` entry with
  `xcrun simctl list devices`, verify the UUID, and run `xcrun simctl delete UUID`.

## Audit and logs

Simulator device state is visible in `xcrun simctl list devices` and `make simulator-status`.
CoreSimulator logs live under `~/Library/Logs/CoreSimulator/`, while build products and logs remain
under the worktree's ignored `DerivedData/`. These helpers do not emit telemetry or change a hosted
backend.

## Cadence

Create or reuse the device whenever a worktree needs native iOS work. Delete it immediately before
removing that worktree, and recreate it after an incompatible Xcode or iOS runtime upgrade.
