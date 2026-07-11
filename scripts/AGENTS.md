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

## Verification

Run a shell syntax check and the corresponding `make` target after changing a script.
