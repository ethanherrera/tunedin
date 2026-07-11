-- PostgreSQL only permits a UNION to order by output columns.  Alias the
-- collaborator-listing columns explicitly so existing Local/Development
-- databases can load a concert detail without a runtime SQL error.

create or replace function public.list_concert_collaborators(p_concert_id uuid)
returns table (
  id uuid,
  username text,
  display_name text,
  is_owner boolean,
  tagged_at timestamptz
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_caller_id uuid := private.require_concert_editor(p_concert_id);
begin
  return query
  select
    profile.id,
    profile.username,
    profile.display_name,
    profile.id = concert.owner_id as is_owner,
    case when profile.id = concert.owner_id then concert.created_at else collaborator.created_at end as tagged_at
  from public.concerts as concert
  join public.profiles as profile on profile.id = concert.owner_id
  left join public.concert_collaborators as collaborator
    on collaborator.concert_id = concert.id
    and collaborator.profile_id = profile.id
  where concert.id = p_concert_id

  union all

  select
    profile.id,
    profile.username,
    profile.display_name,
    false as is_owner,
    collaborator.created_at as tagged_at
  from public.concert_collaborators as collaborator
  join public.profiles as profile on profile.id = collaborator.profile_id
  where collaborator.concert_id = p_concert_id
  order by is_owner desc, tagged_at asc;
end;
$$;
