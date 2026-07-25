-- Expose the existing tour snapshot consistently wherever a compact event JSON
-- payload is used, and add an event-scoped invitation lookup for detail screens.

create or replace function private.catalog_event_projection_json(p_event_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'event_id', projection.event_id,
    'artists', projection.artists,
    'catalog_place_id', projection.catalog_place_id,
    'catalog_area_id', projection.catalog_area_id,
    'catalog_tour_id', projection.catalog_tour_id,
    'tour_name', projection.tour_name,
    'venue_name', projection.venue_name,
    'area_name', projection.area_name,
    'event_date', projection.event_date,
    'starts_at', projection.starts_at,
    'time_zone_identifier', projection.time_zone_identifier,
    'memory_unlock_at', projection.memory_unlock_at,
    'lifecycle', projection.lifecycle,
    'listing', projection.listing,
    'integrity', projection.integrity,
    'row_state', projection.row_state,
    'source_label', 'Community made'
  )
  from private.catalog_event_projections as projection
  where projection.event_id = private.resolve_catalog_event_id(p_event_id)
$$;

create or replace function private.catalog_event_history_projection_json(p_event_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'event_id', projection.event_id,
    'artists', projection.artists,
    'catalog_place_id', projection.catalog_place_id,
    'catalog_area_id', projection.catalog_area_id,
    'catalog_tour_id', projection.catalog_tour_id,
    'tour_name', projection.tour_name,
    'venue_name', projection.venue_name,
    'area_name', projection.area_name,
    'event_date', projection.event_date,
    'starts_at', projection.starts_at,
    'time_zone_identifier', projection.time_zone_identifier,
    'memory_unlock_at', projection.memory_unlock_at,
    'lifecycle', projection.lifecycle,
    'listing', projection.listing,
    'integrity', projection.integrity,
    'row_state', projection.row_state,
    'source_label', 'Community made'
  )
  from private.catalog_event_projections as projection
  where projection.event_id = coalesce(
    private.resolve_catalog_event_id(p_event_id),
    p_event_id
  )
$$;

create or replace function public.list_pending_catalog_event_invitations(
  p_cursor jsonb default null,
  p_limit integer default 20
)
returns table (
  invitation_id uuid,
  event_id uuid,
  event jsonb,
  sender_id uuid,
  sender_username text,
  sender_display_name text,
  sender_relationship text,
  sender_avatar_object_path text,
  sender_avatar_version bigint,
  created_at timestamptz,
  next_cursor jsonb
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_caller_id uuid := private.require_completed_caller();
  v_cursor_created_at timestamptz;
  v_cursor_id uuid;
begin
  if p_limit not between 1 and 50 then
    raise exception 'Invitation limit must be between 1 and 50' using errcode = '22023';
  end if;
  if p_cursor is not null then
    if jsonb_typeof(p_cursor) <> 'object'
      or (p_cursor - 'created_at' - 'invitation_id') <> '{}'::jsonb
      or not (p_cursor ?& array['created_at', 'invitation_id'])
    then
      raise exception 'Invitation cursor is invalid' using errcode = '22023';
    end if;
    begin
      v_cursor_created_at := (p_cursor ->> 'created_at')::timestamptz;
      v_cursor_id := (p_cursor ->> 'invitation_id')::uuid;
    exception when invalid_text_representation or datetime_field_overflow then
      raise exception 'Invitation cursor is invalid' using errcode = '22023';
    end;
  end if;

  return query
  select
    invitation.id,
    invitation.event_id,
    private.catalog_event_projection_json(invitation.event_id),
    sender.id,
    sender.username,
    sender.display_name,
    private.relationship_label(v_caller_id, sender.id),
    sender.avatar_object_path,
    sender.avatar_version,
    invitation.updated_at,
    jsonb_build_object('created_at', invitation.updated_at, 'invitation_id', invitation.id)
  from public.catalog_event_invitations as invitation
  join public.profiles as sender on sender.id = invitation.sender_id
  where invitation.recipient_id = v_caller_id
    and invitation.status = 'pending'
    and private.are_accepted_friends(invitation.sender_id, invitation.recipient_id)
    and not private.has_relationship_block(v_caller_id, invitation.sender_id)
    and private.can_read_catalog_event_as(v_caller_id, invitation.event_id)
    and (
      p_cursor is null
      or invitation.updated_at < v_cursor_created_at
      or (invitation.updated_at = v_cursor_created_at and invitation.id > v_cursor_id)
    )
  order by invitation.updated_at desc, invitation.id
  limit p_limit;
end;
$$;

create function public.get_pending_catalog_event_invitation(p_event_id uuid)
returns table (
  invitation_id uuid,
  event_id uuid,
  event jsonb,
  sender_id uuid,
  sender_username text,
  sender_display_name text,
  sender_relationship text,
  sender_avatar_object_path text,
  sender_avatar_version bigint,
  created_at timestamptz
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_caller_id uuid := private.require_completed_caller();
begin
  return query
  select
    invitation.id,
    invitation.event_id,
    private.catalog_event_projection_json(invitation.event_id),
    sender.id,
    sender.username,
    sender.display_name,
    private.relationship_label(v_caller_id, sender.id),
    sender.avatar_object_path,
    sender.avatar_version,
    invitation.updated_at
  from public.catalog_event_invitations as invitation
  join public.profiles as sender on sender.id = invitation.sender_id
  where invitation.event_id = p_event_id
    and invitation.recipient_id = v_caller_id
    and invitation.status = 'pending'
    and private.are_accepted_friends(invitation.sender_id, invitation.recipient_id)
    and not private.has_relationship_block(v_caller_id, invitation.sender_id)
    and private.can_read_catalog_event_as(v_caller_id, invitation.event_id)
  order by invitation.updated_at desc, invitation.id
  limit 1;
end;
$$;

revoke all on function public.get_pending_catalog_event_invitation(uuid)
  from public, anon;
grant execute on function public.get_pending_catalog_event_invitation(uuid)
  to authenticated;
