# Scripts Guide

## Responsibility

Scripts provide small, portable terminal tasks invoked by `make`, CI, and documented runbooks.

## Rules

- Use `bash` with `set -euo pipefail` and clear actionable errors.
- Never print credentials, access tokens, connection strings, or user content.
- Keep scripts idempotent where practical and avoid hidden deployment side effects.
- Add or update a runbook before introducing a recurring maintenance or high-impact operational command.
- Keep generated-output checks deterministic and non-mutating.
- Simulator scenario launchers must accept only an explicit allow-list of UI fixture names. They may pass Development launch arguments but must never inject credentials, privileged users, or backend authorization bypasses.
- Local-stack helpers may read `supabase status -o env` to populate ignored local configuration, but must never print or log returned keys. They must operate only on Docker-local data and state that boundary in their success output.
- Development-deployment helpers must hard-code the approved project ref, obtain the database password only from an environment variable or the documented Keychain item, and never echo either credential. They may apply migrations only from the manually dispatched GitHub workflow on an explicitly requested branch; they must not reset hosted data, include seeds, or push unrelated Supabase configuration.
- Staging-deployment helpers must require and validate the protected Staging project ref, explicitly reject the Development project, and mutate Staging only from the manually dispatched protected `main` workflow. They may deploy tracked migrations and Edge Functions but must never include seeds or copy database/Storage data.

## Verification

Run a shell syntax check and the corresponding `make` target after changing a script.
