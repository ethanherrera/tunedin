# Local Supabase iOS

## Purpose

Run the complete tunedIn iOS journey—email sign-in, onboarding, private concerts, friendships, collaboration, comments, and activity—against the disposable Docker Supabase stack. This procedure never contacts or changes `tunedin-dev`.

## Prerequisites and permissions

- Docker Desktop is running.
- Supabase CLI, Xcode, and an iPhone 13 Simulator are installed; run `make setup` to verify tools.
- The local database may be reset. Do not use this procedure for data that must persist.

## Commands

From the repository root:

```sh
make local-db-reset
make configure-local-supabase
make simulator-local
```

To test email authentication:

1. Enter an unused local email address in the app.
2. Open local Inbucket at `http://127.0.0.1:54324` on the Mac and find the message.
3. Copy the **Sign in** button address without opening it on the Mac.
4. Run `make simulator-auth-link` from the repository root.
5. When iOS asks whether to open the link in tunedIn, choose **Open**.

For a second local person, sign out, repeat the email flow with a second address, and complete onboarding. The local database keeps both accounts until the next `make local-db-reset`.

## Expected result and verification

- `make local-db-reset` starts or reuses Docker Supabase, applies every migration, and loads the local development seed.
- `make configure-local-supabase` writes the running local API URL and publishable key only to ignored `ios/Config/Local.xcconfig`; it never prints the key.
- `make simulator-local` builds the `tunedIn-Local` scheme, installs it into the booted Simulator, and launches it.
- The Local scheme stores its temporary Supabase session and PKCE verifier in the Simulator app sandbox because command-line Simulator builds are unsigned. It is constrained to `127.0.0.1`/`localhost` and must never be used with a hosted project.
- The app can create a real local Auth user and profile, save a concert through the hardened RPC, create friend requests, and exercise collaboration/comment/activity paths under the same RLS and RPC rules covered by pgTAP.
- Run `make backend-test` whenever schema, RLS, RPC, or realtime publication changes. Run `make test-local` after native changes that could depend on Local configuration.

## Recovery and audit

- To return to a clean known state, run `make local-db-reset`. This destroys only Docker-local Supabase data.
- If Local configuration is stale, run `make configure-local-supabase` after `supabase start`; do not copy values from a hosted dashboard.
- If an Auth link fails, request a fresh link, choose **Open** in the iOS handoff prompt, and check local Inbucket plus the Simulator/Xcode console. Do not print or commit the one-time link.
- Local Supabase CLI output, Docker logs, and Xcode console are the investigation locations. There is no hosted audit trail because this procedure does not reach a hosted project.

## Cadence

Use before local end-to-end feature verification and after any local reset, migration, or Supabase CLI restart.
