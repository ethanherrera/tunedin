-- Deferred lineup validation runs at transaction commit, after the public
-- concert RPC has performed the child inserts. It must retain the narrowly
-- scoped migration-owner privileges needed to invoke its private assertion.

alter function private.enforce_concert_lineup() security definer;
alter function private.enforce_concert_lineup() set search_path = '';

revoke all on function private.enforce_concert_lineup() from public, anon, authenticated;
