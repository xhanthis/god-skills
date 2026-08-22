#!/usr/bin/env bash
# M1/M2 — agent generation, the installer, and the router contract.
# Everything runs against a scratch HOME so nothing touches the real config.
set -uo pipefail
cd "$(dirname "$0")/.."
. test/harness.sh

CLI="$(pwd)/bin/god-skills.js"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# --- generation is faithful to the manifest -------------------------------
HOME="$WORK/h1" node "$CLI" --agents -g -y >/dev/null
AGENTS="$WORK/h1/.claude/agents"
assert_eq "$(ls "$AGENTS" | grep -c '^god-')" "7" "all seven agents are generated"

# Frontmatter must be parseable YAML. A description containing ': ' silently
# breaks the agent unless quoted, which is exactly how this bug first appeared.
YAML=$(python3 - "$AGENTS" <<'PY'
import glob, sys, yaml
bad = []
for path in sorted(glob.glob(sys.argv[1] + "/god-*.md")):
    text = open(path).read()
    end = text.index("\n---\n", 4)
    try:
        data = yaml.safe_load(text[4:end])
        if set(data) != {"name", "description", "tools", "model"}:
            bad.append(path + " keys=" + str(sorted(data)))
    except Exception as exc:
        bad.append(path + " " + str(exc))
print("OK" if not bad else "BAD " + "; ".join(bad))
PY
)
assert_eq "$YAML" "OK" "every agent has valid, complete YAML frontmatter"

# --- tool restrictions are a security boundary ----------------------------
SEC=$(grep '^tools:' "$AGENTS/god-security.md")
assert_not_contains "$SEC" "Edit" "god-security cannot edit the code it audits"
assert_not_contains "$SEC" "Write" "god-security cannot write files"
assert_not_contains "$(grep '^tools:' "$AGENTS/god-scout.md")" "Edit" "god-scout cannot edit code"
assert_not_contains "$(grep '^tools:' "$AGENTS/god-scout.md")" "Bash" "god-scout cannot run commands"
assert_contains "$(grep '^tools:' "$AGENTS/god-tester.md")" "Edit" "god-tester can edit (it auto-fixes)"
assert_contains "$(grep '^tools:' "$AGENTS/god-architect.md")" "Write" "god-architect can write design docs"

# --- models are pinned, never inherited -----------------------------------
MISSING=$(grep -L '^model:' "$AGENTS"/god-*.md | wc -l | tr -d ' ')
assert_eq "$MISSING" "0" "every agent pins a model explicitly"
assert_contains "$(grep '^model:' "$AGENTS/god-cos.md")" "haiku" "the router runs on a cheap model"

# --- the body comes from the skill, unmodified ----------------------------
assert_contains "$(cat "$AGENTS/god-dev.md")" "boring beats clever" "the agent body is the skill body"
assert_contains "$(cat "$AGENTS/god-dev.md")" "json god-handoff" "the handoff contract is appended"

# --- skills remain the single source of truth -----------------------------
SKILL_LINE=$(grep -c "Core question" skills/god-tester/SKILL.md)
AGENT_LINE=$(grep -c "Core question" "$AGENTS/god-tester.md")
assert_eq "$AGENT_LINE" "$SKILL_LINE" "no duplicated prompt content between skill and agent"

# --- the router command ships with the agents -----------------------------
assert_file "$WORK/h1/.claude/commands/god.md" "the /god command is installed"
assert_contains "$(cat "$WORK/h1/.claude/commands/god.md")" "sequentially from this session" \
  "the router runs the chain from the main session, not nested in cos"
assert_contains "$(cat skills/god-cos/SKILL.md)" '"chain"' "god-cos declares its JSON output contract"

# --- installs are idempotent without --force ------------------------------
OUT=$(HOME="$WORK/h1" node "$CLI" --agents -g -y)
assert_contains "$OUT" "already present" "a second install leaves existing agents alone"

# --- selective install, short names, unknown names ------------------------
HOME="$WORK/h2" node "$CLI" --agents dev tester -g -y >/dev/null
assert_eq "$(ls "$WORK/h2/.claude/agents" | grep -c '^god-')" "2" "short names install just those agents"
assert_file "$WORK/h2/.claude/agents/god-dev.md" "short name 'dev' resolves to god-dev"
assert_exit 1 "an unknown agent name fails loudly" -- env HOME="$WORK/h3" node "$CLI" --agents nope -g -y

# --- dry run writes nothing -----------------------------------------------
HOME="$WORK/h4" node "$CLI" --agents --dry-run >/dev/null
assert_no_file "$WORK/h4/.claude" "--agents --dry-run writes nothing"
HOME="$WORK/h5" node "$CLI" --hooks --dry-run >/dev/null
assert_no_file "$WORK/h5/.claude" "--hooks --dry-run writes nothing"

# --- hooks install and settings merge -------------------------------------
HOME="$WORK/h6" node "$CLI" --hooks >/dev/null
assert_file "$WORK/h6/.claude/hooks/god/require-tester-pass.sh" "hook scripts are installed"
assert_eq "$(stat -c '%a' "$WORK/h6/.claude/hooks/god/require-tester-pass.sh")" "755" "hook scripts are executable"
EVENTS=$(node -e "console.log(Object.keys(require('$WORK/h6/.claude/settings.json').hooks).sort().join(','))")
assert_eq "$EVENTS" "PostToolUse,PreToolUse,Stop,SubagentStop" "all four gate events are registered"

# re-running must not duplicate entries
HOME="$WORK/h6" node "$CLI" --hooks >/dev/null
TOTAL=$(node -e "const h=require('$WORK/h6/.claude/settings.json').hooks;console.log(Object.values(h).reduce((a,g)=>a+g.length,0))")
assert_eq "$TOTAL" "4" "re-running --hooks does not duplicate entries"

# --- existing user settings survive ---------------------------------------
mkdir -p "$WORK/h7/.claude"
cat > "$WORK/h7/.claude/settings.json" <<'EOF'
{"model":"opus","hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"/my/own.sh"}]}]}}
EOF
HOME="$WORK/h7" node "$CLI" --hooks >/dev/null
assert_eq "$(node -e "console.log(require('$WORK/h7/.claude/settings.json').model)")" "opus" \
  "unrelated settings are preserved"
assert_contains "$(cat "$WORK/h7/.claude/settings.json")" "/my/own.sh" "the user's own hooks are preserved"
assert_file "$WORK/h7/.claude/settings.json.bak" "the previous settings are backed up"

# --- a corrupt settings file is never overwritten -------------------------
mkdir -p "$WORK/h8/.claude"
printf '{invalid json' > "$WORK/h8/.claude/settings.json"
HOME="$WORK/h8" node "$CLI" --hooks >/dev/null 2>&1
assert_eq "$?" "1" "a corrupt settings file exits non-zero"
assert_eq "$(cat "$WORK/h8/.claude/settings.json")" "{invalid json" "the corrupt file is left untouched"

# --- the original skill install still works -------------------------------
HOME="$WORK/h9" node "$CLI" -g -y >/dev/null
assert_eq "$(ls "$WORK/h9/.claude/skills" | wc -l | tr -d ' ')" "29" "all 29 skills still install"

# --- doctor ---------------------------------------------------------------
assert_exit 1 "doctor fails on an install that isn't there" -- env HOME="$WORK/d1" node "$CLI" doctor

HOME="$WORK/d2" node "$CLI" --agents -g -y >/dev/null
HOME="$WORK/d2" node "$CLI" --hooks >/dev/null
assert_exit 0 "doctor passes on a complete install" -- env HOME="$WORK/d2" node "$CLI" doctor

# Drift is the failure mode generation exists to prevent, so doctor must catch it.
echo "tampered" >> "$WORK/d2/.claude/agents/god-dev.md"
assert_exit 1 "doctor detects an agent that drifted from its skill" -- env HOME="$WORK/d2" node "$CLI" doctor
OUT=$(HOME="$WORK/d2" node "$CLI" doctor 2>&1 || true)
assert_contains "$OUT" "stale" "doctor names the fix for a stale agent"

finish
