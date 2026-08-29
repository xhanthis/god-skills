#!/usr/bin/env bash
# M3 — the hook gates. These are the only part of the system that cannot be
# talked out of enforcing a rule, so they are tested against sample hook input
# both with jq available and with jq removed from PATH.
set -uo pipefail
cd "$(dirname "$0")/.."
. test/harness.sh

H="$(pwd)/god-agents/hooks/god"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

hook() { printf '%s' "$2" | "$H/$1"; }

run_gate() {
  # run_gate <script> <json> -> prints exit code
  printf '%s' "$2" | "$H/$1" >/dev/null 2>&1
  echo $?
}

PROJ="$WORK/proj"; mkdir -p "$PROJ"
LOG="$PROJ/.claude/logs/chain.jsonl"

# --- Gate 3: audit trail --------------------------------------------------
hook log-edits.sh "{\"cwd\":\"$PROJ\",\"agent_type\":\"god-dev\",\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"/x/y.go\"}}"
assert_file "$LOG" "log-edits creates the chain log"
assert_contains "$(cat "$LOG")" '"agent":"god-dev"' "the edit is attributed to the agent that made it"

# --- Gate 1: no PASS, no finish -------------------------------------------
CODE=$(run_gate require-tester-pass.sh "{\"cwd\":\"$PROJ\",\"stop_hook_active\":false}")
assert_eq "$CODE" "2" "session is blocked while god-dev edits lack a tester PASS"

# --- verdict recording ----------------------------------------------------
printf 'noise\n**Result: PASS**\n' > "$WORK/transcript.txt"
hook record-verdict.sh "{\"cwd\":\"$PROJ\",\"transcript_path\":\"$WORK/transcript.txt\"}"
assert_contains "$(cat "$LOG")" '"verdict":"PASS"' "the tester verdict is recorded"

CODE=$(run_gate require-tester-pass.sh "{\"cwd\":\"$PROJ\",\"stop_hook_active\":false}")
assert_eq "$CODE" "0" "a recorded PASS unblocks the session"

# --- a later dev edit re-blocks -------------------------------------------
hook log-edits.sh "{\"cwd\":\"$PROJ\",\"agent_type\":\"god-dev\",\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"/x/z.go\"}}"
CODE=$(run_gate require-tester-pass.sh "{\"cwd\":\"$PROJ\",\"stop_hook_active\":false}")
assert_eq "$CODE" "2" "an edit after the PASS blocks again"

# --- FAIL is not a PASS ---------------------------------------------------
printf '**Result: FAIL**\n' > "$WORK/fail.txt"
hook record-verdict.sh "{\"cwd\":\"$PROJ\",\"transcript_path\":\"$WORK/fail.txt\"}"
CODE=$(run_gate require-tester-pass.sh "{\"cwd\":\"$PROJ\",\"stop_hook_active\":false}")
assert_eq "$CODE" "2" "a FAIL verdict does not unblock the session"

# --- UNVERIFIED is not a PASS either --------------------------------------
printf '**Result: UNVERIFIED**\n' > "$WORK/unv.txt"
hook record-verdict.sh "{\"cwd\":\"$PROJ\",\"transcript_path\":\"$WORK/unv.txt\"}"
CODE=$(run_gate require-tester-pass.sh "{\"cwd\":\"$PROJ\",\"stop_hook_active\":false}")
assert_eq "$CODE" "2" "an UNVERIFIED verdict does not unblock the session"

# --- loop guard -----------------------------------------------------------
CODE=$(run_gate require-tester-pass.sh "{\"cwd\":\"$PROJ\",\"stop_hook_active\":true}")
assert_eq "$CODE" "0" "the gate does not re-block itself (loop guard)"

# --- a project with no dev edits is never blocked -------------------------
CLEAN="$WORK/clean"; mkdir -p "$CLEAN"
CODE=$(run_gate require-tester-pass.sh "{\"cwd\":\"$CLEAN\",\"stop_hook_active\":false}")
assert_eq "$CODE" "0" "a session that changed nothing is not blocked"

# --- Gate 2: string-built SQL --------------------------------------------
sql_case() { run_gate block-raw-sql.sh "$1"; }

CODE=$(sql_case '{"tool_input":{"file_path":"/a/q.go","content":"q := \"SELECT * FROM users WHERE id=\" + id"}}')
assert_eq "$CODE" "2" "concatenated SQL is blocked"

CODE=$(sql_case '{"tool_input":{"file_path":"/a/q.go","new_string":"q := fmt.Sprintf(\"SELECT * FROM t WHERE x=%s\", v)"}}')
assert_eq "$CODE" "2" "Sprintf-built SQL is blocked"

CODE=$(sql_case '{"tool_input":{"file_path":"/a/q.py","content":"cur.execute(f\"SELECT * FROM t WHERE id={uid}\")"}}')
assert_eq "$CODE" "2" "f-string SQL is blocked"

CODE=$(sql_case '{"tool_input":{"file_path":"/a/q.py","content":"sql = \"DELETE FROM sessions WHERE id=\" % uid"}}')
assert_eq "$CODE" "2" "percent-formatted SQL is blocked"

CODE=$(sql_case '{"tool_input":{"file_path":"/a/q.go","content":"db.Query(\"SELECT * FROM users WHERE id = ?\", id)"}}')
assert_eq "$CODE" "0" "parameterized SQL passes"

CODE=$(sql_case '{"tool_input":{"file_path":"/a/q.go","content":"const q = `SELECT id, name FROM users WHERE active = $1`"}}')
assert_eq "$CODE" "0" "a plain SQL constant passes"

CODE=$(sql_case '{"tool_input":{"file_path":"/a/q_test.go","content":"q := \"SELECT * FROM users WHERE id=\" + id"}}')
assert_eq "$CODE" "0" "test files are exempt"

CODE=$(sql_case '{"tool_input":{"file_path":"/a/readme.md","content":"Use SELECT * FROM users to read them."}}')
assert_eq "$CODE" "0" "prose mentioning SQL passes"

# --- gates never block on their own bugs ----------------------------------
CODE=$(run_gate block-raw-sql.sh 'not json at all')
assert_eq "$CODE" "0" "malformed input does not block the tool call"
CODE=$(run_gate require-tester-pass.sh '{}')
assert_eq "$CODE" "0" "missing cwd does not block the session"
CODE=$(run_gate log-edits.sh '{}')
assert_eq "$CODE" "0" "the logger exits cleanly on empty input"

# --- python3 fallback (jq removed from PATH) ------------------------------
BIN="$WORK/bin"; mkdir -p "$BIN"
for t in bash grep cut tail head printf date mkdir dirname cat python3 sh env sed; do
  p=$(command -v "$t") && ln -sf "$p" "$BIN/$t"
done
PROJ2="$WORK/proj2"; mkdir -p "$PROJ2"
printf '%s' "{\"cwd\":\"$PROJ2\",\"agent_type\":\"god-dev\",\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"/q.py\"}}" \
  | PATH="$BIN" "$H/log-edits.sh"
assert_file "$PROJ2/.claude/logs/chain.jsonl" "log-edits works without jq"

printf '%s' "{\"cwd\":\"$PROJ2\",\"stop_hook_active\":false}" | PATH="$BIN" "$H/require-tester-pass.sh" >/dev/null 2>&1
assert_eq "$?" "2" "the PASS gate works without jq"

printf '%s' '{"tool_input":{"file_path":"/a.py","content":"cur.execute(f\"SELECT * FROM t WHERE id={uid}\")"}}' \
  | PATH="$BIN" "$H/block-raw-sql.sh" >/dev/null 2>&1
assert_eq "$?" "2" "the SQL gate works without jq"

finish
