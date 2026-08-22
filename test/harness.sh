#!/usr/bin/env bash
# Tiny assertion harness. Sourced by every test file.
# No dependencies: this repo ships zero-dependency tooling and the tests match.

PASS=0
FAIL=0

_ok()   { PASS=$((PASS + 1)); printf '  ok   %s\n' "$1"; }
_fail() { FAIL=$((FAIL + 1)); printf '  FAIL %s\n' "$1"; [ -n "${2:-}" ] && printf '       %s\n' "$2"; }

assert_eq() {
  if [ "$1" = "$2" ]; then _ok "$3"; else _fail "$3" "expected '$2', got '$1'"; fi
}

assert_contains() {
  case "$1" in
    *"$2"*) _ok "$3" ;;
    *) _fail "$3" "expected to contain '$2', got '$(printf '%s' "$1" | head -c 200)'" ;;
  esac
}

assert_not_contains() {
  case "$1" in
    *"$2"*) _fail "$3" "expected NOT to contain '$2'" ;;
    *) _ok "$3" ;;
  esac
}

# assert_exit <expected-code> <label> -- <command...>
assert_exit() {
  local want="$1" label="$2"; shift 3
  "$@" >/dev/null 2>&1
  local got=$?
  if [ "$got" = "$want" ]; then _ok "$label"; else _fail "$label" "expected exit $want, got $got"; fi
}

assert_file() {
  if [ -e "$1" ]; then _ok "$2"; else _fail "$2" "missing: $1"; fi
}

assert_no_file() {
  if [ -e "$1" ]; then _fail "$2" "should not exist: $1"; else _ok "$2"; fi
}

finish() {
  printf '\n  %d passed, %d failed\n\n' "$PASS" "$FAIL"
  [ "$FAIL" -eq 0 ] || exit 1
}
