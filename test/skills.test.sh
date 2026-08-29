#!/usr/bin/env bash
# god-skills — the skill installer, list, and doctor.
# Everything runs against a scratch HOME so nothing touches the real config.
set -uo pipefail
cd "$(dirname "$0")/.."
. test/harness.sh

CLI="$(pwd)/bin/god-skills.js"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

COUNT=$(ls -d skills/*/ | wc -l | tr -d ' ')

# --- the package version is what publishes --------------------------------
assert_eq "$(node "$CLI" --version)" "$(node -e "console.log(require('./package.json').version)")" \
  "--version reports the package version"

# --- install --------------------------------------------------------------
HOME="$WORK/h1" node "$CLI" -g -y >/dev/null
assert_eq "$(ls "$WORK/h1/.claude/skills" | wc -l | tr -d ' ')" "$COUNT" "every skill installs"
assert_file "$WORK/h1/.claude/skills/god-reverse/SKILL.md" "the newest skill ships"

# --- installs are idempotent without --force ------------------------------
OUT=$(HOME="$WORK/h1" node "$CLI" -g -y)
assert_contains "$OUT" "already present" "a second install leaves existing skills alone"

# --- selective install, short names, unknown names ------------------------
HOME="$WORK/h2" node "$CLI" dev tester -g -y >/dev/null
assert_eq "$(ls "$WORK/h2/.claude/skills" | wc -l | tr -d ' ')" "2" "short names install just those skills"
assert_file "$WORK/h2/.claude/skills/god-dev/SKILL.md" "short name 'dev' resolves to god-dev"
assert_exit 1 "an unknown skill name fails loudly" -- env HOME="$WORK/h3" node "$CLI" nope -g -y

# --all beats a named argument, so `--all dev` is still a full install.
HOME="$WORK/h4" node "$CLI" --all dev -g -y >/dev/null
assert_eq "$(ls "$WORK/h4/.claude/skills" | wc -l | tr -d ' ')" "$COUNT" "--all overrides named skills"

# --- --force overwrites, plain install does not ---------------------------
echo "tampered" >> "$WORK/h2/.claude/skills/god-dev/SKILL.md"
HOME="$WORK/h2" node "$CLI" dev -g -y >/dev/null
assert_contains "$(cat "$WORK/h2/.claude/skills/god-dev/SKILL.md")" "tampered" \
  "a plain re-install does not clobber local edits"
HOME="$WORK/h2" node "$CLI" dev -g -y -f >/dev/null
assert_not_contains "$(cat "$WORK/h2/.claude/skills/god-dev/SKILL.md")" "tampered" \
  "--force restores the packaged skill"

# --- list -----------------------------------------------------------------
LIST=$(node "$CLI" list)
assert_contains "$LIST" "$COUNT skills available" "list counts every skill"
assert_contains "$LIST" "god-reverse" "list names the newest skill"

# --- the agent system moved out of this package ---------------------------
HELP=$(node "$CLI" --help)
assert_not_contains "$HELP" "--agents" "the agent flags are gone from god-skills"
assert_contains "$HELP" "npx god-agents" "help points at the god-agents package"

# --- doctor ---------------------------------------------------------------
assert_exit 1 "doctor fails on an install that isn't there" -- env HOME="$WORK/d1" node "$CLI" doctor
assert_exit 0 "doctor passes on a complete install" -- env HOME="$WORK/h1" node "$CLI" doctor

echo "tampered" >> "$WORK/h1/.claude/skills/god-dev/SKILL.md"
assert_exit 1 "doctor detects a skill that drifted from the package" -- env HOME="$WORK/h1" node "$CLI" doctor
OUT=$(HOME="$WORK/h1" node "$CLI" doctor 2>&1 || true)
assert_contains "$OUT" "stale" "doctor names the fix for a stale skill"

# --- every skill is loadable ----------------------------------------------
BAD=$(node -e '
const fs = require("fs");
const bad = [];
for (const name of fs.readdirSync("skills")) {
  const file = "skills/" + name + "/SKILL.md";
  if (!fs.existsSync(file)) { bad.push(name + " has no SKILL.md"); continue; }
  const text = fs.readFileSync(file, "utf8");
  if (!text.startsWith("---\n")) { bad.push(name + " has no frontmatter"); continue; }
  const end = text.indexOf("\n---\n", 4);
  if (end === -1) { bad.push(name + " has an unterminated frontmatter"); continue; }
  const head = text.slice(4, end);
  if (!/^name:\s*\S/m.test(head)) bad.push(name + " has no name");
  if (!/^description:\s*\S/m.test(head)) bad.push(name + " has no description");
}
console.log(bad.length ? "BAD " + bad.join("; ") : "OK");
')
assert_eq "$BAD" "OK" "every skill has a name and a description"

# --- the published tarball carries the skills, not the agent package ------
MANIFEST=$(npm pack --dry-run --json 2>/dev/null | node -e '
let raw = "";
process.stdin.on("data", (c) => (raw += c));
process.stdin.on("end", () => {
  const files = JSON.parse(raw)[0].files.map((f) => f.path);
  const skills = files.filter((f) => f.startsWith("skills/")).length;
  const leaked = files.filter((f) => f.startsWith("god-agents/") || f.startsWith("test/"));
  console.log(skills > 0 && leaked.length === 0 ? "OK" : "BAD leaked=" + leaked.join(","));
});
')
assert_eq "$MANIFEST" "OK" "the tarball ships skills and excludes the god-agents package"

finish
