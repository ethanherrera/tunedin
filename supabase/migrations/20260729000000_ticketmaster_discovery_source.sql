-- Ticketmaster identities are intentionally independent from MusicBrainz and
-- community-created catalog identities. A later reconciliation project may
-- connect them, but ingest must never guess that relationship.
alter type public.catalog_entity_origin add value if not exists 'ticketmaster';
