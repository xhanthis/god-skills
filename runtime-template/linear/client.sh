#!/usr/bin/env bash
# Linear client for the God runtime. Deterministic, testable without Claude.
#
# The dedup protocol lives here, not in a prompt: search before every write.
# Headless `claude -p` runs often lack interactively-authenticated MCP servers,
# so this talks to the Linear GraphQL API directly.
#
# Agents write into the same workspace and team as human work, so attribution
# does the job a separate team would otherwise do:
#   - Authorship: writes are made as "God" via createAsUser, which requires an
#     OAuth app token authorized with actor=app. A personal API key cannot set
#     the author — see LINEAR_ACTOR_MODE below.
#   - Filtering: every issue carries a label (default "god") so agent findings
#     can be excluded from human views in one filter.
#
# Requires: LINEAR_API_KEY (or LINEAR_OAUTH_TOKEN), LINEAR_TEAM_ID, jq.
set -uo pipefail

# LINEAR_API_URL is overridable so the dedup protocol can be tested against a
# mock server without touching the real workspace. Defaults to Linear.
API="${LINEAR_API_URL:-https://api.linear.app/graphql}"
: "${LINEAR_API_KEY:?set LINEAR_API_KEY (personal key or OAuth app token)}"
: "${LINEAR_TEAM_ID:?set LINEAR_TEAM_ID}"

GOD_ACTOR_NAME="${GOD_ACTOR_NAME:-God}"
GOD_ACTOR_ICON="${GOD_ACTOR_ICON:-}"
GOD_LABEL="${GOD_LABEL:-god}"

# Authorship only works with an OAuth app token authorized with actor=app.
# Personal keys always attribute writes to the key's owner, and Linear rejects
# createAsUser on them — so detect the token type and only send it when valid.
# Override with LINEAR_ACTOR_MODE=oauth|key if the prefix heuristic is wrong.
detect_actor_mode() {
  if [ -n "${LINEAR_ACTOR_MODE:-}" ]; then
    printf '%s' "$LINEAR_ACTOR_MODE"
    return
  fi
  case "$LINEAR_API_KEY" in
    lin_oauth_*) printf 'oauth' ;;
    *) printf 'key' ;;
  esac
}
ACTOR_MODE=$(detect_actor_mode)

# actor_fields — the createAsUser/displayIconUrl pair as GraphQL input fragments,
# empty when the token cannot carry them.
actor_input() {
  [ "$ACTOR_MODE" = "oauth" ] || { printf ''; return; }
  printf ', createAsUser: $actor'
  [ -n "$GOD_ACTOR_ICON" ] && printf ', displayIconUrl: $icon'
}
actor_decl() {
  [ "$ACTOR_MODE" = "oauth" ] || { printf ''; return; }
  printf ', $actor: String'
  [ -n "$GOD_ACTOR_ICON" ] && printf ', $icon: String'
}
actor_vars() {
  if [ "$ACTOR_MODE" = "oauth" ]; then
    jq -nc --arg a "$GOD_ACTOR_NAME" --arg i "$GOD_ACTOR_ICON" \
      'if $i == "" then {actor:$a} else {actor:$a, icon:$i} end'
  else
    printf '{}'
  fi
}

# gql <query> [variables-json] — posts a GraphQL request, prints the JSON response.
gql() {
  local query="$1" vars="${2:-{\}}"
  jq -nc --arg q "$query" --argjson v "$vars" '{query:$q, variables:$v}' \
    | curl -sS -X POST "$API" \
        -H "Authorization: $LINEAR_API_KEY" \
        -H "Content-Type: application/json" \
        --data @-
}

# label_id <name> — finds the team's label by name, creating it when absent.
# In a shared team the label is what keeps agent findings out of human views,
# so it must exist rather than being silently skipped.
label_id() {
  local name="$1" id
  id=$(gql 'query($team:ID!){ issueLabels(filter:{team:{id:{eq:$team}}}, first:250){ nodes{ id name } } }' \
           "$(jq -nc --arg team "$LINEAR_TEAM_ID" '{team:$team}')" \
       | jq -r --arg n "$name" '[.data.issueLabels.nodes[]? | select(.name==$n)][0].id // empty')
  if [ -z "$id" ]; then
    id=$(gql 'mutation($n:String!,$team:String!){ issueLabelCreate(input:{name:$n, teamId:$team}){ success issueLabel{ id } } }' \
             "$(jq -nc --arg n "$name" --arg team "$LINEAR_TEAM_ID" '{n:$n, team:$team}')" \
         | jq -r '.data.issueLabelCreate.issueLabel.id // empty')
  fi
  printf '%s' "$id"
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

# create <title> <body-file> [extra-label...] — creates an issue in the team,
# authored as the God actor and labelled for filtering.
cmd_create() {
  local title="$1" body_file="$2"; shift 2
  local ids=() id
  for name in "$GOD_LABEL" "$@"; do
    id=$(label_id "$name")
    [ -n "$id" ] && ids+=("$id")
  done
  local label_json
  label_json=$(printf '%s\n' "${ids[@]+"${ids[@]}"}" | jq -R . | jq -sc 'map(select(length>0))')

  local query="mutation(\$t:String!, \$d:String!, \$team:String!, \$labels:[String!]$(actor_decl)){
    issueCreate(input:{title:\$t, description:\$d, teamId:\$team, labelIds:\$labels$(actor_input)}){
      success issue{ identifier url }
    }
  }"
  gql "$query" \
      "$(jq -nc --arg t "$title" --rawfile d "$body_file" --arg team "$LINEAR_TEAM_ID" \
             --argjson labels "$label_json" --argjson actor "$(actor_vars)" \
          '{t:$t, d:$d, team:$team, labels:$labels} + $actor')" \
    | jq -r '.data.issueCreate.issue | if . == null then "create failed" else "created \(.identifier) \(.url)" end'
}

# comment <issue-id> <text> — adds a recurrence comment, also authored as God.
cmd_comment() {
  local query="mutation(\$i:String!, \$b:String!$(actor_decl)){
    commentCreate(input:{issueId:\$i, body:\$b$(actor_input)}){ success }
  }"
  gql "$query" \
      "$(jq -nc --arg i "$1" --arg b "$2" --argjson actor "$(actor_vars)" \
          '{i:$i, b:$b} + $actor')" \
    | jq -r 'if .data.commentCreate.success then "commented" else "comment failed" end'
}

# reopen <issue-id> — moves a closed issue back to an unstarted state.
cmd_reopen() {
  local state
  state=$(gql 'query($team:ID!){ workflowStates(filter:{team:{id:{eq:$team}}}){ nodes{ id type } } }' \
              "$(jq -nc --arg team "$LINEAR_TEAM_ID" '{team:$team}')" \
          | jq -r '[.data.workflowStates.nodes[] | select(.type=="unstarted")][0].id')
  [ -n "$state" ] && [ "$state" != "null" ] || { echo "no unstarted state found" >&2; return 1; }
  gql 'mutation($i:String!,$s:String!){ issueUpdate(id:$i, input:{stateId:$s}){ success } }' \
      "$(jq -nc --arg i "$1" --arg s "$state" '{i:$i, s:$s}')" \
    | jq -r 'if .data.issueUpdate.success then "reopened" else "reopen failed" end'
}

# file <fingerprint> <title> <body-file> [extra-label...] — the full write
# protocol in one call. This is what prompts must use: it cannot skip the search.
cmd_file() {
  local fp="$1" title="$2" body="$3"; shift 3
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
  cmd_create "$title" "$body" "$@"
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

# whoami — reports how writes will be attributed. Run this before the first
# live run: it is the difference between issues authored by God and issues
# authored by you.
cmd_whoami() {
  if [ "$ACTOR_MODE" = "oauth" ]; then
    echo "actor: $GOD_ACTOR_NAME (OAuth actor=app — issues will be authored as $GOD_ACTOR_NAME)"
  else
    echo "actor: personal key — issues will be authored by the key's owner, NOT $GOD_ACTOR_NAME"
    echo "  to fix: authorize an OAuth app with actor=app and use its token as LINEAR_API_KEY"
  fi
  echo "team:  $LINEAR_TEAM_ID"
  echo "label: $GOD_LABEL"
}

case "${1:-}" in
  search)            shift; cmd_search "$@" ;;
  create)            shift; cmd_create "$@" ;;
  comment)           shift; cmd_comment "$@" ;;
  reopen)            shift; cmd_reopen "$@" ;;
  file)              shift; cmd_file "$@" ;;
  list-scout-titles) shift; cmd_list_scout_titles "$@" ;;
  runner-failure)    shift; cmd_runner_failure "$@" ;;
  whoami)            shift; cmd_whoami "$@" ;;
  *) echo "usage: client.sh {search|create|comment|reopen|file|list-scout-titles|runner-failure|whoami} ..." >&2; exit 1 ;;
esac
