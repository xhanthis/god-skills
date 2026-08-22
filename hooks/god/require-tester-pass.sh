#!/usr/bin/env bash
# Gate 1 — dev cannot self-declare done. Runs on the lead session's Stop event
# (not god-dev's SubagentStop: tester runs after dev finishes, and dev cannot
# spawn it, so blocking dev's stop would deadlock; the lead session can).
# Blocks the session from finishing while chain.jsonl shows god-dev edits with
# no god-tester PASS recorded after the newest of them.
set -u
. "$(dirname "$0")/lib.sh"

[ "$(hook_field .stop_hook_active)" = "true" ] && exit 0   # loop guard

CWD=$(hook_field .cwd)
LOG="$CWD/.claude/logs/chain.jsonl"
[ -n "$CWD" ] && [ -f "$LOG" ] || exit 0

LAST_DEV=$(grep -nE '"agent": ?"god-dev"' "$LOG" | tail -1 | cut -d: -f1)
[ -n "$LAST_DEV" ] || exit 0
LAST_PASS=$(grep -nE '"verdict": ?"PASS"' "$LOG" | tail -1 | cut -d: -f1)

if [ -z "$LAST_PASS" ] || [ "$LAST_PASS" -lt "$LAST_DEV" ]; then
  echo "god-dev changes lack a god-tester PASS. Run god-tester before finishing." >&2
  exit 2
fi
exit 0
