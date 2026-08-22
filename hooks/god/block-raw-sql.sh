#!/usr/bin/env bash
# Gate 2 — no string-built SQL. PreToolUse on Edit|Write.
# Blocks edits that concatenate or interpolate values into SQL strings.
# Conservative on purpose: a false positive that blocks legitimate edits
# erodes trust in every gate. Test files are skipped.
set -u
. "$(dirname "$0")/lib.sh"

FILE=$(hook_field .tool_input.file_path)
case "$FILE" in
  *_test.*|*.test.*|*_spec.*|*.spec.*|*/tests/*|*/test/*) exit 0 ;;
esac

CONTENT=$(hook_field .tool_input.content)
[ -n "$CONTENT" ] || CONTENT=$(hook_field .tool_input.new_string)
[ -n "$CONTENT" ] || exit 0

SQL='(SELECT |INSERT INTO |UPDATE .* SET |DELETE FROM )'
HIT=$(printf '%s\n' "$CONTENT" | grep -nE \
  -e "\"[^\"]*${SQL}[^\"]*\"[[:space:]]*(\+|%|\|\|)" \
  -e "(\+|%)[[:space:]]*\"[^\"]*${SQL}" \
  -e "f\"[^\"]*${SQL}[^\"]*\{" \
  -e "Sprintf\([[:space:]]*\"[^\"]*${SQL}" \
  -e "\`[^\`]*${SQL}[^\`]*\\\$\{" \
  | head -3)

if [ -n "$HIT" ]; then
  {
    echo "Blocked: string-built SQL detected. Use parameterized queries."
    printf '%s\n' "$HIT"
  } >&2
  exit 2
fi
exit 0
