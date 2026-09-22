#!/usr/bin/env bash
# god-ally's data collector. Runs on SessionStart, UserPromptSubmit and Stop.
# Appends one line per event to ~/.claude/god/god-ally/activity.jsonl so god-ally can learn
# the user's hours, breaks and sleep window without reading transcripts. On a prompt it also
# reads next.json (written by god-ally at its last close) and, when the next meeting is close or
# the user is past their stop target, injects a one-line reminder that god-ally must ask before
# the work starts. Never blocks; any failure exits 0 silently.
set -u
. "$(dirname "$0")/lib.sh"

DIR="${GOD_ALLY_DIR:-$HOME/.claude/god/god-ally}"
mkdir -p "$DIR" 2>/dev/null || exit 0
NOW=$(date +%s)
EVENT=$(hook_field .hook_event_name)
case "$EVENT" in
  SessionStart) KIND=session_start ;;
  UserPromptSubmit) KIND=prompt ;;
  Stop) KIND=stop ;;
  *) KIND=other ;;
esac
CWD=$(hook_field .cwd | tr -d '\n\r\t')
CWD=${CWD//\\/\\\\}
CWD=${CWD//\"/\\\"}
printf '{"ts":%s,"event":"%s","cwd":"%s"}\n' "$NOW" "$KIND" "$CWD" >> "$DIR/activity.jsonl" 2>/dev/null

[ "$KIND" = "prompt" ] || exit 0
NEXT="$DIR/next.json"
[ -f "$NEXT" ] || exit 0
[ -f "$DIR/off-$(date +%F)" ] && exit 0

field() { HOOK_INPUT=$(cat "$NEXT") hook_field ".$1"; }
QUIET=$(field quiet_until); [ -n "$QUIET" ] && [ "$QUIET" -gt "$NOW" ] 2>/dev/null && exit 0

MSG=""
MEET=$(field next_meeting_ts)
if [ -n "$MEET" ] && [ "$MEET" -gt "$NOW" ] 2>/dev/null; then
  MIN=$(( (MEET - NOW) / 60 ))
  [ "$MIN" -le 15 ] && MSG="meeting in $MIN min"
fi
STOP=$(field stop_after)
if [ -n "$STOP" ] && [ "$(date +%H:%M)" \> "$STOP" ]; then
  MSG="${MSG:+$MSG; }past your stop time ($STOP)"
fi
[ -n "$MSG" ] || exit 0

printf '%s' "{\"hookSpecificOutput\":{\"hookEventName\":\"UserPromptSubmit\",\"additionalContext\":\"god-ally: $MSG. Before starting, ask in one line whether to continue now; the answer stands for the rest of the day.\"}}"
exit 0
