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
assert_file "$WORK/h1/.claude/skills/god-ally/SKILL.md" "the newest skill ships"

# --- installs are idempotent without --force ------------------------------
OUT=$(HOME="$WORK/h1" node "$CLI" -g -y)
assert_contains "$OUT" "already present" "a second install leaves existing skills alone"

# --- selective install, short names, unknown names ------------------------
HOME="$WORK/h2" node "$CLI" build qa -g -y >/dev/null
assert_eq "$(ls "$WORK/h2/.claude/skills" | wc -l | tr -d ' ')" "2" "short names install just those skills"
assert_file "$WORK/h2/.claude/skills/god-build/SKILL.md" "short name 'build' resolves to god-build"
assert_exit 1 "an unknown skill name fails loudly" -- env HOME="$WORK/h3" node "$CLI" nope -g -y

# --all beats a named argument, so `--all build` is still a full install.
HOME="$WORK/h4" node "$CLI" --all build -g -y >/dev/null
assert_eq "$(ls "$WORK/h4/.claude/skills" | wc -l | tr -d ' ')" "$COUNT" "--all overrides named skills"

# --- --force overwrites, plain install does not ---------------------------
echo "tampered" >> "$WORK/h2/.claude/skills/god-build/SKILL.md"
HOME="$WORK/h2" node "$CLI" build -g -y >/dev/null
assert_contains "$(cat "$WORK/h2/.claude/skills/god-build/SKILL.md")" "tampered" \
  "a plain re-install does not clobber local edits"
HOME="$WORK/h2" node "$CLI" build -g -y -f >/dev/null
assert_not_contains "$(cat "$WORK/h2/.claude/skills/god-build/SKILL.md")" "tampered" \
  "--force restores the packaged skill"

# --- retired skills are removed, foreign folders are not -------------------
OLD="$WORK/h5/.claude/skills"; mkdir -p "$OLD/god-tester" "$OLD/god-designer" "$OLD/god-mine"
printf -- '---\nname: god-tester\ndescription: old\n---\n' > "$OLD/god-tester/SKILL.md"
printf -- '---\nname: my-designer\ndescription: the user\x27s own skill in a folder with a retired name\n---\n' > "$OLD/god-designer/SKILL.md"
printf -- '---\nname: god-mine\ndescription: unrelated\n---\n' > "$OLD/god-mine/SKILL.md"
OUT=$(HOME="$WORK/h5" node "$CLI" doctor 2>&1 || true)
assert_contains "$OUT" "retired skill god-tester still installed" "doctor flags a retired skill left on disk"
OUT=$(HOME="$WORK/h5" node "$CLI" -g -y)
assert_contains "$OUT" "retired skill(s) removed" "install reports what it retired"
assert_no_file "$OLD/god-tester/SKILL.md" "a retired skill folder that names itself is removed"
assert_file "$OLD/god-designer/SKILL.md" "a user folder with a retired name but a different skill name is kept"
assert_file "$OLD/god-mine/SKILL.md" "unrelated folders are untouched"
assert_contains "$OUT" "share_learnings" "install tells the user how to opt out of upstream learning PRs"

# --- other CLIs: --codex / --gemini / --agents-md ---------------------------
CX="$WORK/codex"; mkdir -p "$CX"; printf '# My repo\n\nKeep this.\n' > "$CX/AGENTS.md"
(cd "$CX" && node "$CLI" --codex >/dev/null)
assert_file "$CX/.god-skills/god-build/SKILL.md" "--codex copies the skills next to AGENTS.md"
assert_file "$CX/.god-skills/god-qa/references/frontend.md" "--codex copies skill references too"
AG=$(cat "$CX/AGENTS.md")
assert_contains "$AG" "Keep this." "--codex preserves the existing AGENTS.md content"
assert_contains "$AG" "<!-- god-skills:start -->" "--codex writes a marker-delimited block"
assert_eq "$(grep -c '^| \*\*god-' "$CX/AGENTS.md" | tr -d ' ')" "$COUNT" "the index block lists every skill"
assert_contains "$AG" ".god-skills/god-ceo/SKILL.md" "the index points at the copied files"
(cd "$CX" && node "$CLI" --codex >/dev/null)
assert_eq "$(grep -c 'god-skills:start' "$CX/AGENTS.md" | tr -d ' ')" "1" "re-running --codex replaces the block instead of appending"
(cd "$CX" && node "$CLI" --gemini >/dev/null)
assert_file "$CX/GEMINI.md" "--gemini writes GEMINI.md"
(cd "$CX" && node "$CLI" --agents-md .cursor/rules/god.md >/dev/null)
assert_file "$CX/.cursor/rules/god.md" "--agents-md writes any instruction file"

# --- list -----------------------------------------------------------------
LIST=$(node "$CLI" list)
assert_contains "$LIST" "$COUNT skills available" "list counts every skill"
assert_contains "$LIST" "god-ally" "list names the newest skill"

# --- the agent system moved out of this package ---------------------------
HELP=$(node "$CLI" --help)
assert_not_contains "$HELP" "--agents " "the agent flags are gone from god-skills"
assert_contains "$HELP" "npx god-agents" "help points at the god-agents package"

# --- doctor ---------------------------------------------------------------
assert_exit 1 "doctor fails on an install that isn't there" -- env HOME="$WORK/d1" node "$CLI" doctor
assert_exit 0 "doctor passes on a complete install" -- env HOME="$WORK/h1" node "$CLI" doctor

echo "tampered" >> "$WORK/h1/.claude/skills/god-build/SKILL.md"
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

# --- god-qa contract ---------------------------------------------------
# The hook gates grep the lead transcript for `Result: PASS|FAIL|UNVERIFIED`;
# the reply template must keep that token or every session stays blocked.
TESTER=$(cat skills/god-qa/SKILL.md skills/god-qa/references/*.md)
assert_contains "$TESTER" "Result: PASS | FAIL | UNVERIFIED" "god-qa's reply template carries the hook verdict token"
for VP in 390x844 820x1180 1512x982 1440x900; do
  assert_contains "$TESTER" "$VP" "god-qa tests the $VP viewport"
done
assert_contains "$TESTER" "Any **5** → **FAIL**" "god-qa fails the module on a score-5 issue"
assert_contains "$TESTER" "Laid out like god-ally's report" "god-qa's reply follows god-ally's layout"
assert_contains "$TESTER" "Verdict    ✅ Result: PASS" "god-qa's verdict row carries the hook token"
assert_contains "$TESTER" "Manual Test Guide" "god-qa produces the manual curl guide"
for REF in frontend security compliance-india integrity docs; do
  assert_file "skills/god-qa/references/$REF.md" "god-qa ships references/$REF.md"
done
assert_contains "$(cat skills/god-qa/SKILL.md)" "integrity.md\` runs before **every** PASS" "god-qa runs the integrity pass before any PASS"

# --- god-build contract ------------------------------------------------------
DEV=$(cat skills/god-build/SKILL.md)
for MODE in small normal deep; do
  assert_contains "$DEV" "| **$MODE** |" "god-build defines the $MODE mode"
done
assert_contains "$DEV" "User override wins" "god-build lets the user override the mode"
assert_contains "$DEV" "Self-score before handoff" "god-build scores its own diff before god-qa"
assert_contains "$DEV" "returned \`Result: PASS\`" "god-build's done requires god-qa's hook verdict token"
for MEM in "profiles/<repo-slug>.json" "lessons/<repo-slug>.md" "scorecard.jsonl"; do
  assert_contains "$DEV" "$MEM" "god-build keeps $MEM"
done
assert_contains "$DEV" "**🧪 Manual checks**" "god-build's final message carries the manual-checks link"
assert_contains "$DEV" "https://github.com/<owner>/<repo>/pull/<n>" "god-build lists PRs as plain URLs"
assert_contains "$DEV" "run god-qa yourself" "god-build tests by default by running god-qa itself"
assert_contains "$DEV" "never type a verdict god-qa did not return" "god-build may only relay god-qa's real verdict"
assert_contains "$DEV" "## Mode"  "god-build calls it mode, not size"
assert_contains "$DEV" "](https://www.npmjs.com/package/god-skills)" "god-build signs PRs with the god-skills signature"
assert_contains "$DEV" "there is no list to pick from" "the PR signature is written fresh, not drawn from a list"
assert_contains "$DEV" "signatures.jsonl" "god-build remembers signatures so none repeats"
assert_not_contains "$DEV" "set -- \"" "god-build ships no hardcoded signer list"
assert_contains "$DEV" "Laid out like god-ally's report" "god-build's final message follows god-ally's layout"
assert_contains "$DEV" "QA         Result: PASS" "the verdict row carries god-qa's token for the hooks"
assert_contains "$DEV" "boring beats clever" "god-build keeps the body line the agent test pins"
assert_file "skills/god-build/references/architecture.md" "god-build ships the architecture pass"
assert_contains "$DEV" "Remove first" "god-build removes before it adds"
assert_contains "$DEV" "learning-loop.md" "god-build closes with the shared learning loop"

# --- god-ceo / god-cfo / god-cmo contracts --------------------------------
CEO=$(cat skills/god-ceo/SKILL.md skills/god-ceo/references/*.md)
assert_contains "$CEO" '"chain"' "god-ceo declares the JSON chain contract"
for V in BUILD "DO NOT BUILD" DEFER SHIP STOP; do
  assert_contains "$CEO" "**$V**" "god-ceo has the $V verdict"
done
assert_contains "$CEO" "Known fact → Evidence → Inference → Assumption → Unknown" "god-ceo classifies claims before deciding"
assert_contains "$CEO" "Weekly review" "god-ceo runs the weekly review"
for S in god-ceo god-pm god-cmo; do
  assert_contains "$(cat skills/$S/SKILL.md)" "Laid out like god-ally's report" "$S's reply follows god-ally's layout"
done
assert_contains "$(cat skills/god-ally/SKILL.md)" "laid out exactly like the daily report" "god-ally's week view matches the daily report"
assert_contains "$CEO" "Sensei" "god-ceo is the escalation point for stuck skills"
for REF in routing decisions learning-loop; do assert_file "skills/god-ceo/references/$REF.md" "god-ceo ships references/$REF.md"; done
CFO=$(cat skills/god-cfo/SKILL.md)
assert_contains "$CFO" "Pin the definition" "god-cfo pins metric definitions first"
assert_contains "$CFO" "Recompute independently" "god-cfo recomputes money a second way"
assert_contains "$CFO" "Pop questions first" "god-cfo asks quick questions when something is unclear"
assert_contains "$CFO" "Always an example" "god-cfo explains with a worked example"
assert_contains "$CFO" "Always a picture" "god-cfo explains with a graph or illustration"
assert_contains "$CFO" "Laid out like god-ally's report" "god-cfo's reply follows god-ally's layout"
for REF in pricing sql-metrics; do assert_file "skills/god-cfo/references/$REF.md" "god-cfo ships references/$REF.md"; done
WRITER=$(cat skills/god-cmo/SKILL.md)
assert_contains "$WRITER" "## Editor pass" "god-cmo runs the editor pass"
assert_contains "$WRITER" "references/ai-patterns.md" "god-cmo loads the pattern catalog on demand"
assert_file "skills/god-cmo/references/ai-patterns.md" "the AI-pattern catalog ships"
assert_contains "$(cat skills/god-cmo/references/ai-patterns.md)" "## Full Example" "the catalog keeps the worked example"
PM=$(cat skills/god-pm/SKILL.md)
for REF in research ops reverse; do assert_file "skills/god-pm/references/$REF.md" "god-pm ships references/$REF.md"; done
assert_contains "$PM" "filed only after the user says yes" "god-pm files scouted ideas only on a yes"
assert_contains "$PM" "WHO** hits **WHAT** pain **WHEN" "god-pm starts from a problem statement"
ZEN=$(cat skills/god-ally/SKILL.md)
assert_contains "$ZEN" "never leaves the machine, never a PR" "god-ally data stays local"
assert_contains "$ZEN" "ask before continuing" "god-ally asks before work on a strong signal"
assert_contains "$ZEN" "zen-activity.sh" "god-ally names its collector hook"
assert_contains "$ZEN" "Never** diagnoses" "god-ally never diagnoses"
assert_file "skills/god-ally/scripts/zen-report.js" "god-ally ships its daily report script"
assert_file "skills/god-ally/scripts/zen-score.js" "god-ally ships its scoring module"
assert_file "$WORK/h1/.claude/skills/god-ally/scripts/zen-report.js" "the installer copies skill scripts"
for S in god-ceo god-cfo god-cmo god-qa god-build god-pm god-ally; do
  L=$(wc -l < skills/$S/SKILL.md | tr -d ' ')
  [ "$L" -le 150 ] && _ok "$S core stays under 150 lines ($L)" || _fail "$S core stays under 150 lines" "$L lines"
done

# --- the shared learning loop ---------------------------------------------
LOOP=skills/god-ceo/references/learning-loop.md
assert_file "$LOOP" "the learning loop ships inside god-ceo"
LOOPTXT=$(cat "$LOOP")
for SCOPE in universal repo personal; do
  assert_contains "$LOOPTXT" "**$SCOPE**" "the loop defines the $SCOPE scope"
done
assert_contains "$LOOPTXT" "severity × reach × confidence" "the loop scores by value, not by count"
assert_contains "$LOOPTXT" "never a PR, even after 100 sightings" "personal lessons never leave the machine"
assert_contains "$LOOPTXT" "value ≥ 18" "a high-value universal lesson is promoted on first sighting"
assert_contains "$LOOPTXT" '"share_learnings": false' "users can opt out of upstream PRs"
assert_contains "$LOOPTXT" "Never merge" "the loop never merges its own PRs"
assert_file "$WORK/h1/.claude/skills/god-ceo/references/learning-loop.md" "the installer copies skill references"
WF=.github/workflows/test.yml
assert_file "$WF" "CI workflow exists"
assert_contains "$(cat $WF)" "bash test/run.sh" "CI runs the suite"
assert_contains "$(cat $WF)" "'learning'" "CI guards learning PRs"
assert_contains "$(cat $WF)" "Scope: universal" "CI accepts only universal lessons upstream"

finish
