#!/usr/bin/env bash
# M5 — runner guardrails. These are the rules that keep an unattended run from
# doing damage, so they are tested against real git repos with the model stubbed
# out (GOD_DRY_RUN=1). No network, no spend.
set -uo pipefail
cd "$(dirname "$0")/.."
. test/harness.sh

REPO_ROOT=$(pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# --- build a fake origin + two clones -------------------------------------
mk_repo() {
  local name="$1"
  git init -q --bare "$WORK/$name.git"
  git clone -q "$WORK/$name.git" "$WORK/$name" 2>/dev/null
  cd "$WORK/$name"
  git config user.email t@t.t; git config user.name t
  echo hello > file.txt
  git add -A; git commit -qm init
  git branch -M main
  git push -q -u origin main
  cd "$REPO_ROOT"
}
mk_repo alpha
mk_repo beta

# --- a runtime root wired to those repos ----------------------------------
ROOT="$WORK/.god-agents"
mkdir -p "$ROOT/logs" "$ROOT/prompts" "$ROOT/linear"
cp god-agents/runtime-template/run.sh "$ROOT/"
cp god-agents/runtime-template/linear/client.sh "$ROOT/linear/"
echo "test prompt" > "$ROOT/prompts/nightly-tester.md"
chmod +x "$ROOT"/*.sh "$ROOT/linear/client.sh"

cat > "$ROOT/config.sh" <<EOF
REPOS=("$WORK/alpha" "$WORK/beta")
DEFAULT_BRANCH="main"
GOD_COST_CAP="\${GOD_COST_CAP:-10}"
GOD_PR_CAP="\${GOD_PR_CAP:-3}"
EOF

run_nightly() { GOD_ROOT="$ROOT" GOD_DRY_RUN=1 bash "$ROOT/run.sh" 2>&1; }

# --- missing config is a hard stop, not a silent default -------------------
mv "$ROOT/config.sh" "$ROOT/config.hidden"
OUT=$(run_nightly); CODE=$?
assert_eq "$CODE" "1" "missing config.sh exits non-zero"
assert_contains "$OUT" "missing" "missing config.sh explains itself"
mv "$ROOT/config.hidden" "$ROOT/config.sh"

# --- kill switch ----------------------------------------------------------
touch "$ROOT/PAUSE"
OUT=$(run_nightly)
assert_contains "$OUT" "PAUSE present" "PAUSE stops the nightly runner"
rm "$ROOT/PAUSE"

# --- normal run -----------------------------------------------------------
OUT=$(GOD_FAKE_COST=0.5 run_nightly)
assert_contains "$OUT" "2 repo(s)" "nightly visits every configured repo"
assert_contains "$OUT" '$1.0000' "costs accumulate across repos"

# --- never on the default branch ------------------------------------------
cd "$WORK/alpha"; BRANCH=$(git rev-parse --abbrev-ref HEAD); cd "$REPO_ROOT"
assert_contains "$BRANCH" "god/nightly-" "runner left the repo on a god/nightly branch"
assert_not_contains "$BRANCH" "main" "runner never leaves the repo on main"

# --- cost cap aborts the remaining repos ----------------------------------
OUT=$(GOD_FAKE_COST=9 GOD_COST_CAP=5 run_nightly)
assert_contains "$OUT" "cost cap" "cost cap fires when exceeded"
assert_contains "$OUT" "(cost cap hit)" "the summary says the run was capped"
FAILLOG=$(cat "$ROOT/logs/failures.log")
assert_contains "$FAILLOG" "remaining repos skipped" "cap breach is recorded as a failure"
COUNT=$(grep -c "dry run" "$ROOT/logs/$(date +%F).jsonl")
assert_eq "$COUNT" "3" "capped run called the model once, not twice (2 prior + 1)"

# --- under the cap, nothing is skipped ------------------------------------
: > "$ROOT/logs/failures.log"
OUT=$(GOD_FAKE_COST=0.1 GOD_COST_CAP=100 run_nightly)
assert_not_contains "$OUT" "cost cap" "no cap message when well under budget"

# --- a missing repo is reported, not fatal --------------------------------
cat >> "$ROOT/config.sh" <<EOF
REPOS+=("$WORK/does-not-exist")
EOF
OUT=$(GOD_FAKE_COST=0.1 run_nightly)
assert_contains "$OUT" "3 repo(s)" "run continues past a missing repo"
assert_contains "$(cat "$ROOT/logs/failures.log")" "repo missing" "missing repo is recorded"

# --- last-success timestamps let silent death be detected ------------------
assert_file "$ROOT/logs/last-success" "nightly writes a last-success timestamp"

finish
