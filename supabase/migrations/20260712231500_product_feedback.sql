create type public.product_feedback_category as enum ('bug', 'idea', 'other');

create table public.product_feedback (
  id uuid primary key default gen_random_uuid(),
  submitter_id uuid not null references public.profiles(id) on delete cascade,
  category public.product_feedback_category not null,
  message text not null,
  originating_screen text not null,
  app_environment text not null,
  release_version text not null,
  build_number text not null,
  git_sha text not null,
  created_at timestamptz not null default statement_timestamp(),
  expires_at timestamptz not null default (statement_timestamp() + interval '90 days'),
  constraint product_feedback_message_length check (
    char_length(btrim(message)) between 1 and 2000
  ),
  constraint product_feedback_originating_screen check (
    originating_screen in ('settings', 'profile')
  ),
  constraint product_feedback_environment check (
    app_environment in ('development', 'staging', 'production')
  ),
  constraint product_feedback_release_length check (
    char_length(release_version) between 1 and 40
    and char_length(build_number) between 1 and 40
    and char_length(git_sha) between 1 and 40
  ),
  constraint product_feedback_retention_window check (
    expires_at <= created_at + interval '90 days'
  )
);

alter table public.product_feedback enable row level security;

revoke all on table public.product_feedback from public, anon, authenticated;

create function public.submit_product_feedback(
  p_category text,
  p_message text,
  p_originating_screen text,
  p_app_environment text,
  p_release_version text,
  p_build_number text,
  p_git_sha text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_caller_id uuid := auth.uid();
  v_feedback_id uuid;
  v_message text := btrim(coalesce(p_message, ''));
begin
  if v_caller_id is null then
    raise exception 'Authentication required'
      using errcode = '42501';
  end if;

  if not exists (
    select 1
    from public.profiles
    where id = v_caller_id
  ) then
    raise exception 'Profile required'
      using errcode = '42501';
  end if;

  if p_category not in ('bug', 'idea', 'other') then
    raise exception 'Unsupported feedback category'
      using errcode = '22023';
  end if;

  if char_length(v_message) not between 1 and 2000 then
    raise exception 'Feedback must contain between 1 and 2000 characters'
      using errcode = '22023';
  end if;

  insert into public.product_feedback (
    submitter_id,
    category,
    message,
    originating_screen,
    app_environment,
    release_version,
    build_number,
    git_sha
  )
  values (
    v_caller_id,
    p_category::public.product_feedback_category,
    v_message,
    lower(p_originating_screen),
    lower(p_app_environment),
    p_release_version,
    p_build_number,
    lower(p_git_sha)
  )
  returning id into v_feedback_id;

  return v_feedback_id;
end;
$$;

revoke all on function public.submit_product_feedback(
  text,
  text,
  text,
  text,
  text,
  text,
  text
) from public, anon;

grant execute on function public.submit_product_feedback(
  text,
  text,
  text,
  text,
  text,
  text,
  text
) to authenticated;

create function private.purge_expired_product_feedback()
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_deleted bigint;
begin
  delete from public.product_feedback
  where expires_at <= statement_timestamp();

  get diagnostics v_deleted = row_count;
  return v_deleted;
end;
$$;

revoke all on function private.purge_expired_product_feedback() from public, anon, authenticated;

create extension if not exists pg_cron with schema extensions;

do $$
declare
  v_job_id bigint;
begin
  select jobid
  into v_job_id
  from cron.job
  where jobname = 'purge-expired-product-feedback';

  if v_job_id is not null then
    perform cron.unschedule(v_job_id);
  end if;

  perform cron.schedule(
    'purge-expired-product-feedback',
    '17 3 * * *',
    'select private.purge_expired_product_feedback()'
  );
end;
$$;

comment on table public.product_feedback is
  'Voluntary in-app feedback. Clients may submit through a hardened RPC but cannot read responses.';

comment on function private.purge_expired_product_feedback() is
  'Permanently deletes voluntary feedback at the enforced 90-day retention boundary.';
