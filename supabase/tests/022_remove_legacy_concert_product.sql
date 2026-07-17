begin;

select plan(10);

select is(
  (
    select count(*)
    from information_schema.tables
    where table_schema = 'public'
      and table_name in (
        'setlist_items', 'concert_events', 'concert_collaborators',
        'direct_collaboration_notifications', 'concerts', 'concert_artists',
        'concert_photos', 'diary_reviews', 'comments', 'catalog_event_posts'
      )
  ),
  0::bigint,
  'unsupported public content tables are removed'
);

select is(
  (
    select count(*)
    from information_schema.tables
    where table_schema = 'private'
      and table_name in (
        'catalog_event_diary_mutations', 'catalog_event_integrity_operations'
      )
  ),
  0::bigint,
  'unsupported private transition tables are removed'
);

select is(
  (
    select count(*)
    from pg_proc as procedure
    join pg_namespace as namespace on namespace.oid = procedure.pronamespace
    where namespace.nspname in ('public', 'private')
      and (
        procedure.proname like '%diary%'
        or procedure.proname like '%concert%'
        or procedure.proname in (
          'create_catalog_event_post', 'list_catalog_event_posts',
          'list_catalog_event_diaries', 'reserve_concert_photo',
          'attach_concert_photo', 'create_private_concert', 'update_concert'
        )
      )
  ),
  0::bigint,
  'unsupported content RPCs and helpers are removed'
);

select is(
  (
    select count(*)
    from pg_type as type
    join pg_namespace as namespace on namespace.oid = type.typnamespace
    where namespace.nspname = 'public'
      and type.typname in (
        'concert_record_model', 'concert_visibility', 'concert_photo_status'
      )
  ),
  0::bigint,
  'unsupported content types are removed'
);

select is(
  (
    select count(*)
    from pg_enum as enum
    join pg_type as type on type.oid = enum.enumtypid
    where type.typname = 'social_activity_action'
      and enum.enumlabel in (
        'diary_published', 'diary_media_added', 'event_posted', 'event_replied'
      )
  ),
  0::bigint,
  'social activity exposes only Posts and Comments vocabulary'
);

select is(
  (
    select count(*)
    from information_schema.tables
    where table_schema = 'public'
      and table_name in ('event_comments', 'event_posts', 'post_media', 'post_comments')
  ),
  4::bigint,
  'the supported content boundary contains Comments, Posts, media, and Post comments'
);

select is(
  (
    select count(distinct procedure.proname)
    from pg_proc as procedure
    join pg_namespace as namespace on namespace.oid = procedure.pronamespace
    where namespace.nspname = 'public'
      and procedure.proname in (
        'list_event_comments', 'create_event_comment', 'list_event_posts',
        'upsert_event_post', 'get_event_post_summaries',
        'list_catalog_profile_event_history', 'list_catalog_event_activity',
        'reserve_post_media', 'attach_post_media', 'list_post_media',
        'list_post_comments', 'create_post_comment'
      )
  ),
  12::bigint,
  'all supported content RPCs exist'
);

select is(
  (
    select count(*)
    from pg_proc as procedure
    join pg_namespace as namespace on namespace.oid = procedure.pronamespace
    where namespace.nspname in ('public', 'private')
      and procedure.prokind = 'f'
      and coalesce(array_to_string(procedure.proargnames, ','), '') like '%p_concert_id%'
  ),
  0::bigint,
  'catalog and content functions no longer accept private-concert context'
);

select is(
  (
    select count(*)
    from pg_proc as procedure
    join pg_namespace as namespace on namespace.oid = procedure.pronamespace
    where namespace.nspname in ('public', 'private')
      and procedure.prokind = 'f'
      and pg_get_functiondef(procedure.oid) ~ 'legacy_(import|client)'
  ),
  0::bigint,
  'active catalog functions cannot create retired provenance rows'
);

select is(
  (
    select count(*) from public.catalog_entities
    where origin::text in ('legacy_import', 'legacy_client')
  ),
  0::bigint,
  'no retired catalog provenance rows survive the destructive cut'
);

select * from finish();
rollback;
