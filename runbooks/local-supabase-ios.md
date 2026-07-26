# Local Supabase iOS

## Purpose

Run the complete tunedIn iOS journey—email sign-in, onboarding, private concerts, friendships, collaboration, comments, sharing, and activity—against the current worktree's disposable Docker Supabase stack. Each reset loads valid, deterministic accounts and backend states so manual testing starts with usable data rather than setup screens. This procedure never contacts or changes `tunedin-dev`.

## Prerequisites and permissions

- Docker Desktop is running.
- Supabase CLI, Xcode, and an iPhone 13 Simulator are installed; run `make setup` to verify tools.
- The current worktree's local database may be reset. Do not use this procedure for data that must persist.

## Commands

From the repository root:

```sh
# Restore the complete known journey catalog when you need a fresh state.
make local-db-reset

# Start/reuse Local Supabase, configure the ignored xcconfig, build, install,
# and launch the app without resetting the data above.
make simulator-local
```

`make local-db-reset` already runs the seed verification; `make local-seed-verify` is useful after inspecting or changing local data. `make simulator-local` automatically starts this worktree's Local stack and refreshes `Local.xcconfig`, but deliberately does not reset data—use `make local-db-reset` only when you want this worktree's catalog restored.

## Seeded accounts and journeys

All accounts below are real Local Auth accounts. The Local sign-in screen provides a one-tap account picker that creates a normal password-authenticated Supabase session; it is available only for the disposable loopback Local stack. No account, profile, relationship, concert, or email-link handoff is required before testing.

| Account | Ready state | Useful journeys |
| --- | --- | --- |
| `listener@tunedin.local` | Completed profile (`local_listener`) | Primary account: five friends, pending outgoing/incoming/declined requests, discoverable people, six owned concerts, shared concerts, comments, and activity. |
| `morgan@tunedin.local`, `ava@tunedin.local`, `jules@tunedin.local`, `riley@tunedin.local`, `casey@tunedin.local` | Completed profiles | Established friend circle with their own friend lists and private, friends-only, and collaborator concerts. |
| `sasha@tunedin.local` | Completed profile | Local Listener's pending outgoing request. |
| `theo@tunedin.local` | Completed profile | Local Listener's pending incoming request. |
| `june@tunedin.local` | Completed profile | Local Listener's declined request. |
| `noah@tunedin.local`, `blair@tunedin.local`, `elena@tunedin.local`, `quinn@tunedin.local`, `marin@tunedin.local`, `parker@tunedin.local` | Completed profiles | Discoverable people with no relationship to Local Listener. |
| `newcomer@tunedin.local` | Auth account without a completed profile | Real onboarding flow. |

The catalog includes 24 valid concerts across private, friends, and collaborator visibility; eight valid collaborator memberships; twelve comments; and 73 activity events. The primary account can directly explore owner, friend, collaborator, pending-request, declined-request, and discovery states while still calling the real RLS policies and RPCs.

To sign in to any seeded account:

1. Tap **Continue as Local Listener** for the primary account, or **Choose another seeded account** for a specific journey.
2. The app signs in through normal Local Supabase password auth and immediately applies the account's profile and RLS permissions.

Sign out and repeat with another seeded address to inspect that person's valid view. This worktree's local database keeps all catalog data until the next `make local-db-reset`.

To test the email-link flow itself instead, enter a seeded address manually, use the Inbucket URL from `./scripts/worktree-local-supabase.sh status`, copy the **Sign in** button address without opening it on the Mac, run `make simulator-auth-link`, then choose **Open** in tunedIn.

## Expected result and verification

- `make local-db-reset` starts or reuses Docker Supabase, applies every migration, loads the local development seed, and passes `make local-seed-verify`.
- `make local-seed-verify` proves the catalog contains 16 Local Auth accounts, 15 completed profiles plus one onboarding profile, five primary-account friends, pending outgoing/incoming/declined relationship states, six discoverable profiles, 24 concerts, eight collaborations, twelve comments, 73 activity events, and no private concert with collaborators.
- `make simulator-local` starts or reuses this worktree's Local Supabase, writes the running local API URL and publishable key only to ignored `ios/Config/Local.xcconfig`, then builds the `tunedIn-Local` scheme, installs it into this worktree's Simulator, and launches it. It never prints the key or resets data.
- The Local scheme stores its temporary Supabase session and PKCE verifier in the Simulator app sandbox because command-line Simulator builds are unsigned. It is constrained to `127.0.0.1`/`localhost` and must never be used with a hosted project.
- The Local-only account picker signs into seeded real Local Auth accounts with normal password sessions, so the app can create additional data through the hardened RPCs if a destructive/empty-state journey needs it and exercise collaboration/comment/activity paths under the same RLS and RPC rules covered by pgTAP.
- Run `make backend-test` whenever schema, RLS, RPC, or realtime publication changes. Run `make test-local` after native changes that could depend on Local configuration.

## Recovery and audit

- To return to the complete known catalog, run `make local-db-reset`. This destroys only Docker-local Supabase data and reloads verified synthetic accounts and journeys.
- If Local configuration is stale, run `make configure-local-supabase` after `supabase start`; do not copy values from a hosted dashboard.
- If an Auth link fails, request a fresh link, choose **Open** in the iOS handoff prompt, and check local Inbucket plus the Simulator/Xcode console. Do not print or commit the one-time link.
- Local Supabase CLI output, Docker logs, and Xcode console are the investigation locations. There is no hosted audit trail because this procedure does not reach a hosted project.

## Cadence

Use before local end-to-end feature verification and after any local reset, migration, or Supabase CLI restart. When a local-testable user journey changes, update `supabase/seeds/development.sql`, the seed verifier, this runbook, and the relevant database/iOS tests in the same change.
