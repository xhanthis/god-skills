#!/usr/bin/env bash
# Weekly scout runner.
#
# Read-only by construction: no branch is created, nothing is committed, and the
# prompt forbids writes. Scout's only output is Linear issues and a summary.
#
# GOD_DRY_RUN=1 stubs the model call so the guardrails can be tested for free.
set -uo pipefail

ROOT="${GOD_ROOT:-$HOME/.god-agents}"
DATE=$(date +%F)
LOG="$ROOT/logs/scout-$DATE.jsonl"

mkdir -p "$ROOT/logs"

if [ ! -f "$ROOT/config.sh" ]; then
  echo "missing $ROOT/config.sh — copy config.example.sh and fill it in" >&2
  exit 1
fi
# shellcheck source=/dev/null
. "$ROOT/config.sh"

if [ -f "$ROOT/PAUSE" ]; then
  echo "PAUSE present — exiting."
  exit 0
fi

notify() {
  command -v osascript >/dev/null 2>&1 &&
    osascript -e "display notification \"$1\" with title \"god-scout\"" >/dev/null 2>&1
  echo "$(date -Iseconds) $1" >> "$ROOT/logs/failures.log"
  if [ -x "$ROOT/linear/client.sh" ] && [ "${GOD_DRY_RUN:-0}" != "1" ]; then
    "$ROOT/linear/client.sh" runner-failure "$1" "$LOG" >/dev/null 2>&1 || true
  fi
}
trap 'notify "weekly scout crashed (line $LINENO)"' ERR

run_model() {
  if [ "${GOD_DRY_RUN:-0}" = "1" ]; then
    printf '{"result":"dry run — model not called","total_cost_usd":%s}' "${GOD_FAKE_COST:-0.5}"
    return 0
  fi
  claude -p "$(cat "$ROOT/prompts/weekly-scout.md")" --output-format json
}

TOTAL=0
CAPPED=0

for repo in "${SCOUT_REPOS[@]}"; do
  if ! cd "$repo" 2>/dev/null; then
    notify "repo missing: $repo"
    continue
  fi

  BEFORE=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
  git fetch --all --quiet 2>/dev/null || true   # read latest, never switch branches

  OUT=$(run_model 2>>"$ROOT/logs/scout-$DATE.stderr")
  printf '%s\n' "$OUT" >> "$LOG"

  # Scout must leave the checkout exactly as it found it.
  AFTER=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
  if [ "$BEFORE" != "$AFTER" ]; then
    notify "scout changed branch in $repo ($BEFORE -> $AFTER) — investigate"
  fi

  COST=$(printf '%s' "$OUT" | jq -r '.total_cost_usd // 0' 2>/dev/null || echo 0)
  TOTAL=$(awk -v a="$TOTAL" -v b="$COST" 'BEGIN{printf "%.4f", a+b}')
  if awk -v t="$TOTAL" -v c="$GOD_SCOUT_COST_CAP" 'BEGIN{exit !(t>c)}'; then
    notify "scout cost cap \$$GOD_SCOUT_COST_CAP hit at \$$TOTAL — remaining repos skipped"
    CAPPED=1
    break
  fi
done

date +%s > "$ROOT/logs/last-scout-success"
SUFFIX=""
[ "$CAPPED" = "1" ] && SUFFIX=" (cost cap hit)"
echo "scout done: \$$TOTAL spent across ${#SCOUT_REPOS[@]} repo(s)$SUFFIX"
