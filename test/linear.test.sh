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
export LINEAR_API_KEY="mock-key"
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

rm -f "$BODY" "$BODY2" "$BODY3"
finish
