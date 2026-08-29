#!/usr/bin/env bash
# Gate 3 — audit trail. PostToolUse on Edit|Write.
# Appends {ts, agent, tool, file} to <project>/.claude/logs/chain.jsonl.
# This log is what god-police samples and what require-tester-pass.sh reads.
set -u
. "$(dirname "$0")/lib.sh"

LOG=$(chain_log) || exit 0
AGENT=$(hook_field .agent_type); AGENT=${AGENT:-lead}
TOOL=$(hook_field .tool_name)
FILE=$(hook_field .tool_input.file_path)
[ -n "$TOOL" ] || exit 0

printf '{"ts":%s,"agent":"%s","tool":"%s","file":"%s"}\n' \
  "$(date +%s)" "$AGENT" "$TOOL" "$FILE" >> "$LOG"
exit 0
