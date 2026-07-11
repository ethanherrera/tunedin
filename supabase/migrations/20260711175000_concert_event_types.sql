-- Stage 4 prerequisite: PostgreSQL requires new enum values to commit before
-- functions and policies may safely reference them.

alter type public.concert_event_type add value if not exists 'concert_updated';
alter type public.concert_event_type add value if not exists 'setlist_updated';
alter type public.concert_event_type add value if not exists 'collaborator_tagged';
alter type public.concert_event_type add value if not exists 'collaborator_removed';
alter type public.concert_event_type add value if not exists 'visibility_changed';
alter type public.concert_event_type add value if not exists 'ownership_transferred';
alter type public.concert_event_type add value if not exists 'comment_added';
alter type public.concert_event_type add value if not exists 'comment_updated';
alter type public.concert_event_type add value if not exists 'comment_deleted';
