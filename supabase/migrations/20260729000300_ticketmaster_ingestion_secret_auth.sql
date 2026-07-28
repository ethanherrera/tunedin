-- Supabase service-to-service calls use a new secret API key in the apikey
-- header. The Edge Function validates that exact key after the legacy gateway
-- JWT check is disabled.

create or replace function private.invoke_ticketmaster_ingestion_worker()
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_project_url text;
  v_operator_key text;
  v_request_id bigint;
begin
  begin
    execute $query$
      select
        max(decrypted_secret) filter (
          where name = 'ticketmaster_ingestion_project_url'
        ),
        max(decrypted_secret) filter (
          where name = 'ticketmaster_ingestion_operator_key'
        )
      from vault.decrypted_secrets
    $query$
    into v_project_url, v_operator_key;
  exception when undefined_table or invalid_schema_name then
    return null;
  end;

  if v_project_url is null
    or v_project_url !~ '^https://[a-z]+[.]supabase[.]co$'
    or v_operator_key is null
    or v_operator_key !~ '^sb_secret_[A-Za-z0-9_-]+$'
    or char_length(v_operator_key) > 512
  then
    return null;
  end if;

  select net.http_post(
    url := v_project_url || '/functions/v1/ticketmaster-ingestion',
    headers := jsonb_build_object(
      'apikey', v_operator_key,
      'Content-Type', 'application/json'
    ),
    body := '{"operation":"resume"}'::jsonb,
    timeout_milliseconds := 5000
  ) into v_request_id;
  return v_request_id;
end;
$$;
