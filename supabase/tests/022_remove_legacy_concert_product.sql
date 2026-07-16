begin;

select plan(6);

select is(
  (
    select count(*)
    from information_schema.tables
    where table_schema = 'public'
      and table_name in (
        'setlist_items',
        'concert_events',
        'concert_collaborators',
        'direct_collaboration_notifications'
      )
  ),
  0::bigint,
  'retired shared-concert tables are removed'
);

select is(
  (
    select count(*)
    from pg_proc as procedure
    join pg_namespace as namespace on namespace.oid = procedure.pronamespace
    where namespace.nspname = 'public'
      and procedure.proname in (
        'create_private_concert',
        'create_private_concert_v2',
        'update_concert',
        'update_concert_v2',
        'friends_activity_feed',
        'profile_concert_history',
        'list_concert_collaborators',
        'tag_concert_collaborator',
        'remove_concert_collaborator',
        'transfer_concert_ownership'
      )
  ),
  0::bigint,
  'retired shared-concert RPCs are removed'
);

select is(
  (select count(*) from public.concerts where record_model = 'legacy_shared'),
  0::bigint,
  'no retired shared-concert records survive the destructive cut'
);

select is(
  (
    select count(*)
    from public.catalog_entities
    where origin in ('legacy_import', 'legacy_client')
  ),
  0::bigint,
  'legacy-only catalog identities are removed'
);

select ok(
  private.is_concert_editor_as(
    'd1000000-0000-0000-0000-000000000001',
    'd4500000-0000-0000-0000-000000000001'
  ),
  'a Post author retains media editing access'
);

select ok(
  private.can_view_concert_as(
    'd1000000-0000-0000-0000-000000000002',
    'd4500000-0000-0000-0000-000000000001'
  ),
  'an authorized friend retains Post visibility'
);

select * from finish();
rollback;
