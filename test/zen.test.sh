#!/usr/bin/env bash
# God Ally's daily report: its own node:test suite, plus the contract the skill depends on.
set -uo pipefail
cd "$(dirname "$0")/.."
. test/harness.sh

printf 'god-ally daily report\n'

SCRIPTS=skills/god-ally/scripts
assert_file "$SCRIPTS/zen-report.js" "the report script ships with the skill"
assert_file "$SCRIPTS/zen-score.js" "the scoring module ships with the skill"
assert_file "$SCRIPTS/zen-report.test.js" "the report's own suite ships"

# --- the algorithm, run for real -------------------------------------------
OUT=$(node --test "$SCRIPTS/" 2>&1)
case "$OUT" in
  *"# fail 0"*) _ok "every scoring unit test passes" ;;
  *) _fail "every scoring unit test passes" "$(printf '%s' "$OUT" | grep -E '^not ok|# fail' | head -5)" ;;
esac
assert_contains "$OUT" "the worked example scores exactly 3.3" "the 3.3 worked example is pinned"
assert_contains "$OUT" "00:29 belongs to the previous Zen day" "the 05:00 day boundary is pinned"
assert_contains "$OUT" "caps the score at 5" "the past-midnight cap is pinned"
assert_contains "$OUT" "with every source missing" "a run with no sources at all is covered"

# --- it degrades instead of crashing ---------------------------------------
HOME_DIR=$(mktemp -d)
mkdir -p "$HOME_DIR/.god-ally" "$HOME_DIR/empty"
cat > "$HOME_DIR/.god-ally/config.json" <<JSON
{"repoRoots":["$HOME_DIR/empty"],"maxDepth":2,"authorEmails":["nobody@example.invalid"],"timezone":"Asia/Kolkata","dayStartHour":5,"healthFolder":"$HOME_DIR/nope","useCcusage":false}
JSON
REPORT=$(HOME="$HOME_DIR" node "$SCRIPTS/zen-report.js" --mcp 'not json' 2>&1)
assert_contains "$REPORT" "Zen Score" "the report prints without a single source"
assert_contains "$REPORT" "missing " "the footer names the missing sources"
assert_contains "$REPORT" "apple health sleep" "a missing Health folder is named, not fatal"
assert_not_contains "$REPORT" "🧘 \"" "the report itself carries no quote"
assert_contains "$REPORT" "taller is better" "the chart says which direction is good"
assert_contains "$REPORT" "Last 7 days" "the chart covers seven days"
assert_file "$HOME_DIR/.god-ally/history.jsonl" "the first run writes history"
NUMBERS_ONLY=$(grep -c '"date"' "$HOME_DIR/.god-ally/history.jsonl" 2>/dev/null || echo 0)
[ "$NUMBERS_ONLY" -ge 30 ] && _ok "the first run backfills 30 days" || _fail "the first run backfills 30 days" "$NUMBERS_ONLY lines"
assert_not_contains "$(cat "$HOME_DIR/.god-ally/history.jsonl")" "message" "history holds numbers, never content"
JSON_OUT=$(HOME="$HOME_DIR" node "$SCRIPTS/zen-report.js" --json 2>&1)
assert_contains "$JSON_OUT" '"sources"' "--json returns the same run as data"
LINE=$(HOME="$HOME_DIR" node "$SCRIPTS/zen-report.js" --line 2>&1)
assert_eq "$(printf '%s' "$LINE" | grep -c .)" "1" "--line prints exactly one line"
assert_contains "$LINE" "🧘 " "the status line carries the god-ally marker"
assert_contains "$LINE" "today · intensity" "the status line names today's spend and intensity"
assert_contains "$LINE" "Zen " "the status line carries the Zen Score"
rm -rf "$HOME_DIR"

# --- what the skill promises -----------------------------------------------
ZEN=$(cat skills/god-ally/SKILL.md)
assert_contains "$ZEN" "zen-report.js" "the skill names the report script"
assert_contains "$ZEN" "Never ask the user anything" "the report stays passive"
assert_contains "$ZEN" '"meetings"' "the skill documents the MCP payload"
assert_contains "$ZEN" "never message or event content" "MCP gathering is timestamps only"
assert_contains "$ZEN" "fenced code block" "the report is printed as a code block so it stays aligned"
assert_contains "$ZEN" "zen-report.js --quote" "the skill can fetch just the motivational line"
assert_contains "$ZEN" "zen-report.js --line" "the skill documents the status line every skill prints"
assert_contains "$ZEN" "never by hand" "the status line is computed by the script, never typed"
assert_contains "$ZEN" "never carries a quote" "/god-ally itself stays free of quotes"
assert_contains "$ZEN" "Never write a line the script did not ask for" "a quote only when the script asks for one"
assert_contains "$ZEN" "There is no quote bank" "lines are written fresh for the moment"
assert_contains "$ZEN" "--quote-said" "a shown line is recorded so it is never reused"
[ ! -e "$SCRIPTS/quotes.json" ] && _ok "no hardcoded quote bank ships" || _fail "no hardcoded quote bank ships" "quotes.json exists"

# --- the motivational line, on a home with no history at all ----------------
QUOTE_HOME=$(mktemp -d)
QUOTE=$(HOME="$QUOTE_HOME" node "$SCRIPTS/zen-report.js" --quote --force 2>&1)
assert_contains "$QUOTE" "brief · mood" "--quote returns a brief for a fresh line"
HOME="$QUOTE_HOME" node "$SCRIPTS/zen-report.js" --quote-said '🧘 "Log off; tomorrow needs you rested."' >/dev/null
AGAIN=$(HOME="$QUOTE_HOME" node "$SCRIPTS/zen-report.js" --quote --force 2>&1)
assert_eq "$AGAIN" '🧘 "Log off; tomorrow needs you rested."' "the same day repeats the line already shown"
assert_file "$QUOTE_HOME/.god-ally/quotes-seen.json" "the line is remembered so it is not reused"
GATED=$(HOME="$QUOTE_HOME" node "$SCRIPTS/zen-report.js" --quote 2>&1)
assert_eq "$GATED" "" "without --force a line just shown is withheld"
rm -rf "$QUOTE_HOME"

README=$(cat README.md)
assert_contains "$README" "cleanupPeriodDays" "the README tells users to keep more log history"
assert_contains "$README" "Find Health Samples" "the README carries the iOS Shortcut steps"
assert_contains "$README" "Run Immediately" "the Shortcut never prompts"

finish
