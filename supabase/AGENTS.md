# Supabase Backend Guide

## Responsibility

This directory contains the versioned Supabase schema, RLS policies, hardened RPCs, Edge Functions, deterministic development seed data, and direct database authorization tests.

## Rules

- Every shared schema change is a new, forward-only timestamped migration. Do not rewrite applied migrations or make dashboard-only changes.
- Keep access logic in reusable Postgres helper functions, then use those helpers consistently in RLS policies and RPCs.
- Permission-sensitive multi-table actions must be narrowly scoped `SECURITY DEFINER` RPCs with a fixed `search_path`, authenticated-caller validation, least-privilege grants, and pgTAP coverage.
- The hosted Development project is the day-to-day backend. Docker/local Supabase is only a disposable test environment.
- Seed data must be deterministic and synthetic; never copy production data.

## Secrets and verification

- Do not commit Supabase personal access tokens, database passwords, service-role keys, SMTP credentials, APNs credentials, or `.env` files.
- Run `supabase test db` after migrations, RLS, helpers, or RPCs change. Add real owner/editor/friend/non-friend/blocked authorization cases.
- Generate and commit Swift DTOs after each public-schema change.
