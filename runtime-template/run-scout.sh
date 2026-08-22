#!/usr/bin/env bash
# Weekly scout runner. Read-only by construction: no branch is created, no push
# is possible, and the prompt forbids writes. Scout files Linear issues only.
set -uo pipefail

ROOT="$HOME/.god-agents"
DATE=$(date +%F)
LOG="$ROOT/logs/scout-$DATE.jsonl"
COST_CAP="${GOD_SCOUT_COST_CAP:-8}"
REPOS=({{SCOUT_REPO_PATHS}})          # includes read-only repos with no test harness

mkdir -p "$ROOT/logs"
[ -f "$ROOT/PAUSE" ] && { echo "PAUSE present — exiting."; exit 0; }

notify() {
  command -v osascript >/dev/null 2>&1 &&
    osascript -e "display notification \"$1\" with title \"god-scout\"" >/dev/null 2>&1
  echo "$(date -Iseconds) $1" >> "$ROOT/logs/failures.log"
  "$ROOT/linear/client.sh" runner-failure "$1" "$LOG" >/dev/null 2>&1 || true
}
trap 'notify "weekly scout crashed (line $LINENO)"' ERR

TOTAL=0
for repo in "${REPOS[@]}"; do
  cd "$repo" || { notify "repo missing: $repo"; continue; }
  git fetch --all --quiet || true      # read latest, but never switch branches

  OUT=$(claude -p "$(cat "$ROOT/prompts/weekly-scout.md")" \
          --output-format json 2>>"$ROOT/logs/scout-$DATE.stderr")
  printf '%s\n' "$OUT" >> "$LOG"

  COST=$(printf '%s' "$OUT" | jq -r '.total_cost_usd // 0' 2>/dev/null || echo 0)
  TOTAL=$(awk -v a="$TOTAL" -v b="$COST" 'BEGIN{print a+b}')
  if awk -v t="$TOTAL" -v c="$COST_CAP" 'BEGIN{exit !(t>c)}'; then
    notify "scout cost cap \$$COST_CAP hit at \$$TOTAL — remaining repos skipped"
    break
  fi
done

date +%s > "$ROOT/logs/last-scout-success"
echo "scout done: \$$TOTAL spent"
