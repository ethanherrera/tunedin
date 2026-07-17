#!/usr/bin/env bash
# shellcheck disable=SC2016 # jq variables intentionally remain single-quoted.
set -euo pipefail

command -v jq >/dev/null || { echo "jq is required for the community-event API test." >&2; exit 1; }

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
    -H "apikey: $publishable_key" -H 'Content-Type: application/json' \
    --data "{\"email\":\"$1@tunedin.local\",\"password\":\"tunedIn-local-seeded-account\"}" \
    | jq -er '.access_token'
}

rpc() {
  curl --silent --show-error --fail -X POST "$api_url/rest/v1/rpc/$2" \
    -H "apikey: $publishable_key" -H "Authorization: Bearer $1" \
    -H 'Content-Type: application/json' --data "$3"
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
listener_post_id="d4500000-0000-0000-0000-000000000001"

search_results="$(rpc "$listener_token" search_catalog_events \
  '{"p_query":"Local Signals","p_filters":{},"p_limit":20}')"
assert_json "search returns both upcoming and past shared events" "$search_results" \
  --arg upcoming "$upcoming_event_id" --arg past "$past_event_id" \
  'any(.[]; .event_id == $upcoming and .lifecycle == "scheduled") and any(.[]; .event_id == $past and .lifecycle == "completed")'

event_detail="$(rpc "$listener_token" get_catalog_event_detail \
  "{\"p_event_id\":\"$upcoming_event_id\"}")"
assert_json "event detail remains one community-owned source of truth" "$event_detail" \
  --arg event_id "$upcoming_event_id" \
  '.[0].event_id == $event_id and .[0].source_label == "Community added" and .[0].listing == "listed"'

duplicate_result="$(rpc "$listener_token" create_catalog_event \
  '{"p_artists":[{"catalog_artist_id":"d3000000-0000-0000-0000-000000000102","is_primary":true}],"p_catalog_place_id":"d3000000-0000-0000-0000-000000000103","p_event_date":"2026-09-18","p_catalog_tour_id":"d3000000-0000-0000-0000-000000000105","p_starts_at":"2026-09-19T03:00:00Z","p_time_zone_identifier":"America/Los_Angeles","p_listing":"listed"}')"
assert_json "exact event identity reuses the canonical row" "$duplicate_result" \
  --arg event_id "$upcoming_event_id" '.[0].event_id == $event_id and .[0].was_created == false'

rpc "$listener_token" send_catalog_event_invitations \
  "{\"p_event_id\":\"$upcoming_event_id\",\"p_recipient_ids\":[\"$riley_id\"]}" >/dev/null
pending_invitations="$(rpc "$riley_token" list_pending_catalog_event_invitations '{"p_limit":20}')"
invitation_id="$(jq -er --arg event_id "$upcoming_event_id" \
  '.[] | select(.event_id == $event_id) | .invitation_id' <<<"$pending_invitations")"
accepted_invitation="$(rpc "$riley_token" respond_catalog_event_invitation \
  "{\"p_invitation_id\":\"$invitation_id\",\"p_response\":\"accepted\",\"p_audience\":\"friends\"}")"
assert_json "accepting an invitation adds Going" "$accepted_invitation" \
  --arg event_id "$upcoming_event_id" '.[0].event_id == $event_id and .[0].status == "accepted"'

profile_going="$(rpc "$listener_token" list_catalog_profile_attendance \
  "{\"p_profile_id\":\"$riley_id\",\"p_state\":\"going\",\"p_limit\":20}")"
assert_json "a friend sees Going on the recipient profile" "$profile_going" \
  --arg event_id "$upcoming_event_id" 'any(.[]; .event.event_id == $event_id and .status == "going")'

root_comment="$(rpc "$listener_token" create_event_comment \
  "{\"p_event_id\":\"$upcoming_event_id\",\"p_body\":\"Repeatable Local journey comment.\",\"p_audience\":\"friends\"}")"
root_comment_id="$(jq -er '.[0].comment_id' <<<"$root_comment")"
reply_comment="$(rpc "$riley_token" create_event_comment \
  "{\"p_event_id\":\"$upcoming_event_id\",\"p_parent_comment_id\":\"$root_comment_id\",\"p_body\":\"Reply from the invited friend.\",\"p_audience\":\"friends\"}")"
reply_comment_id="$(jq -er '.[0].comment_id' <<<"$reply_comment")"
conversation="$(rpc "$listener_token" list_event_comments \
  "{\"p_event_id\":\"$upcoming_event_id\",\"p_scope\":\"friends\",\"p_limit\":50}")"
assert_json "the event conversation contains the cross-session reply" "$conversation" \
  --arg reply "$reply_comment_id" --arg parent "$root_comment_id" \
  'any(.[]; .id == $reply and .parent_comment_id == $parent and .author_relationship == "friends")'

event_posts="$(rpc "$riley_token" list_event_posts \
  "{\"p_event_id\":\"$past_event_id\",\"p_scope\":\"all\",\"p_limit\":30}")"
assert_json "one shared event exposes independent visible Posts" "$event_posts" \
  --arg listener "$listener_id" --arg riley "$riley_id" \
  'length >= 2 and any(.[]; .author_id == $listener and .audience == "friends") and all(.[]; .author_id != $riley)'

private_went="$(rpc "$riley_token" list_catalog_profile_attendance \
  "{\"p_profile_id\":\"$listener_id\",\"p_state\":\"went\",\"p_limit\":20}")"
assert_json "private Went stays hidden while the shared Post remains visible" "$private_went" 'length == 0'

profile_history="$(rpc "$riley_token" list_catalog_profile_event_history \
  "{\"p_profile_id\":\"$listener_id\",\"p_limit\":20}")"
assert_json "the independently shared Post appears in profile history" "$profile_history" \
  --arg post_id "$listener_post_id" \
  'any(.[]; .history_kind == "post" and .post.post_id == $post_id)'

created_post_comment="$(rpc "$riley_token" create_post_comment \
  "{\"p_post_id\":\"$listener_post_id\",\"p_body\":\"Verified from the second Local session.\"}")"
post_comment_id="$(jq -er '.[0].id' <<<"$created_post_comment")"
post_comments="$(rpc "$listener_token" list_post_comments \
  "{\"p_post_id\":\"$listener_post_id\",\"p_limit\":30}")"
assert_json "the Post owner sees a friend's comment" "$post_comments" \
  --arg comment_id "$post_comment_id" --arg riley "$riley_id" \
  'any(.[]; .id == $comment_id and .author_id == $riley)'

activity="$(rpc "$listener_token" list_catalog_event_activity '{"p_limit":50}')"
assert_json "the feed uses the Comment action vocabulary" "$activity" \
  --arg subject "$reply_comment_id" \
  'any(.[]; .subject_id == $subject and .action == "event_comment_replied")'

printf 'Authenticated community-event integration passed: discovery, invitations/Going, event Comments, Posts, profile history, and Post comments.\n'
