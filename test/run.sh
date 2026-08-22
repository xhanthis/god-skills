#!/usr/bin/env bash
# Runs every test file. `npm test`.
set -uo pipefail
cd "$(dirname "$0")/.."

FAILED=0
for file in test/*.test.sh; do
  printf '\n\033[1m%s\033[0m\n' "$file"
  bash "$file" || FAILED=1
done

if [ "$FAILED" -eq 0 ]; then
  printf '\033[32mall suites passed\033[0m\n'
else
  printf '\033[31msome suites failed\033[0m\n'
fi
exit "$FAILED"
