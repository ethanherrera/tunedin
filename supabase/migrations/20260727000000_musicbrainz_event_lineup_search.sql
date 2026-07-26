-- MusicBrainz event search must match every billed artist, not just the
-- headliner. Keep this derived from the normalized lineup so write-through
-- imports and their refreshes cannot drift from discoverable search.
create function private.refresh_musicbrainz_catalog_event_search_text(p_event_id uuid)
returns void
language plpgsql
set search_path = ''
as $$
begin
  update public.catalog_events as event
  set search_text = lower(regexp_replace(
    btrim(concat_ws(
      ' ',
      event.tour_name_snapshot,
      (
        select string_agg(lineup.artist_name_snapshot, ' ' order by lineup.lineup_position)
        from public.catalog_event_artists as lineup
        where lineup.event_id = event.id
      ),
      event.venue_name_snapshot,
      event.area_name_snapshot
    )),
    '[[:space:]]+', ' ', 'g'
  ))
  where event.id = p_event_id
    and event.origin = 'musicbrainz';
end;
$$;

create function private.refresh_musicbrainz_catalog_event_search_text_trigger()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  perform private.refresh_musicbrainz_catalog_event_search_text(
    case when tg_op = 'DELETE' then old.event_id else new.event_id end
  );
  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$$;

create trigger refresh_musicbrainz_catalog_event_search_text
after insert or update of catalog_artist_id, lineup_position, is_headliner, artist_name_snapshot or delete
on public.catalog_event_artists
for each row
execute function private.refresh_musicbrainz_catalog_event_search_text_trigger();

select private.refresh_musicbrainz_catalog_event_search_text(id)
from public.catalog_events
where origin = 'musicbrainz';
