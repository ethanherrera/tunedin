-- Preserve the provider's ordered search page after write-through ingestion.
-- The function accepts only IDs returned by the authenticated gateway and still
-- applies the same discoverability rule to every row.
create function public.list_discoverable_catalog_event_summaries(p_event_ids uuid[])
returns table (event jsonb)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_caller_id uuid := private.require_completed_caller();
begin
  if coalesce(cardinality(p_event_ids), 0) > 20 then
    raise exception 'At most 20 event IDs may be requested' using errcode = '22023';
  end if;

  return query
  select private.catalog_event_projection_json(requested.event_id)
  from unnest(coalesce(p_event_ids, '{}'::uuid[])) with ordinality as requested(event_id, ordinal)
  join private.catalog_event_projections as projection on projection.event_id = requested.event_id
  where projection.row_state = 'active'
    and private.can_read_catalog_event_as(v_caller_id, requested.event_id)
  order by requested.ordinal;
end;
$$;

revoke all on function public.list_discoverable_catalog_event_summaries(uuid[]) from public, anon;
grant execute on function public.list_discoverable_catalog_event_summaries(uuid[]) to authenticated;
