create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  username text unique,
  display_name text,
  onboarding_completed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint profiles_username_normalized_check check (
    username is null or username = lower(username)
  ),
  constraint profiles_username_format_check check (
    username is null or username ~ '^[a-z0-9][a-z0-9_]{1,22}[a-z0-9]$'
  ),
  constraint profiles_display_name_check check (
    display_name is null or (
      char_length(display_name) between 1 and 50
      and display_name = btrim(display_name)
      and display_name !~ '[[:cntrl:]]'
    )
  ),
  constraint profiles_onboarding_completion_check check (
    (onboarding_completed_at is null and username is null and display_name is null)
    or (
      onboarding_completed_at is not null
      and username is not null
      and display_name is not null
    )
  )
);

create function public.set_profile_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger set_profiles_updated_at
before update on public.profiles
for each row
execute function public.set_profile_updated_at();

create function public.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id)
  values (new.id);

  return new;
end;
$$;

create trigger on_auth_user_created
after insert on auth.users
for each row
execute function public.handle_new_auth_user();

create function public.normalize_username(value text)
returns text
language sql
immutable
set search_path = ''
as $$
  select lower(btrim(value));
$$;

create function public.normalize_display_name(value text)
returns text
language sql
immutable
set search_path = ''
as $$
  select regexp_replace(btrim(value), '[[:space:]]+', ' ', 'g');
$$;

create function public.is_valid_username(value text)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select value ~ '^[a-z0-9][a-z0-9_]{1,22}[a-z0-9]$';
$$;

create function public.is_username_available(p_username text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  normalized_username text;
begin
  if auth.uid() is null then
    raise exception 'Authentication is required to check a username'
      using errcode = '28000';
  end if;

  normalized_username := public.normalize_username(p_username);

  if normalized_username is null or not public.is_valid_username(normalized_username) then
    return false;
  end if;

  return not exists (
    select 1
    from public.profiles
    where username = normalized_username
  );
end;
$$;

create function public.complete_onboarding(
  p_username text,
  p_display_name text
)
returns public.profiles
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := auth.uid();
  normalized_username text := public.normalize_username(p_username);
  normalized_display_name text := public.normalize_display_name(p_display_name);
  profile public.profiles%rowtype;
begin
  if caller_id is null then
    raise exception 'Authentication is required to complete onboarding'
      using errcode = '28000';
  end if;

  if normalized_username is null or not public.is_valid_username(normalized_username) then
    raise exception 'Username must be 3-24 lowercase letters, numbers, or underscores and start and end with a letter or number'
      using errcode = '22023';
  end if;

  if p_display_name is null
    or p_display_name ~ '[[:cntrl:]]'
    or normalized_display_name is null
    or char_length(normalized_display_name) not between 1 and 50
  then
    raise exception 'Display name must be 1-50 characters and cannot contain control characters'
      using errcode = '22023';
  end if;

  select *
  into profile
  from public.profiles
  where id = caller_id
  for update;

  if not found then
    raise exception 'Profile creation is incomplete for this account'
      using errcode = 'P0001';
  end if;

  if profile.onboarding_completed_at is not null then
    if profile.username = normalized_username
      and profile.display_name = normalized_display_name
    then
      return profile;
    end if;

    raise exception 'Profile onboarding is already complete'
      using errcode = 'P0001';
  end if;

  update public.profiles
  set
    username = normalized_username,
    display_name = normalized_display_name,
    onboarding_completed_at = now()
  where id = caller_id
  returning * into profile;

  return profile;
end;
$$;

alter table public.profiles enable row level security;

create policy "profiles_select_own"
on public.profiles
for select
to authenticated
using ((select auth.uid()) = id);

revoke all on table public.profiles from anon, authenticated;
grant select on table public.profiles to authenticated;

revoke all on function public.set_profile_updated_at() from public;
revoke all on function public.handle_new_auth_user() from public;
revoke all on function public.normalize_username(text) from public;
revoke all on function public.normalize_display_name(text) from public;
revoke all on function public.is_valid_username(text) from public;
revoke all on function public.is_username_available(text) from public;
revoke all on function public.complete_onboarding(text, text) from public;

grant execute on function public.is_username_available(text) to authenticated;
grant execute on function public.complete_onboarding(text, text) to authenticated;
