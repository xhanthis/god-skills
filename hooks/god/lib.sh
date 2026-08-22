#!/usr/bin/env bash
# Shared helper for God hook scripts. Sourced, not executed.
# Reads the hook input JSON from stdin into HOOK_INPUT and defines hook_field.
# Gates must never block on their own bugs: any parse failure exits 0.

HOOK_INPUT=$(cat)

# hook_field <jq-path> — prints the value at a dot path (e.g. .tool_input.file_path),
# empty string if absent. Uses jq when present, python3 otherwise.
hook_field() {
  local path="$1"
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$HOOK_INPUT" | jq -r "${path} // empty" 2>/dev/null
  elif command -v python3 >/dev/null 2>&1; then
    printf '%s' "$HOOK_INPUT" | python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)
cur = d
for key in sys.argv[1].lstrip(".").split("."):
    if isinstance(cur, dict) and key in cur:
        cur = cur[key]
    else:
        sys.exit(0)
if cur is None or cur is False:
    sys.exit(0)
if cur is True:
    print("true")
else:
    print(cur)
' "$path" 2>/dev/null
  fi
}

# chain_log — prints the chain log path for the current project, creating the dir.
chain_log() {
  local cwd
  cwd=$(hook_field .cwd)
  [ -n "$cwd" ] || return 1
  mkdir -p "$cwd/.claude/logs" 2>/dev/null || return 1
  printf '%s' "$cwd/.claude/logs/chain.jsonl"
}
