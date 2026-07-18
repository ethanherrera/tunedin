# Community Event Integrity Operations

## Purpose

Review and execute the exceptional operations that repair the shared concert
catalog without deleting a person's Going/Went history, diary, review, photos,
comments, or immutable activity. This runbook covers duplicate-event merge,
event tombstone, legal/safety/privacy diary detach, and diary relink recovery.

These are human-reviewed operations, never scheduled maintenance. Ordinary event
corrections continue through the creator correction flow.

## Prerequisites and permissions

- The migration containing the integrity operation has passed
  `make backend-verify`, been reviewed and merged to `main`, and reached the
  intended environment through its protected deployment workflow.
- The operator has a completed tunedIn profile and a freshly issued access token
  whose protected `app_metadata.catalog_event_operator` claim is `true`.
- A second human has reviewed the source event, target event, reason code, merge
  conflict counts, and the expected event versions.
- `curl` and `jq` are installed. Audit verification also requires `psql` and a
  temporary environment-specific database URL.
- Keep `SUPABASE_SERVICE_ROLE_KEY`, `SUPABASE_ANON_KEY`, `SUPABASE_DB_URL`, and access tokens only in
  the current shell or an approved secret manager. Never paste them into issues,
  PRs, logs, source files, or command history.

The supported reason codes are intentionally fixed:

- merge: `duplicate_event`;
- tombstone: `invalid_event`, `legal_request`, or `safety`;
- diary detach: `legal_request`, `safety`, or `privacy_request`;
- diary relink: `incorrect_association` or `recovery`.

## One-time operator claim

Set these values from the protected environment and identify the completed
profile that will operate the RPCs:

```sh
export SUPABASE_URL='https://PROJECT_REF.supabase.co'
export SUPABASE_ANON_KEY='...'
export SUPABASE_SERVICE_ROLE_KEY='...'
export OPERATOR_PROFILE_ID='00000000-0000-0000-0000-000000000000'
```

Fetch the Auth user, preserve all existing app metadata, and add only the
operator claim:

```sh
OPERATOR_USER=$(curl --fail-with-body --silent --show-error \
  "$SUPABASE_URL/auth/v1/admin/users/$OPERATOR_PROFILE_ID" \
  -H "apikey: $SUPABASE_SERVICE_ROLE_KEY" \
  -H "Authorization: Bearer $SUPABASE_SERVICE_ROLE_KEY")

OPERATOR_UPDATE=$(jq -cn \
  --argjson metadata "$(jq '.app_metadata // {}' <<<"$OPERATOR_USER")" \
  '{app_metadata: ($metadata + {catalog_event_operator: true})}')

curl --fail-with-body --silent --show-error \
  -X PUT "$SUPABASE_URL/auth/v1/admin/users/$OPERATOR_PROFILE_ID" \
  -H "apikey: $SUPABASE_SERVICE_ROLE_KEY" \
  -H "Authorization: Bearer $SUPABASE_SERVICE_ROLE_KEY" \
  -H 'Content-Type: application/json' \
  --data "$OPERATOR_UPDATE" | jq '{id, app_metadata}'

unset OPERATOR_USER OPERATOR_UPDATE
```

The operator must sign in again or refresh their session before the new claim is
present. Export only the resulting short-lived operator access token:

```sh
export OPERATOR_ACCESS_TOKEN='...'
```

## Review a duplicate merge

Never call the merge RPC before reviewing its bounded conflict report.

```sh
export SOURCE_EVENT_ID='00000000-0000-0000-0000-000000000000'
export TARGET_EVENT_ID='00000000-0000-0000-0000-000000000000'

MERGE_REVIEW=$(curl --fail-with-body --silent --show-error \
  "$SUPABASE_URL/rest/v1/rpc/review_catalog_event_merge" \
  -H "apikey: $SUPABASE_ANON_KEY" \
  -H "Authorization: Bearer $OPERATOR_ACCESS_TOKEN" \
  -H 'Content-Type: application/json' \
  --data "$(jq -cn \
    --arg source "$SOURCE_EVENT_ID" \
    --arg target "$TARGET_EVENT_ID" \
    '{p_source_event_id: $source, p_target_event_id: $target}')")

jq . <<<"$MERGE_REVIEW"
```

Expected result: one row with source and target versions, dependent-record
counts, and `can_merge: true`. Duplicate attendance is safe: the canonical row
remains effective and the other stable row is retained with an explicit
supersession link. If `duplicate_diary_count` is nonzero or `can_merge` is false,
stop. The system will not guess between two diaries owned by the same person.

After the second reviewer approves the exact output, execute with the reviewed
versions:

```sh
SOURCE_VERSION=$(jq -er '.[0].source_version' <<<"$MERGE_REVIEW")
TARGET_VERSION=$(jq -er '.[0].target_version' <<<"$MERGE_REVIEW")

curl --fail-with-body --silent --show-error \
  "$SUPABASE_URL/rest/v1/rpc/merge_catalog_events" \
  -H "apikey: $SUPABASE_ANON_KEY" \
  -H "Authorization: Bearer $OPERATOR_ACCESS_TOKEN" \
  -H 'Content-Type: application/json' \
  --data "$(jq -cn \
    --arg source "$SOURCE_EVENT_ID" \
    --arg target "$TARGET_EVENT_ID" \
    --argjson source_version "$SOURCE_VERSION" \
    --argjson target_version "$TARGET_VERSION" \
    '{
      p_source_event_id: $source,
      p_target_event_id: $target,
      p_expected_source_version: $source_version,
      p_expected_target_version: $target_version,
      p_reason_code: "duplicate_event"
    }')" | jq .
```

Expected result: the source becomes a redirect to the active target; the target
version advances; non-conflicting attendance, diaries, posts, and invitations
move; attendance conflicts remain recorded as superseded; content counts do not
decrease. Opening the source event ID returns target detail.

## Tombstone an invalid or unsafe event

Record the currently reviewed event version, then execute:

```sh
export EVENT_ID='00000000-0000-0000-0000-000000000000'
export EXPECTED_VERSION='1'
export TOMBSTONE_REASON='invalid_event'

curl --fail-with-body --silent --show-error \
  "$SUPABASE_URL/rest/v1/rpc/tombstone_catalog_event" \
  -H "apikey: $SUPABASE_ANON_KEY" \
  -H "Authorization: Bearer $OPERATOR_ACCESS_TOKEN" \
  -H 'Content-Type: application/json' \
  --data "$(jq -cn \
    --arg event "$EVENT_ID" \
    --argjson version "$EXPECTED_VERSION" \
    --arg reason "$TOMBSTONE_REASON" \
    '{p_event_id: $event, p_expected_version: $version, p_reason_code: $reason}')" \
  | jq .
```

Expected result: shared search and detail stop returning the event. Attendance
and diaries retain their foreign keys and remain visible through authorized
profile history using the durable event snapshot.

## Detach and relink a personal diary

Detach only for an approved legal, safety, or privacy case:

```sh
export DIARY_ID='00000000-0000-0000-0000-000000000000'
export DETACH_REASON='privacy_request'

curl --fail-with-body --silent --show-error \
  "$SUPABASE_URL/rest/v1/rpc/detach_personal_diary" \
  -H "apikey: $SUPABASE_ANON_KEY" \
  -H "Authorization: Bearer $OPERATOR_ACCESS_TOKEN" \
  -H 'Content-Type: application/json' \
  --data "$(jq -cn \
    --arg diary "$DIARY_ID" \
    --arg reason "$DETACH_REASON" \
    '{p_diary_id: $diary, p_reason_code: $reason}')" | jq .
```

Expected result: the event link is removed, the diary is forced private, and its
review/media/comments and original Went record remain. The owner's profile uses
the private audit snapshot so the memory is not lost.

To recover the same diary after a correct event is created, review the diary
owner, event snapshots, and target occurrence, then run:

```sh
export TARGET_EVENT_ID='00000000-0000-0000-0000-000000000000'

curl --fail-with-body --silent --show-error \
  "$SUPABASE_URL/rest/v1/rpc/relink_personal_diary" \
  -H "apikey: $SUPABASE_ANON_KEY" \
  -H "Authorization: Bearer $OPERATOR_ACCESS_TOKEN" \
  -H 'Content-Type: application/json' \
  --data "$(jq -cn \
    --arg diary "$DIARY_ID" \
    --arg target "$TARGET_EVENT_ID" \
    '{p_diary_id: $diary, p_target_event_id: $target, p_reason_code: "recovery"}')" \
  | jq .
```

Expected result: the stable diary ID and its content remain; its original Went
row moves when possible, or is retained as superseded when a canonical target
Went row already exists. The diary remains private until its owner deliberately
changes its audience through an approved product flow.

## Verification and audit

Verify the private audit and correction history with a temporary database URL:

```sh
psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -c \
  "select id, operation, operator_id, source_event_id, target_event_id, diary_id, reason_code, created_at
   from private.catalog_event_integrity_operations
   where source_event_id in ('$SOURCE_EVENT_ID', '$EVENT_ID')
      or target_event_id = '$TARGET_EVENT_ID'
      or diary_id = '$DIARY_ID'
   order by created_at desc;"

psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -c \
  "select event_id, previous_version, next_version, changed_by, created_at
   from private.catalog_event_revisions
   where event_id in ('$SOURCE_EVENT_ID', '$TARGET_EVENT_ID', '$EVENT_ID')
   order by created_at desc;"
```

Also verify from normal signed-in accounts: old merge links redirect, canonical
People and Memories counts are correct, tombstoned detail is unavailable, and
the owner can still open authorized profile history and diary content.

Audit locations are the two private tables above, the protected database
deployment workflow, Supabase Auth admin logs for claim changes, and the human
review record that approved the operation. Audit snapshots contain bounded
structural records and opaque IDs, not post/review text copied into notifications.

## Recovery and claim removal

Merge and tombstone are intentionally not self-service reversible. If either
target was wrong, stop further operations, preserve the audit IDs, and prepare a
new reviewed forward migration or narrowly scoped recovery RPC. Never delete the
audit, rewrite an applied migration, reset a hosted environment, or directly
edit dependent user rows.

Diary detach is recovered through `relink_personal_diary` as documented above.
If relink reports an existing target diary, stop and review both diaries with the
owner; do not merge their content automatically.

Remove the operator claim as soon as the operation window closes while preserving
all other app metadata:

```sh
OPERATOR_USER=$(curl --fail-with-body --silent --show-error \
  "$SUPABASE_URL/auth/v1/admin/users/$OPERATOR_PROFILE_ID" \
  -H "apikey: $SUPABASE_SERVICE_ROLE_KEY" \
  -H "Authorization: Bearer $SUPABASE_SERVICE_ROLE_KEY")

OPERATOR_UPDATE=$(jq -cn \
  --argjson metadata "$(jq '.app_metadata // {} | del(.catalog_event_operator)' <<<"$OPERATOR_USER")" \
  '{app_metadata: $metadata}')

curl --fail-with-body --silent --show-error \
  -X PUT "$SUPABASE_URL/auth/v1/admin/users/$OPERATOR_PROFILE_ID" \
  -H "apikey: $SUPABASE_SERVICE_ROLE_KEY" \
  -H "Authorization: Bearer $SUPABASE_SERVICE_ROLE_KEY" \
  -H 'Content-Type: application/json' \
  --data "$OPERATOR_UPDATE" | jq '{id, app_metadata}'

unset OPERATOR_USER OPERATOR_UPDATE OPERATOR_ACCESS_TOKEN
```

Existing access tokens can retain old claims until expiry. Revoke the operator's
sessions through the Auth admin surface when immediate removal is required.

## Cadence

Ad hoc only, after two-person review. During private beta, review integrity audit
rows monthly and after every operation. Do not automate merges, tombstones,
detaches, or relinks.
