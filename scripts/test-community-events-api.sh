#!/usr/bin/env bash
# shellcheck disable=SC2016 # jq variables intentionally remain single-quoted.
set -euo pipefail

command -v jq >/dev/null || {
  echo "jq is required for the community-event API test." >&2
  exit 1
}

api_url=""
publishable_key=""
while IFS='=' read -r key quoted_value; do
  value="${quoted_value%\"}"
  value="${value#\"}"
  case "$key" in
    API_URL) api_url="$value" ;;
    PUBLISHABLE_KEY) publishable_key="$value" ;;
  esac
done < <(supabase status -o env)

if [[ "$api_url" != http://127.0.0.1:* || -z "$publishable_key" ]]; then
  echo "Community-event integration tests run only against Local Supabase. Run 'make local-db-reset'." >&2
  exit 1
fi

sign_in() {
  curl --silent --show-error --fail "$api_url/auth/v1/token?grant_type=password" \
    -H "apikey: $publishable_key" \
    -H 'Content-Type: application/json' \
    --data "{\"email\":\"$1@tunedin.local\",\"password\":\"tunedIn-local-seeded-account\"}" \
    | jq -er '.access_token'
}

rpc() {
  local access_token="$1"
  local function_name="$2"
  local payload="$3"
  curl --silent --show-error --fail \
    -X POST "$api_url/rest/v1/rpc/$function_name" \
    -H "apikey: $publishable_key" \
    -H "Authorization: Bearer $access_token" \
    -H 'Content-Type: application/json' \
    --data "$payload"
}

assert_json() {
  local label="$1"
  local document="$2"
  shift 2
  if ! jq -e "$@" >/dev/null <<<"$document"; then
    echo "Community-event integration check failed: $label." >&2
    exit 1
  fi
}

listener_token="$(sign_in listener)"
riley_token="$(sign_in riley)"

listener_id="d1000000-0000-0000-0000-000000000001"
riley_id="d1000000-0000-0000-0000-000000000005"
upcoming_event_id="d4000000-0000-0000-0000-000000000001"
past_event_id="d4000000-0000-0000-0000-000000000002"
listener_diary_id="d4500000-0000-0000-0000-000000000001"

search_results="$(rpc "$listener_token" search_catalog_events \
  '{"p_query":"Local Signals","p_filters":{},"p_limit":20}')"
assert_json "search returns the shared upcoming event" \
  "$search_results" --arg event_id "$upcoming_event_id" \
  'any(.[]; .event_id == $event_id and .lifecycle == "scheduled")'
assert_json "search returns past events for an explicit Upcoming/Past split" \
  "$search_results" 'any(.[]; .lifecycle == "completed")'

event_detail="$(rpc "$listener_token" get_catalog_event_detail \
  "{\"p_event_id\":\"$upcoming_event_id\"}")"
assert_json "event detail is the community-owned shared object" \
  "$event_detail" \
  --arg event_id "$upcoming_event_id" \
  '.[0].event_id == $event_id and .[0].source_label == "Community added" and .[0].listing == "listed"'

duplicate_result="$(rpc "$listener_token" create_catalog_event \
  '{"p_artists":[{"catalog_artist_id":"d3000000-0000-0000-0000-000000000102","is_primary":true}],"p_catalog_place_id":"d3000000-0000-0000-0000-000000000103","p_event_date":"2026-09-18","p_catalog_tour_id":"d3000000-0000-0000-0000-000000000105","p_starts_at":"2026-09-19T03:00:00Z","p_time_zone_identifier":"America/Los_Angeles","p_listing":"listed"}')"
assert_json "exact event identity reuses the canonical row" \
  "$duplicate_result" \
  --arg event_id "$upcoming_event_id" \
  '.[0].event_id == $event_id and .[0].was_created == false'

invitation_result="$(rpc "$listener_token" send_catalog_event_invitations \
  "{\"p_event_id\":\"$upcoming_event_id\",\"p_recipient_ids\":[\"$riley_id\"]}")"
assert_json "the invitation request is accepted or already pending" \
  "$invitation_result" '.[0].sent_count == 0 or .[0].sent_count == 1'

pending_invitations="$(rpc "$riley_token" list_pending_catalog_event_invitations \
  '{"p_limit":20}')"
assert_json "the recipient session sees the invitation" \
  "$pending_invitations" \
  --arg event_id "$upcoming_event_id" \
  'any(.[]; .event_id == $event_id and .sender_relationship == "friends")'
invitation_id="$(jq -er --arg event_id "$upcoming_event_id" \
  '.[] | select(.event_id == $event_id) | .invitation_id' <<<"$pending_invitations")"

accepted_invitation="$(rpc "$riley_token" respond_catalog_event_invitation \
  "{\"p_invitation_id\":\"$invitation_id\",\"p_response\":\"accepted\",\"p_audience\":\"friends\"}")"
assert_json "acceptance adds the event to Going" \
  "$accepted_invitation" \
  --arg event_id "$upcoming_event_id" \
  '.[0].event_id == $event_id and .[0].status == "accepted"'

profile_going="$(rpc "$listener_token" list_catalog_profile_attendance \
  "{\"p_profile_id\":\"$riley_id\",\"p_state\":\"going\",\"p_limit\":20}")"
assert_json "the friend can see Going on the recipient profile" \
  "$profile_going" \
  --arg event_id "$upcoming_event_id" \
  'any(.[]; .event.event_id == $event_id and .status == "going" and .audience == "friends")'

root_post="$(rpc "$listener_token" create_catalog_event_post \
  "{\"p_event_id\":\"$upcoming_event_id\",\"p_body\":\"Repeatable Local journey post.\",\"p_audience\":\"friends\"}")"
root_post_id="$(jq -er '.[0].post_id' <<<"$root_post")"
reply_post="$(rpc "$riley_token" create_catalog_event_post \
  "{\"p_event_id\":\"$upcoming_event_id\",\"p_parent_post_id\":\"$root_post_id\",\"p_body\":\"Reply from the invited friend.\",\"p_audience\":\"friends\"}")"
reply_post_id="$(jq -er '.[0].post_id' <<<"$reply_post")"

conversation="$(rpc "$listener_token" list_catalog_event_posts \
  "{\"p_event_id\":\"$upcoming_event_id\",\"p_scope\":\"friends\",\"p_limit\":50}")"
assert_json "the shared conversation contains the cross-session reply" \
  "$conversation" \
  --arg post_id "$reply_post_id" --arg parent_id "$root_post_id" \
  'any(.[]; .id == $post_id and .parent_post_id == $parent_id and .author_relationship == "friends")'

activity="$(rpc "$listener_token" list_catalog_event_activity '{"p_limit":50}')"
assert_json "the feed projects the friend's accepted invitation" \
  "$activity" \
  --arg actor_id "$riley_id" --arg event_id "$upcoming_event_id" \
  'any(.[]; .actor_id == $actor_id and .action == "invitation_accepted" and .event.event_id == $event_id)'
assert_json "the feed projects the friend's reply" \
  "$activity" \
  --arg subject_id "$reply_post_id" \
  'any(.[]; .subject_id == $subject_id and .action == "event_replied")'

event_diaries="$(rpc "$riley_token" list_catalog_event_diaries \
  "{\"p_event_id\":\"$past_event_id\",\"p_scope\":\"all\",\"p_limit\":30}")"
assert_json "one global event exposes separate visible personal diaries" \
  "$event_diaries" \
  --arg listener_id "$listener_id" --arg riley_id "$riley_id" \
  'length >= 2 and any(.[]; .author_id == $listener_id and .audience == "friends") and all(.[]; .author_id != $riley_id)'

private_went="$(rpc "$riley_token" list_catalog_profile_attendance \
  "{\"p_profile_id\":\"$listener_id\",\"p_state\":\"went\",\"p_limit\":20}")"
assert_json "the owner's private Went record remains hidden" "$private_went" 'length == 0'

profile_history="$(rpc "$riley_token" list_catalog_profile_event_history \
  "{\"p_profile_id\":\"$listener_id\",\"p_limit\":20}")"
assert_json "the independently shared diary remains visible on profile history" \
  "$profile_history" \
  --arg diary_id "$listener_diary_id" \
  'any(.[]; .history_kind == "diary" and .diary.diary_id == $diary_id)'

created_comment="$(rpc "$riley_token" create_concert_comment \
  "{\"p_concert_id\":\"$listener_diary_id\",\"p_body\":\"Verified from the second Local session.\"}")"
comment_id="$(jq -er 'if type == "array" then .[0].id else .id end' <<<"$created_comment")"
diary_comments="$(rpc "$listener_token" list_concert_comments \
  "{\"p_concert_id\":\"$listener_diary_id\",\"p_limit\":30}")"
assert_json "the diary owner sees the friend's comment" \
  "$diary_comments" \
  --arg comment_id "$comment_id" --arg riley_id "$riley_id" \
  'any(.[]; .id == $comment_id and .author_id == $riley_id)'

printf 'Authenticated community-event integration passed: search/dedup, invitation/Going, conversation/feed, and diary privacy/comments.\n'
