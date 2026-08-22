#!/usr/bin/env bash
# Linear client for the God runtime. Deterministic, testable without Claude.
#
# The dedup protocol lives here, not in a prompt: search before every write.
# Headless `claude -p` runs often lack interactively-authenticated MCP servers,
# so this talks to the Linear GraphQL API directly.
#
# Requires: LINEAR_API_KEY, jq. Team is set by LINEAR_TEAM_ID.
set -uo pipefail

API="https://api.linear.app/graphql"
: "${LINEAR_API_KEY:?set LINEAR_API_KEY}"
: "${LINEAR_TEAM_ID:?set LINEAR_TEAM_ID (the God Agents team)}"

# gql <query> [variables-json] — posts a GraphQL request, prints the JSON response.
gql() {
  local query="$1" vars="${2:-{\}}"
  jq -nc --arg q "$query" --argjson v "$vars" '{query:$q, variables:$v}' \
    | curl -sS -X POST "$API" \
        -H "Authorization: $LINEAR_API_KEY" \
        -H "Content-Type: application/json" \
        --data @-
}

# search <fingerprint> — prints "<issue-id> <state-type>" if an issue carries
# this fingerprint, nothing otherwise. State type is one of: triage, backlog,
# unstarted, started, completed, canceled.
cmd_search() {
  local fp="$1"
  gql 'query($q:String!){ searchIssues(term:$q, first:10){ nodes{ id identifier description state{ type } } } }' \
      "$(jq -nc --arg q "$fp" '{q:$q}')" \
    | jq -r --arg fp "$fp" '
        .data.searchIssues.nodes[]?
        | select(.description != null and (.description | contains($fp)))
        | "\(.id) \(.state.type)"' \
    | head -1
}

# create <title> <body-file> [label...] — creates an issue in the God team.
cmd_create() {
  local title="$1" body_file="$2"; shift 2
  local labels; labels=$(printf '%s\n' "$@" | jq -R . | jq -sc .)
  gql 'mutation($t:String!,$d:String!,$team:String!){ issueCreate(input:{title:$t, description:$d, teamId:$team}){ success issue{ identifier url } } }' \
      "$(jq -nc --arg t "$title" --rawfile d "$body_file" --arg team "$LINEAR_TEAM_ID" \
          '{t:$t, d:$d, team:$team}')" \
    | jq -r '.data.issueCreate.issue | "created \(.identifier) \(.url)"'
  [ -n "${labels}" ] || true   # labels applied by workflow rules; see README
}

# comment <issue-id> <text> — adds a recurrence comment to an existing issue.
cmd_comment() {
  gql 'mutation($i:String!,$b:String!){ commentCreate(input:{issueId:$i, body:$b}){ success } }' \
      "$(jq -nc --arg i "$1" --arg b "$2" '{i:$i, b:$b}')" \
    | jq -r 'if .data.commentCreate.success then "commented" else "comment failed" end'
}

# reopen <issue-id> — moves a closed issue back to an unstarted state.
cmd_reopen() {
  local state
  state=$(gql 'query($team:String!){ workflowStates(filter:{team:{id:{eq:$team}}}){ nodes{ id type } } }' \
              "$(jq -nc --arg team "$LINEAR_TEAM_ID" '{team:$team}')" \
          | jq -r '[.data.workflowStates.nodes[] | select(.type=="unstarted")][0].id')
  [ -n "$state" ] && [ "$state" != "null" ] || { echo "no unstarted state found" >&2; return 1; }
  gql 'mutation($i:String!,$s:String!){ issueUpdate(id:$i, input:{stateId:$s}){ success } }' \
      "$(jq -nc --arg i "$1" --arg s "$state" '{i:$i, s:$s}')" \
    | jq -r 'if .data.issueUpdate.success then "reopened" else "reopen failed" end'
}

# file <fingerprint> <title> <body-file> — the full write protocol in one call.
# This is what prompts should use: it cannot skip the search step.
cmd_file() {
  local fp="$1" title="$2" body="$3"
  local hit id state
  hit=$(cmd_search "$fp")
  if [ -n "$hit" ]; then
    id=${hit%% *}; state=${hit##* }
    case "$state" in
      completed|canceled)
        cmd_reopen "$id"
        cmd_comment "$id" "Refound by the God runtime on $(date +%F). Regression." ;;
      *)
        cmd_comment "$id" "Recurred on $(date +%F). Still open — not filing a duplicate." ;;
    esac
    return 0
  fi
  cmd_create "$title" "$body"
}

# list-scout-titles — titles of open scout issues, for conceptual dedup.
cmd_list_scout_titles() {
  gql 'query($team:ID!){ issues(filter:{team:{id:{eq:$team}}, state:{type:{nin:["completed","canceled"]}}}, first:100){ nodes{ title } } }' \
      "$(jq -nc --arg team "$LINEAR_TEAM_ID" '{team:$team}')" \
    | jq -r '.data.issues.nodes[]?.title | select(startswith("[god-scout]"))'
}

# runner-failure <message> <log-file> — files a runner failure with a log tail.
cmd_runner_failure() {
  local msg="$1" log="${2:-}" tmp
  tmp=$(mktemp)
  {
    echo "The God runtime failed on $(date +%F)."
    echo; echo "**Message:** $msg"; echo
    if [ -n "$log" ] && [ -f "$log" ]; then
      echo '```'; tail -40 "$log"; echo '```'
    fi
    echo; echo "<!-- god-fingerprint: runner:failure:$(date +%F) -->"
  } > "$tmp"
  cmd_create "[god-runner] $msg" "$tmp"
  rm -f "$tmp"
}

case "${1:-}" in
  search)            shift; cmd_search "$@" ;;
  create)            shift; cmd_create "$@" ;;
  comment)           shift; cmd_comment "$@" ;;
  reopen)            shift; cmd_reopen "$@" ;;
  file)              shift; cmd_file "$@" ;;
  list-scout-titles) shift; cmd_list_scout_titles "$@" ;;
  runner-failure)    shift; cmd_runner_failure "$@" ;;
  *) echo "usage: client.sh {search|create|comment|reopen|file|list-scout-titles|runner-failure} ..." >&2; exit 1 ;;
esac
