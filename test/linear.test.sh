#!/usr/bin/env bash
# M4 — the dedup protocol. This is the test that has to pass before the nightly
# runner is ever scheduled: a runner without working dedup floods Linear on
# night one.
set -uo pipefail
cd "$(dirname "$0")/.."
. test/harness.sh

PORT=${MOCK_PORT:-4747}
CLIENT="runtime-template/linear/client.sh"

export LINEAR_API_URL="http://127.0.0.1:$PORT"
export LINEAR_API_KEY="lin_oauth_mock"   # oauth prefix => actor mode, see client.sh
export LINEAR_TEAM_ID="mock-team"

node test/mock-linear.js "$PORT" >/dev/null 2>&1 &
MOCK_PID=$!
trap 'kill $MOCK_PID 2>/dev/null' EXIT

for _ in $(seq 1 40); do
  curl -sf "$LINEAR_API_URL/__dump" >/dev/null 2>&1 && break
  sleep 0.1
done

FP='<!-- god-fingerprint: repo:pkg/pay.go:sql-concat:Charge -->'
BODY=$(mktemp)
printf 'Finding: concatenated SQL.\n\n%s\n' "$FP" > "$BODY"

# --- create ---------------------------------------------------------------
OUT=$("$CLIENT" file "$FP" "[god-tester] concatenated SQL in Charge" "$BODY")
assert_contains "$OUT" "created GOD-1" "first file() creates an issue"

# --- the whole point: same finding again must not create a second issue ----
OUT=$("$CLIENT" file "$FP" "[god-tester] concatenated SQL in Charge" "$BODY")
assert_contains "$OUT" "commented" "second file() comments instead of creating"

COUNT=$(curl -s "$LINEAR_API_URL/__dump" | jq '.issues | length')
assert_eq "$COUNT" "1" "still exactly one issue after a duplicate finding"

COMMENTS=$(curl -s "$LINEAR_API_URL/__dump" | jq '.comments | length')
assert_eq "$COMMENTS" "1" "the duplicate produced exactly one comment"

# --- a different finding is genuinely new ---------------------------------
FP2='<!-- god-fingerprint: repo:pkg/user.go:n-plus-one:ListUsers -->'
BODY2=$(mktemp)
printf 'Finding: N+1 query.\n\n%s\n' "$FP2" > "$BODY2"
OUT=$("$CLIENT" file "$FP2" "[god-tester] N+1 in ListUsers" "$BODY2")
assert_contains "$OUT" "created GOD-2" "a different fingerprint creates a new issue"

# --- closed issue refound: reopen + regression, never a duplicate ----------
curl -s "$LINEAR_API_URL/__close/GOD-1" >/dev/null
OUT=$("$CLIENT" file "$FP" "[god-tester] concatenated SQL in Charge" "$BODY")
assert_contains "$OUT" "reopened" "a refound closed issue is reopened"
assert_contains "$OUT" "commented" "the reopen is annotated"

STATE=$(curl -s "$LINEAR_API_URL/__dump" | jq -r '.issues[] | select(.identifier=="GOD-1") | .stateType')
assert_eq "$STATE" "unstarted" "reopened issue left in an open state"

COUNT=$(curl -s "$LINEAR_API_URL/__dump" | jq '.issues | length')
assert_eq "$COUNT" "2" "reopening did not create a third issue"

REGRESSION=$(curl -s "$LINEAR_API_URL/__dump" | jq -r '[.comments[] | select(.body | test("Regression"))] | length')
assert_eq "$REGRESSION" "1" "the regression is labelled as one in the comment"

# --- scout conceptual dedup input -----------------------------------------
FP3='<!-- god-fingerprint: scout:store:extraction -->'
BODY3=$(mktemp)
printf 'Observation: store module is decoupled.\n\n%s\n' "$FP3" > "$BODY3"
"$CLIENT" file "$FP3" "[god-scout] store module is extractable" "$BODY3" >/dev/null
TITLES=$("$CLIENT" list-scout-titles)
assert_contains "$TITLES" "[god-scout] store module is extractable" "scout titles are listable for overlap checks"
assert_not_contains "$TITLES" "[god-tester]" "tester issues are excluded from scout titles"

# --- search on a fingerprint that was never filed --------------------------
EMPTY=$("$CLIENT" search '<!-- god-fingerprint: nope:nope:nope:nope -->')
assert_eq "$EMPTY" "" "search returns nothing for an unknown fingerprint"

# --- attribution: agents write into the shared workspace as "God" ----------
# The team is shared with human work, so authorship and the label are what keep
# agent findings identifiable and filterable.
ACTORS=$(curl -s "$LINEAR_API_URL/__dump" | jq -r '[.issues[].createAsUser] | unique | join(",")')
assert_eq "$ACTORS" "God" "every issue is authored as God"

COMMENT_ACTORS=$(curl -s "$LINEAR_API_URL/__dump" | jq -r '[.comments[].createAsUser] | unique | join(",")')
assert_eq "$COMMENT_ACTORS" "God" "every comment is authored as God"

LABELLED=$(curl -s "$LINEAR_API_URL/__dump" | jq '[.issues[] | select((.labelIds | length) > 0)] | length')
ISSUES=$(curl -s "$LINEAR_API_URL/__dump" | jq '.issues | length')
assert_eq "$LABELLED" "$ISSUES" "every issue carries a label for filtering"

GODLABEL=$(curl -s "$LINEAR_API_URL/__dump" | jq -r '[.labels[] | select(.name=="god")] | length')
assert_eq "$GODLABEL" "1" "the god label is created once and reused"

# a custom actor name is honoured
BODY4=$(mktemp)
FP4='<!-- god-fingerprint: repo:pkg/a.go:rule:Sym -->'
printf 'x\n\n%s\n' "$FP4" > "$BODY4"
GOD_ACTOR_NAME="Zeus" "$CLIENT" file "$FP4" "[god-tester] custom actor" "$BODY4" >/dev/null
ZEUS=$(curl -s "$LINEAR_API_URL/__dump" | jq -r '[.issues[] | select(.createAsUser=="Zeus")] | length')
assert_eq "$ZEUS" "1" "GOD_ACTOR_NAME overrides the actor name"
rm -f "$BODY4"

# an extra label rides along with the god label
BODY5=$(mktemp)
FP5='<!-- god-fingerprint: repo:pkg/b.go:rule:Sym -->'
printf 'x\n\n%s\n' "$FP5" > "$BODY5"
"$CLIENT" file "$FP5" "[god-tester] labelled" "$BODY5" Bug >/dev/null
NLABELS=$(curl -s "$LINEAR_API_URL/__dump" | jq '[.issues[] | select(.title=="[god-tester] labelled")][0].labelIds | length')
assert_eq "$NLABELS" "2" "an extra label is applied alongside the god label"
rm -f "$BODY5"

# --- a personal key must not silently pretend to be God -------------------
# Linear rejects createAsUser on personal keys, so the client must omit it and
# say so rather than producing issues quietly authored by the key's owner.
OUT=$(LINEAR_API_KEY="lin_api_personal" "$CLIENT" whoami)
assert_contains "$OUT" "NOT God" "a personal key reports that writes will not be authored as God"
assert_contains "$OUT" "actor=app" "the fix is named in the same breath"

BODY6=$(mktemp)
FP6='<!-- god-fingerprint: repo:pkg/c.go:rule:Sym -->'
printf 'x\n\n%s\n' "$FP6" > "$BODY6"
LINEAR_API_KEY="lin_api_personal" "$CLIENT" file "$FP6" "[god-tester] personal key" "$BODY6" >/dev/null
PERSONAL=$(curl -s "$LINEAR_API_URL/__dump" | jq -r '[.issues[] | select(.title=="[god-tester] personal key")][0].createAsUser')
assert_eq "$PERSONAL" "null" "a personal key omits createAsUser instead of sending an invalid field"
rm -f "$BODY6"

OUT=$(LINEAR_ACTOR_MODE=oauth LINEAR_API_KEY="lin_api_personal" "$CLIENT" whoami)
assert_contains "$OUT" "authored as God" "LINEAR_ACTOR_MODE overrides the prefix heuristic"


rm -f "$BODY" "$BODY2" "$BODY3"
finish
