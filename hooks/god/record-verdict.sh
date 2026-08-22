#!/usr/bin/env bash
# SubagentStop matched to god-tester.
# Greps the tester transcript for its final verdict and records it in chain.jsonl
# so require-tester-pass.sh has ground truth about whether a PASS exists.
set -u
. "$(dirname "$0")/lib.sh"

TRANSCRIPT=$(hook_field .transcript_path)
[ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ] || exit 0
LOG=$(chain_log) || exit 0

VERDICT=$(grep -oE 'Result: ?(PASS|FAIL|UNVERIFIED)' "$TRANSCRIPT" 2>/dev/null \
  | tail -1 | grep -oE 'PASS|FAIL|UNVERIFIED')
[ -n "$VERDICT" ] || exit 0

printf '{"ts":%s,"agent":"god-tester","verdict":"%s"}\n' \
  "$(date +%s)" "$VERDICT" >> "$LOG"
exit 0
