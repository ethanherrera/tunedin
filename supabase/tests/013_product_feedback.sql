begin;

select plan(13);

set local role authenticated;
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claim.sub', 'd1000000-0000-0000-0000-000000000001', true);

select lives_ok(
  $$select public.submit_product_feedback(
    'bug',
    'The album retry stayed visible after the upload finished.',
    'settings',
    'development',
    '0.1.0',
    '42',
    '0123456789ab'
  )$$,
  'an authenticated profile can submit voluntary feedback'
);

select throws_ok(
  $$select count(*) from public.product_feedback$$,
  '42501',
  null,
  'feedback rows are not readable by clients'
);

select throws_ok(
  $$insert into public.product_feedback (
    submitter_id,
    category,
    message,
    originating_screen,
    app_environment,
    release_version,
    build_number,
    git_sha
  ) values (
    'd1000000-0000-0000-0000-000000000001',
    'idea',
    'Direct insert',
    'settings',
    'development',
    '0.1.0',
    '42',
    '0123456789ab'
  )$$,
  '42501',
  null,
  'authenticated clients cannot bypass the submission RPC'
);

select throws_ok(
  $$select public.submit_product_feedback(
    'unsupported', 'Hello', 'settings', 'development', '0.1.0', '42', '0123456789ab'
  )$$,
  '22023',
  'Unsupported feedback category',
  'unknown feedback categories are rejected'
);

select throws_ok(
  $$select public.submit_product_feedback(
    'bug', '   ', 'settings', 'development', '0.1.0', '42', '0123456789ab'
  )$$,
  '22023',
  'Feedback must contain between 1 and 2000 characters',
  'blank feedback is rejected'
);

select throws_ok(
  $$select public.submit_product_feedback(
    'bug', repeat('x', 2001), 'settings', 'development', '0.1.0', '42', '0123456789ab'
  )$$,
  '22023',
  'Feedback must contain between 1 and 2000 characters',
  'oversized feedback is rejected'
);

select throws_ok(
  $$select public.submit_product_feedback(
    'bug', 'Hello', 'unknown', 'development', '0.1.0', '42', '0123456789ab'
  )$$,
  '23514',
  null,
  'unknown originating screens are rejected by a constraint'
);

select throws_ok(
  $$select public.submit_product_feedback(
    'bug', 'Hello', 'settings', 'preview', '0.1.0', '42', '0123456789ab'
  )$$,
  '23514',
  null,
  'unknown app environments are rejected by a constraint'
);

reset role;

select is(
  (select count(*) from public.product_feedback),
  1::bigint,
  'the successful feedback row exists for operators'
);

select is(
  (select submitter_id from public.product_feedback limit 1),
  'd1000000-0000-0000-0000-000000000001'::uuid,
  'the RPC binds the authenticated caller as submitter'
);

select ok(
  (select expires_at <= created_at + interval '90 days' from public.product_feedback limit 1),
  'feedback cannot outlive the 90-day retention window'
);

update public.product_feedback
set expires_at = statement_timestamp() - interval '1 second';

select is(
  private.purge_expired_product_feedback(),
  1::bigint,
  'the cleanup function deletes expired feedback'
);

reset role;
set local role anon;
select set_config('request.jwt.claim.role', 'anon', true);
select set_config('request.jwt.claim.sub', '', true);

select throws_ok(
  $$select public.submit_product_feedback(
    'bug', 'Hello', 'settings', 'development', '0.1.0', '42', '0123456789ab'
  )$$,
  '42501',
  null,
  'anonymous callers cannot submit feedback'
);

select * from finish();
rollback;
