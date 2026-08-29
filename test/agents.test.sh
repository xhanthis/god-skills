#!/usr/bin/env bash
# god-agents — agent generation, the installer, the hook gates, the router contract.
# Everything runs against a scratch HOME so nothing touches the real config.
set -uo pipefail
cd "$(dirname "$0")/.."
. test/harness.sh

CLI="$(pwd)/god-agents/bin/god-agents.js"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# --- generation is faithful to the manifest -------------------------------
HOME="$WORK/h1" node "$CLI" -g -y >/dev/null
AGENTS="$WORK/h1/.claude/agents"
assert_eq "$(ls "$AGENTS" | grep -c '^god-')" "8" "all eight agents are generated"

# Frontmatter must be parseable YAML. A description containing ': ' silently
# breaks the agent unless quoted, which is exactly how this bug first appeared.
# Checked in node so the suite stays dependency-free: the generator emits a JSON
# double-quoted scalar, which is the only form that survives a ': ' in the text.
YAML=$(node -e '
const fs = require("fs"), path = require("path");
const dir = process.argv[1];
const bad = [];
for (const file of fs.readdirSync(dir).filter((f) => /^god-.*\.md$/.test(f)).sort()) {
  const text = fs.readFileSync(path.join(dir, file), "utf8");
  const end = text.indexOf("\n---\n", 4);
  if (!text.startsWith("---\n") || end === -1) { bad.push(file + " no frontmatter"); continue; }
  const keys = [];
  for (const line of text.slice(4, end).split("\n")) {
    const match = line.match(/^([a-z]+): (.*)$/);
    if (!match) { bad.push(file + " unparseable line: " + line); continue; }
    keys.push(match[1]);
    if (match[1] === "description") {
      if (!match[2].startsWith("\"")) { bad.push(file + " description is not a quoted scalar"); continue; }
      try { JSON.parse(match[2]); } catch (e) { bad.push(file + " description " + e.message); }
    } else if (match[2].includes(": ")) {
      bad.push(file + " unquoted \": \" in " + match[1]);
    }
  }
  const want = ["description", "model", "name", "tools"].join(",");
  if (keys.slice().sort().join(",") !== want) bad.push(file + " keys=" + keys.sort().join(","));
}
console.log(bad.length ? "BAD " + bad.join("; ") : "OK");
' "$AGENTS")
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
OUT=$(HOME="$WORK/h1" node "$CLI" -g -y)
assert_contains "$OUT" "already present" "a second install leaves existing agents alone"

# --- selective install, short names, unknown names ------------------------
HOME="$WORK/h2" node "$CLI" dev tester -g -y >/dev/null
assert_eq "$(ls "$WORK/h2/.claude/agents" | grep -c '^god-')" "2" "short names install just those agents"
assert_file "$WORK/h2/.claude/agents/god-dev.md" "short name 'dev' resolves to god-dev"
assert_exit 1 "an unknown agent name fails loudly" -- env HOME="$WORK/h3" node "$CLI" nope -g -y

# --- dry run writes nothing -----------------------------------------------
HOME="$WORK/h4" node "$CLI" --dry-run >/dev/null
assert_no_file "$WORK/h4/.claude" "--dry-run writes nothing"
HOME="$WORK/h5" node "$CLI" --hooks --dry-run >/dev/null
assert_no_file "$WORK/h5/.claude" "--hooks --dry-run writes nothing"

# --- hooks install and settings merge -------------------------------------
HOME="$WORK/h6" node "$CLI" --hooks >/dev/null
GATE="$WORK/h6/.claude/hooks/god/require-tester-pass.sh"
assert_file "$GATE" "hook scripts are installed"
assert_no_file "$WORK/h6/.claude/agents" "--hooks alone does not install agents"
MODE=$(node -e "console.log((require('fs').statSync(process.argv[1]).mode & 0o777).toString(8))" "$GATE")
assert_eq "$MODE" "755" "hook scripts are executable"
EVENTS=$(node -e "console.log(Object.keys(require('$WORK/h6/.claude/settings.json').hooks).sort().join(','))")
assert_eq "$EVENTS" "PostToolUse,PreToolUse,Stop,SubagentStop" "all four gate events are registered"

# re-running must not duplicate entries
HOME="$WORK/h6" node "$CLI" --hooks >/dev/null
TOTAL=$(node -e "const h=require('$WORK/h6/.claude/settings.json').hooks;console.log(Object.values(h).reduce((a,g)=>a+g.length,0))")
assert_eq "$TOTAL" "4" "re-running --hooks does not duplicate entries"

# --- --all installs agents and hooks in one pass ---------------------------
HOME="$WORK/hA" node "$CLI" --all -g -y >/dev/null
assert_file "$WORK/hA/.claude/agents/god-dev.md" "--all installs the agents"
assert_file "$WORK/hA/.claude/hooks/god/require-tester-pass.sh" "--all installs the hook gates"

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

# --- runtime scaffold ------------------------------------------------------
node "$CLI" runtime "$WORK/rt" >/dev/null
assert_file "$WORK/rt/run.sh" "runtime scaffold copies the runner"
assert_file "$WORK/rt/linear/client.sh" "runtime scaffold copies the linear client"
RT_MODE=$(node -e "console.log((require('fs').statSync(process.argv[1]).mode & 0o111).toString(8))" "$WORK/rt/run.sh")
assert_not_contains "$RT_MODE" "0" "the scaffolded runner stays executable"
assert_exit 1 "runtime refuses a non-empty target" -- node "$CLI" runtime "$WORK/rt"
assert_exit 1 "runtime without a target fails loudly" -- node "$CLI" runtime

# --- doctor ---------------------------------------------------------------
assert_exit 1 "doctor fails on an install that isn't there" -- env HOME="$WORK/d1" node "$CLI" doctor

HOME="$WORK/d2" node "$CLI" --all -g -y >/dev/null
assert_exit 0 "doctor passes on a complete install" -- env HOME="$WORK/d2" node "$CLI" doctor

# Drift is the failure mode generation exists to prevent, so doctor must catch it.
echo "tampered" >> "$WORK/d2/.claude/agents/god-dev.md"
assert_exit 1 "doctor detects an agent that drifted from its skill" -- env HOME="$WORK/d2" node "$CLI" doctor
OUT=$(HOME="$WORK/d2" node "$CLI" doctor 2>&1 || true)
assert_contains "$OUT" "stale" "doctor names the fix for a stale agent"

# --- every manifest agent has a skill to generate from --------------------
ORPHANS=$(node -e '
const fs = require("fs");
const manifest = JSON.parse(fs.readFileSync("god-agents/agents/manifest.json", "utf8"));
console.log(Object.keys(manifest).filter((n) => !fs.existsSync("skills/" + n + "/SKILL.md")).join(",") || "none");
')
assert_eq "$ORPHANS" "none" "every manifest agent maps to a shipped skill"

finish
