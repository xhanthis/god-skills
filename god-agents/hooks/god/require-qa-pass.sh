#!/usr/bin/env bash
# Gate 1 — dev cannot self-declare done. Runs on the lead session's Stop event
# (not god-dev's SubagentStop: qa runs after dev finishes, and dev cannot
# spawn it, so blocking dev's stop would deadlock; the lead session can).
# Blocks the session from finishing while god-dev edits have no god-qa PASS
# after the newest of them. Checks both ways god-dev runs:
#   subagent     — chain.jsonl, written by log-edits.sh and record-verdict.sh
#   inline skill — the session transcript, because inline edits carry no
#                  agent_type and no SubagentStop fires to record the verdict
set -u
. "$(dirname "$0")/lib.sh"

[ "$(hook_field .stop_hook_active)" = "true" ] && exit 0   # loop guard

block() {
  echo "god-dev changes lack a god-qa PASS. Run god-qa before finishing." >&2
  exit 2
}

CWD=$(hook_field .cwd)
LOG="$CWD/.claude/logs/chain.jsonl"
if [ -n "$CWD" ] && [ -f "$LOG" ]; then
  LAST_DEV=$(grep -nE '"agent": ?"god-dev"' "$LOG" | tail -1 | cut -d: -f1)
  LAST_PASS=$(grep -nE '"verdict": ?"PASS"' "$LOG" | tail -1 | cut -d: -f1)
  if [ -n "$LAST_DEV" ] && { [ -z "$LAST_PASS" ] || [ "$LAST_PASS" -lt "$LAST_DEV" ]; }; then
    block
  fi
fi

TRANSCRIPT=$(hook_field .transcript_path)
[ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ] || exit 0

# lead_lines <regex> — numbered transcript lines matching regex that are
# main-session assistant messages. User messages quote skill bodies and tool
# output, and sidechain edits belong to subagents already tracked in chain.jsonl.
lead_lines() {
  grep -nE "$1" "$TRANSCRIPT" | grep -E '"role": ?"assistant"' | grep -vE '"isSidechain": ?true'
}

FIRST_DEV=$(lead_lines '"name": ?"Skill", ?"input": ?\{ ?"skill": ?"god-dev"' | head -1 | cut -d: -f1)
[ -n "$FIRST_DEV" ] || exit 0
LAST_EDIT=$(lead_lines '"name": ?"(Edit|Write|MultiEdit|NotebookEdit)", ?"input": ?\{' | tail -1 | cut -d: -f1)
[ -n "$LAST_EDIT" ] && [ "$LAST_EDIT" -ge "$FIRST_DEV" ] || exit 0

VERDICT_LINE=$(lead_lines 'Result: ?(PASS|FAIL|UNVERIFIED)' | tail -1)
VERDICT_AT=$(printf '%s' "$VERDICT_LINE" | cut -d: -f1)
VERDICT=$(printf '%s' "$VERDICT_LINE" | grep -oE 'Result: ?(PASS|FAIL|UNVERIFIED)' | tail -1 | grep -oE 'PASS|FAIL|UNVERIFIED')

if [ "$VERDICT" != "PASS" ] || [ "$VERDICT_AT" -lt "$LAST_EDIT" ]; then
  block
fi
exit 0
