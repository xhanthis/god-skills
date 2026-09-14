#!/usr/bin/env bash
# Gate 5 — loose ends a senior reviewer sends straight back. PreToolUse on Edit|Write.
#  1. An orphan TODO/FIXME/HACK: no owner, no ticket. It is never picked up.
#  2. An external call with no timeout: it hangs a worker forever on a bad day.
# Conservative on purpose: only shapes that are wrong on their face. Test files
# and prose (.md/.txt) are skipped.
set -u
. "$(dirname "$0")/lib.sh"

FILE=$(hook_field .tool_input.file_path)
case "$FILE" in
  *_test.*|*.test.*|*_spec.*|*.spec.*|*/tests/*|*/test/*|*.md|*.txt) exit 0 ;;
esac

CONTENT=$(hook_field .tool_input.content)
[ -n "$CONTENT" ] || CONTENT=$(hook_field .tool_input.new_string)
[ -n "$CONTENT" ] || exit 0

# TODO(owner, ENG-123) or TODO(owner, #123) is owned; anything else is orphaned.
HIT=$(printf '%s\n' "$CONTENT" | grep -nE '\b(TODO|FIXME|HACK)\b' \
  | grep -vE '\b(TODO|FIXME|HACK)\([A-Za-z0-9_.@-]+,[[:space:]]*([A-Z][A-Z0-9]*-[0-9]+|#[0-9]+)\)' \
  | head -3)
if [ -n "$HIT" ]; then
  {
    echo "Blocked: orphan TODO/FIXME/HACK. Write it as TODO(owner, TICKET-123) or fix it now."
    printf '%s\n' "$HIT"
  } >&2
  exit 2
fi

# Python requests without timeout= on the call line; Go's package-level HTTP
# helpers, which use a client that never times out.
HIT=$(printf '%s\n' "$CONTENT" | grep -nE \
  -e 'requests\.(get|post|put|patch|delete|head|request)\(' \
  -e '\bhttp\.(Get|Post|Head|PostForm)\(' \
  -e '\bhttp\.DefaultClient\b' \
  | grep -vE 'timeout[[:space:]]*=' \
  | head -3)
if [ -n "$HIT" ]; then
  {
    echo "Blocked: external call with no timeout. Pass timeout= (requests) or use an http.Client{Timeout: ...} (Go)."
    printf '%s\n' "$HIT"
  } >&2
  exit 2
fi
exit 0
