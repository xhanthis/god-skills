#!/usr/bin/env bash
# Nightly tester runner. Guardrails are enforced here in shell, not in the prompt:
# a prompt can be talked out of a limit, a script cannot.
set -uo pipefail

ROOT="$HOME/.god-agents"
DATE=$(date +%F)
LOG="$ROOT/logs/$DATE.jsonl"
COST_CAP="${GOD_COST_CAP:-10}"        # USD across all repos, per night
PR_CAP="${GOD_PR_CAP:-3}"             # per repo, per night
REPOS=({{REPO_PATHS}})                # e.g. "$HOME/code/backend" "$HOME/code/admin_app"
DEFAULT_BRANCH="{{DEFAULT_BRANCH}}"

mkdir -p "$ROOT/logs"

[ -f "$ROOT/PAUSE" ] && { echo "PAUSE present — exiting."; exit 0; }

notify() {
  command -v osascript >/dev/null 2>&1 &&
    osascript -e "display notification \"$1\" with title \"god-agents\"" >/dev/null 2>&1
  echo "$(date -Iseconds) $1" >> "$ROOT/logs/failures.log"
  "$ROOT/linear/client.sh" runner-failure "$1" "$LOG" >/dev/null 2>&1 || true
}
trap 'notify "nightly run crashed (line $LINENO)"' ERR

TOTAL=0
for repo in "${REPOS[@]}"; do
  cd "$repo" || { notify "repo missing: $repo"; continue; }

  git fetch --all --quiet || { notify "fetch failed: $repo"; continue; }
  # Never work on the default branch.
  git checkout -B "god/nightly-$DATE" "origin/$DEFAULT_BRANCH" --quiet || {
    notify "branch checkout failed: $repo"; continue; }

  OUT=$(claude -p "$(cat "$ROOT/prompts/nightly-tester.md")" \
          --output-format json 2>>"$ROOT/logs/$DATE.stderr")
  printf '%s\n' "$OUT" >> "$LOG"

  COST=$(printf '%s' "$OUT" | jq -r '.total_cost_usd // 0' 2>/dev/null || echo 0)
  TOTAL=$(awk -v a="$TOTAL" -v b="$COST" 'BEGIN{print a+b}')
  if awk -v t="$TOTAL" -v c="$COST_CAP" 'BEGIN{exit !(t>c)}'; then
    notify "cost cap \$$COST_CAP hit at \$$TOTAL — remaining repos skipped"
    break
  fi

  # Post-hoc guardrail check: the prompt is the first line of defence, this is the second.
  N=$(git ls-remote --heads origin "god/nightly-$DATE*" 2>/dev/null | wc -l | tr -d ' ')
  if [ "${N:-0}" -gt "$PR_CAP" ]; then
    notify "$repo pushed $N branches tonight (cap $PR_CAP) — review before the next run"
  fi
done

date +%s > "$ROOT/logs/last-success"
echo "done: \$$TOTAL spent across ${#REPOS[@]} repo(s)"
