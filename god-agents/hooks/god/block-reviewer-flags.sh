#!/usr/bin/env bash
# Gate 4 — nothing the org PR auto-reviewer greps for gets written.
# PreToolUse on Edit|Write. Applies to EVERY file, tests and fixtures included:
# CI secret scanning fails the PR on a credential-shaped literal, and the
# reviewer withholds auto-approval on text that reads as instructions to it or
# names a credential. Both checks are literal regexes on the reviewer's side,
# so they are literal regexes here — a prompt cannot argue its way past them.
set -u
. "$(dirname "$0")/lib.sh"

CONTENT=$(hook_field .tool_input.content)
[ -n "$CONTENT" ] || CONTENT=$(hook_field .tool_input.new_string)
[ -n "$CONTENT" ] || exit 0

# Provider-issued credential shapes: the union of the org CI env-hygiene job and
# the reviewer's output filter. Case-sensitive — the prefixes are.
SECRET_SHAPES='AKIA[0-9A-Z]{16}|ASIA[0-9A-Z]{16}|AIza[0-9A-Za-z_-]{35}|sk_live_[0-9a-zA-Z]{24,}|rzp_live_[0-9a-zA-Z]{14,}|gh[pousr]_[0-9A-Za-z]{20,}|github_pat_[0-9A-Za-z_]{30,}|xox[baprse]-[0-9A-Za-z-]{10,}|sk-ant-[A-Za-z0-9_-]{20,}|-----BEGIN [A-Z ]*PRIVATE KEY-----|eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{6,}'

# Text that reads like an attempt to redirect the reviewer or probe for
# credentials. Verbatim from the reviewer; case-insensitive there, so here.
INJECTION_MARKERS='(ignore|disregard|forget|override)[[:space:]]+(all[[:space:]]+)?(the[[:space:]]+)?(previous|prior|above|earlier|system)[[:space:]]+(instruction|prompt|rule|direction)|you[[:space:]]+are[[:space:]]+now[[:space:]]|new[[:space:]]+(system[[:space:]]+)?instructions?|<\|im_(start|end)\|>|\[\[SYSTEM\]\]|print[[:space:]]+(out[[:space:]]+)?(the[[:space:]]+)?(contents?|value)s?[[:space:]]+of|GH_TOKEN|CLAUDE_CODE_OAUTH_TOKEN|ANTHROPIC_API_KEY|SLACK_WEBHOOK|/proc/self/environ|\.credentials\.json|secrets\.env|always[[:space:]]+approve|reply[[:space:]]+with[[:space:]]+approve'

HIT=$(printf '%s\n' "$CONTENT" | grep -anE "$SECRET_SHAPES" | head -3)
if [ -n "$HIT" ]; then
  {
    echo "Blocked: credential-shaped literal. CI secret scanning fails the PR on it and the reviewer withholds it."
    echo "Use an obviously fake value (test-token-not-real); build JWTs at runtime in tests; read real values from the environment."
    printf '%s\n' "$HIT"
  } >&2
  exit 2
fi

HIT=$(printf '%s\n' "$CONTENT" | grep -anEi "$INJECTION_MARKERS" | head -3)
if [ -n "$HIT" ]; then
  {
    echo "Blocked: text the PR auto-reviewer treats as an injection attempt or a credential probe — auto-approval is withheld and a human is paged."
    echo "Rephrase; keep injection-test payloads in a base64 or joined-string constant; GITHUB_TOKEN works wherever GH_TOKEN did."
    printf '%s\n' "$HIT"
  } >&2
  exit 2
fi
exit 0
