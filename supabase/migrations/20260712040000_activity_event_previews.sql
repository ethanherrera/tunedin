-- Event-specific, visibility-checked feed previews. These projections expose
-- current concert context and ready photo paths, never comment/caption bodies.

create or replace function private.can_view_concert_event_as(
  p_user_id uuid,
  p_concert_id uuid,
  p_event_type public.concert_event_type
)
returns boolean language sql stable security definer set search_path = '' as $$
  select private.is_concert_editor_as(p_user_id, p_concert_id)
    or (
      private.can_view_concert_as(p_user_id, p_concert_id)
      and p_event_type in (
        'concert_created', 'concert_updated', 'setlist_updated',
        'comment_added', 'comment_updated', 'comment_deleted', 'album_photo_added'
      )
    );
$$;

drop function public.friends_activity_feed(timestamptz, uuid, integer);
create function public.friends_activity_feed(
  p_cursor_occurred_at timestamptz default null,
  p_cursor_id uuid default null,
  p_limit integer default 30
)
returns table (
  id uuid, concert_id uuid, actor_id uuid, actor_username text, actor_display_name text,
  event_type text, occurred_at timestamptz, primary_artist text, venue_name text,
  concert_date date, changed_fields text[], setlist_preview text[], setlist_count integer,
  photo_id uuid, photo_object_path text, photo_version bigint
)
language plpgsql security definer set search_path = '' as $$
declare
  v_caller_id uuid := private.require_completed_caller();
  v_limit integer := greatest(1, least(coalesce(p_limit, 30), 30));
begin
  return query
  select event.id, event.concert_id, event.actor_id, actor.username, actor.display_name,
    event.event_type::text, event.occurred_at, primary_artist.artist_name,
    concert.venue_name, concert.concert_date,
    coalesce(array(select jsonb_array_elements_text(event.metadata -> 'changed_fields')), array[]::text[]),
    coalesce(setlist.preview, array[]::text[]), coalesce(setlist.total, 0),
    photo.id, photo.object_path, coalesce(photo.version, 0)
  from public.concert_events event
  join public.concerts concert on concert.id = event.concert_id
  join public.profiles actor on actor.id = event.actor_id
  join lateral (
    select lineup.artist_name from public.concert_artists lineup
    where lineup.concert_id = concert.id and lineup.is_primary limit 1
  ) primary_artist on true
  left join lateral (
    select
      array_agg(item.song_title order by item.set_position) filter (where item.set_position <= 3) as preview,
      count(*)::integer as total
    from public.setlist_items item where item.concert_id = concert.id
  ) setlist on true
  left join public.concert_photos photo on event.event_type = 'album_photo_added'
    and photo.id = event.subject_id and photo.status = 'ready'
  where private.are_accepted_friends(v_caller_id, event.actor_id)
    and private.can_view_concert_as(v_caller_id, concert.id)
    and private.can_view_concert_event_as(v_caller_id, concert.id, event.event_type)
    and (p_cursor_occurred_at is null or event.occurred_at < p_cursor_occurred_at
      or (event.occurred_at = p_cursor_occurred_at and event.id < p_cursor_id))
  order by event.occurred_at desc, event.id desc limit v_limit;
end;
$$;

revoke all on function public.friends_activity_feed(timestamptz, uuid, integer) from public, anon;
grant execute on function public.friends_activity_feed(timestamptz, uuid, integer) to authenticated;
