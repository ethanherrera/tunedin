# Edge Functions Guide

## Responsibility

This directory contains authenticated Supabase Edge Functions and their deterministic
unit/integration fixtures. `music-catalog/` is the only gateway allowed to contact MusicBrainz.

## Dependencies and boundaries

- Keep function code dependency-free where practical and use the runtime Web APIs.
- Call MusicBrainz only through the fixed official HTTPS origin in hosted environments. A loopback
  override is allowed only when `TUNEDIN_ENVIRONMENT=Local` for committed fixture tests.
- Treat Postgres RPCs as the authorization, quota, cache, coalescing, ingestion, and
  application-wide rate-limit boundary. Never replace them with instance-local limits.
- Never log authorization headers, user IDs, raw search queries, catalog names, addresses, MBIDs,
  URLs with query strings, upstream bodies, or setlist content.
- Edge Functions may use the service-role key only for the narrowly scoped RPCs that are revoked
  from ordinary clients. Never return or print it.
- Keep request and upstream decoding strict, bounded, and fail closed. Return only the typed safe
  error envelope documented by the function contract.

## Environment and secrets

- Runtime configuration is supplied through Supabase Function secrets. Do not commit `.env` files or
  contacts used in the MusicBrainz User-Agent.
- Hosted deployments require `TUNEDIN_ENVIRONMENT` and a contactable `MUSICBRAINZ_USER_AGENT`; only
  the protected workflows may reconcile them.
- Local lifecycle tooling writes its fixture-only environment under ignored `supabase/.temp/` and
  must never point a Local function at a hosted project.

## Required verification

- Run `make functions-test` after any function, fixture, or Deno helper change.
- Run `make local-catalog-verify` after changing the HTTP/RPC integration contract.
- Keep all required CI deterministic. Live MusicBrainz checks are opt-in only through
  `make musicbrainz-smoke` and must remain serialized.
