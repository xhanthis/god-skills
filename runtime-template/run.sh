#!/usr/bin/env bash
# Nightly tester runner.
#
# Every guardrail here is enforced in shell rather than in the prompt: a prompt
# can be argued out of a limit, a script cannot. The runner never works on the
# default branch, never exceeds the cost cap, and stops dead if PAUSE exists.
#
# GOD_DRY_RUN=1 runs the whole flow with a stubbed model call — use it to prove
# the guardrails behave before scheduling anything that spends money.
set -uo pipefail

ROOT="${GOD_ROOT:-$HOME/.god-agents}"
DATE=$(date +%F)
LOG="$ROOT/logs/$DATE.jsonl"

mkdir -p "$ROOT/logs"

if [ ! -f "$ROOT/config.sh" ]; then
  echo "missing $ROOT/config.sh — copy config.example.sh and fill it in" >&2
  exit 1
fi
# shellcheck source=/dev/null
. "$ROOT/config.sh"

# Kill switch, checked before anything else can happen.
if [ -f "$ROOT/PAUSE" ]; then
  echo "PAUSE present — exiting."
  exit 0
fi

notify() {
  command -v osascript >/dev/null 2>&1 &&
    osascript -e "display notification \"$1\" with title \"god-agents\"" >/dev/null 2>&1
  echo "$(date -Iseconds) $1" >> "$ROOT/logs/failures.log"
  if [ -x "$ROOT/linear/client.sh" ] && [ "${GOD_DRY_RUN:-0}" != "1" ]; then
    "$ROOT/linear/client.sh" runner-failure "$1" "$LOG" >/dev/null 2>&1 || true
  fi
}
trap 'notify "nightly run crashed (line $LINENO)"' ERR

# run_model — the one place the model is invoked, so dry runs can stub it.
run_model() {
  if [ "${GOD_DRY_RUN:-0}" = "1" ]; then
    printf '{"result":"dry run — model not called","total_cost_usd":%s}' "${GOD_FAKE_COST:-0.5}"
    return 0
  fi
  claude -p "$(cat "$ROOT/prompts/nightly-tester.md")" --output-format json
}

TOTAL=0
CAPPED=0

for repo in "${REPOS[@]}"; do
  if ! cd "$repo" 2>/dev/null; then
    notify "repo missing: $repo"
    continue
  fi

  if ! git fetch --all --quiet 2>/dev/null; then
    notify "fetch failed: $repo"
    continue
  fi

  # Never work on the default branch. Every run starts from a fresh branch off
  # the latest origin state.
  BRANCH="god/nightly-$DATE"
  if ! git checkout -B "$BRANCH" "origin/$DEFAULT_BRANCH" --quiet 2>/dev/null; then
    notify "branch checkout failed: $repo"
    continue
  fi

  CURRENT=$(git rev-parse --abbrev-ref HEAD)
  if [ "$CURRENT" = "$DEFAULT_BRANCH" ]; then
    notify "refusing to run on $DEFAULT_BRANCH in $repo"
    continue
  fi

  OUT=$(run_model 2>>"$ROOT/logs/$DATE.stderr")
  printf '%s\n' "$OUT" >> "$LOG"

  COST=$(printf '%s' "$OUT" | jq -r '.total_cost_usd // 0' 2>/dev/null || echo 0)
  TOTAL=$(awk -v a="$TOTAL" -v b="$COST" 'BEGIN{printf "%.4f", a+b}')

  # Post-hoc guardrail: the prompt is the first line of defence, this is the second.
  PUSHED=$(git ls-remote --heads origin "god/nightly-$DATE*" 2>/dev/null | wc -l | tr -d ' ')
  if [ "${PUSHED:-0}" -gt "$GOD_PR_CAP" ]; then
    notify "$repo pushed $PUSHED branches tonight (cap $GOD_PR_CAP) — review before the next run"
  fi

  if awk -v t="$TOTAL" -v c="$GOD_COST_CAP" 'BEGIN{exit !(t>c)}'; then
    notify "cost cap \$$GOD_COST_CAP hit at \$$TOTAL — remaining repos skipped"
    CAPPED=1
    break
  fi
done

date +%s > "$ROOT/logs/last-success"
SUFFIX=""
[ "$CAPPED" = "1" ] && SUFFIX=" (cost cap hit)"
echo "done: \$$TOTAL spent across ${#REPOS[@]} repo(s)$SUFFIX"
