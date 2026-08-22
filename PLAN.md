# God Agents — v1 Build Plan (final)

This document is the complete, self-contained spec for converting the `god-skills`
package (29 reactive Claude Code skills) into an agent system: isolated subagents
with triggers and tool restrictions, deterministic hook enforcement, and a scheduled
headless runner with persistent state in Linear.

The builder needs no prior conversation context. Everything to build is in this file.

---

## What exists today

- `skills/` — 29 skill folders, each a single `SKILL.md` with YAML frontmatter
  (`name`, `description`) and a prompt body. The bodies are good; do not rewrite them.
- `bin/god-skills.js` — zero-dependency Node installer (`npx god-skills`), with
  scope prompts (`--global`/`--project`), `--force`, `--all`, `list`.
- Published npm package `god-skills` v2.x, public repo, MIT.

## The core problem this system solves

A skill is stateless. It forgets. An agent that reports "found 12 issues" every
night without knowing it already reported them is noise inside a week.

**Every autonomous run must read Linear before it writes to Linear.**
This is the single most important requirement in this document. It is milestone
M4 and it must work before the nightly runner (M5) ever executes.

---

## Locked decisions

| Decision | Choice |
|---|---|
| v1 scope | Engineering chain: architect → dev → tester → security (+ cos router, police gate, scout) |
| Orchestrator | Hybrid: `god-cos` returns a JSON plan; the main session executes the chain |
| Autonomous runtime | Mac, `launchd` (fires on wake; cron misses sleeping Macs) |
| Findings store | Linear, dedicated **God Agents** team |
| Headless autonomy | Fix + open PR (never touches `main`) |
| Target repos | SaffronStays (Go backend + admin_app): nightly tester. Ownspce (React Native): scout only, read-only — no cheap headless E2E path exists |
| Repo split | Public layer (agents, hooks, installer, templates) lives in **this repo**. Private runtime (`~/.god-agents`: prompts with business context, launchd, Linear config) lives in a separate **private** repo `xhanthis/god-agents-runtime`, seeded from `runtime-template/` shipped here |
| Agent authoring | Agents are **generated** from `skills/*/SKILL.md` + `agents/manifest.json` at install time. One source of truth, zero drift. Never hand-maintain duplicate bodies |
| Skills | Keep shipping unchanged. Skills remain the knowledge layer; agents are a thin execution wrapper |

### Previously open questions — now resolved

1. **Scout inputs:** codebase + Linear backlog (mandatory — including closed scout
   issues) + Mixpanel when available. Live web search is mandatory for any High-tier
   finding. Codebase-only scout is not acceptable; it would re-propose planned work.
2. **Chain state passing:** structured handoff schema (see "Handoff protocol"), not
   full prior output. Full transcripts go to the chain log for god-police to sample;
   the next agent receives only the handoff JSON blocks so far plus `git diff`.
   Cheaper and more reliable at depth.
3. **Cost ceiling:** hard dollar cap in `run.sh`, read from `total_cost_usd` in the
   `claude -p --output-format json` result, accumulated across repos. Default $10/night
   (`GOD_COST_CAP` env). On breach: abort remaining repos, notify, file a Linear issue.
   **No silent model downgrade** — predictable behavior beats clever degradation.
4. **Failure notification:** `run.sh` traps errors → macOS notification via
   `osascript` + a Linear issue labeled `god-runner-failure` with the log tail.
   A `logs/last-success` timestamp file makes silent-death detectable.

---

## Architecture

```
LAYER 1  Subagents        ~/.claude/agents/*.md      generated; isolated context
LAYER 2  Hooks            ~/.claude/settings.json    deterministic enforcement
LAYER 3  Headless runner  launchd + claude -p        scheduled, unattended

PUBLIC   xhanthis/god-skills          skills/ agents/ hooks/ commands/ runtime-template/ bin/
PRIVATE  xhanthis/god-agents-runtime  → cloned to ~/.god-agents (user creates from template)
```

---

# Part A — changes to this repo (everything the builder implements)

## A1. `agents/manifest.json`

Per-agent frontmatter that the installer merges with the corresponding
`skills/<name>/SKILL.md` body. The manifest is the **only** place agent frontmatter
is authored. Descriptions here override the skill's description — they are routing
signals ("when to invoke", with PROACTIVELY / MUST BE USED), not summaries.

```json
{
  "god-cos": {
    "description": "Router for the God ecosystem. Use PROACTIVELY on any multi-step or multi-domain request to decide which specialists run and in what order. Returns a strict JSON plan only — it never implements anything itself.",
    "tools": "Agent, Read, Grep, Glob",
    "model": "haiku"
  },
  "god-architect": {
    "description": "System design before implementation. MUST BE USED before god-dev for any change involving a new module, schema change, new endpoint, or cross-service behavior. Writes design docs only — never source code.",
    "tools": "Read, Grep, Glob, Write",
    "model": "opus"
  },
  "god-dev": {
    "description": "Implements code to senior-engineer standards. Use PROACTIVELY whenever code will be written, modified, refactored, or optimized. Work is not done until god-tester has returned PASS.",
    "tools": "Read, Write, Edit, Grep, Glob, Bash",
    "model": "opus"
  },
  "god-tester": {
    "description": "Senior QA. MUST BE USED after god-dev completes any implementation, and whenever code needs verification. Writes and actually executes tests, auto-fixes failures up to 3 cycles, returns PASS / FAIL / UNVERIFIED.",
    "tools": "Read, Write, Edit, Bash, Grep, Glob",
    "model": "opus"
  },
  "god-security": {
    "description": "Security review. MUST BE USED after god-tester whenever changes touch auth, payments, PII, secrets handling, or external input. Read-only: reports findings, never edits the code it audits.",
    "tools": "Read, Grep, Glob",
    "model": "opus"
  },
  "god-police": {
    "description": "Integrity audit. Use before any final PASS or SHIP verdict to detect shortcuts, fabricated evidence, false test claims, and gamed objectives. Re-runs one test and re-checks one citation.",
    "tools": "Read, Grep, Bash",
    "model": "sonnet"
  },
  "god-scout": {
    "description": "Weekly opportunity intelligence. Use for evidence-first scanning of the codebase, analytics, and backlog for extraction, compounding, repetition, and abandonment patterns. Read-only; never writes code or opens PRs.",
    "tools": "Read, Grep, Glob, WebSearch",
    "model": "opus"
  }
}
```

Notes:
- `model` uses aliases (`opus`, `sonnet`, `haiku`) — valid frontmatter values.
  Set explicitly on every agent: subagents otherwise inherit the lead's model,
  which silently burns Opus on triage.
- `tools` is a security boundary, not a convenience. god-security being unable to
  edit the code it audits is non-negotiable.
- god-cos keeps `Agent` only as a fallback for deep sub-investigations (nesting
  depth cap is 5); the primary flow is plan-and-return (see A5).

## A2. Installer: generation + new flags (`bin/god-skills.js`)

Extend the existing installer. Keep zero dependencies and existing behavior intact.

**`npx god-skills --agents [names...]`**
- For each requested agent in the manifest (all, if none named; short names resolve
  like skills): generate `<name>.md` =
  1. YAML frontmatter: `name` + manifest fields.
  2. The `skills/<name>/SKILL.md` body with its own frontmatter stripped.
  3. The handoff-protocol block (A3), appended verbatim.
- Install to `~/.claude/agents/` or `./.claude/agents/` (reuse existing
  scope-prompt / `--global` / `--project` / `--force` logic).
- Also installs `commands/god.md` → `<scope>/.claude/commands/god.md`.
- `--dry-run` prints generated files to stdout without writing.

**`npx god-skills --hooks`**
- Copies `hooks/god/*.sh` → `~/.claude/hooks/god/` (chmod +x).
- Merges `hooks/settings-snippet.json` into `~/.claude/settings.json`:
  back up to `settings.json.bak` first; add only entries not already present
  (match on command path); if the existing file fails to parse, do NOT write —
  print the snippet and manual instructions instead.

Update `prepublishOnly` to also run `node bin/god-skills.js --agents --dry-run > /dev/null`.
Update README: short "Agents" section documenting both flags.

## A3. Handoff protocol (appended to every generated agent)

```markdown
## Handoff (mandatory)

End your final message with exactly one fenced block:

```json god-handoff
{
  "agent": "<your name>",
  "status": "done | blocked | fail",
  "summary": "<max 3 lines, plain language>",
  "files": ["paths you changed or reviewed"],
  "verdict": "PASS | FAIL | UNVERIFIED | null",
  "route": "<next agent, or null>"
}
```

Only god-tester and god-police may set a non-null verdict. Never claim a verdict
for a test you did not run.
```

## A4. `hooks/` — deterministic gates

Prompts can be ignored; hooks cannot. Hooks fire recursively inside subagents, so
gates apply to every specialist automatically. All scripts read the hook input JSON
from stdin (fields include `tool_input`, `transcript_path`, `agent_type`,
`stop_hook_active`); use `jq` if present, else `python3 -c`. Exit 2 = block, with
the reason on stderr.

**`hooks/god/log-edits.sh`** — Gate 3, audit trail. `PostToolUse` on `Edit|Write`.
Appends `{ts, agent_type, tool, file}` to `.claude/logs/chain.jsonl` in the project
(`mkdir -p` first). This log is what god-police samples and what Gate 1 reads.

**`hooks/god/record-verdict.sh`** — `SubagentStop` matched to `god-tester`.
Greps the transcript at `transcript_path` for the last `Result: PASS|FAIL|UNVERIFIED`
and appends `{ts, agent_type: "god-tester", verdict}` to `chain.jsonl`.

**`hooks/god/require-tester-pass.sh`** — Gate 1: dev cannot self-declare done.
**Design change from the draft plan, deliberate:** this runs on the lead session's
`Stop` event, NOT on god-dev's `SubagentStop`. Blocking god-dev's stop would
deadlock — tester runs *after* dev finishes, and dev has no Agent tool to spawn it.
The lead session does. Logic: if `chain.jsonl` contains god-dev edit entries with no
god-tester PASS entry newer than the newest of them → exit 2 with
`"god-dev changes lack a god-tester PASS. Run god-tester before finishing."`
Loop guard: if `stop_hook_active` is true in the hook input, exit 0.

**`hooks/god/block-raw-sql.sh`** — Gate 2. `PreToolUse` on `Edit|Write`.
Scans `tool_input.content` / `new_string` for string-concatenated or interpolated
SQL (`"SELECT/INSERT/UPDATE/DELETE ..."` adjacent to `+`, `%`, f-string/template
interpolation, `fmt.Sprintf` with a SQL verb). Keep the regex conservative — a
false positive that blocks legitimate edits erodes trust in every gate. Skip files
matching `*_test.*` and `*test*`. Exit 2 with the offending line in stderr.

**`hooks/settings-snippet.json`** — the config the installer merges:

```json
{
  "hooks": {
    "PreToolUse": [
      { "matcher": "Edit|Write", "hooks": [
        { "type": "command", "command": "$HOME/.claude/hooks/god/block-raw-sql.sh", "timeout": 15 } ] }
    ],
    "PostToolUse": [
      { "matcher": "Edit|Write", "hooks": [
        { "type": "command", "command": "$HOME/.claude/hooks/god/log-edits.sh", "timeout": 10 } ] }
    ],
    "SubagentStop": [
      { "matcher": "god-tester", "hooks": [
        { "type": "command", "command": "$HOME/.claude/hooks/god/record-verdict.sh", "timeout": 15 } ] }
    ],
    "Stop": [
      { "matcher": "*", "hooks": [
        { "type": "command", "command": "$HOME/.claude/hooks/god/require-tester-pass.sh", "timeout": 15 } ] }
    ]
  }
}
```

## A5. `commands/god.md` — the entry point

A slash command (`/god <request>`) instructing the lead session:

1. Spawn `god-cos` with the request. cos returns strict JSON:
   `{"chain": ["god-architect", "god-dev", "god-tester"], "reason": "..."}`
   (Add a short "Output contract" section to `skills/god-cos/SKILL.md` specifying
   this JSON — the one permitted skill-body edit in this project.)
2. Parse the chain. Execute each agent **sequentially from the main session**,
   passing: the original request, all handoff blocks so far, and current `git diff`.
   This keeps specialist output visible instead of buried under cos's summary.
3. Failure loop: tester FAIL → back to god-dev → god-tester, max 3 cycles, then stop
   and report what is still broken.
4. If any agent issued a verdict, run god-police last.
5. Fallback: if cos returns unparseable output, retry once, then ask the user.

## A6. `runtime-template/` — sanitized seed for the private repo

Everything here uses `{{PLACEHOLDERS}}` — **no business context** (no KRAs, repo
paths, Linear team IDs) may appear in this public repo.

```
runtime-template/
  README.md                        # setup: clone to ~/.god-agents, fill placeholders,
                                   #   set LINEAR_API_KEY, launchctl bootstrap both plists
  run.sh                           # nightly tester driver (below)
  run-scout.sh                     # weekly scout driver (same skeleton, scout prompt, no PR step)
  com.{{USER}}.godagents.plist     # StartCalendarInterval daily 02:00 → run.sh
  com.{{USER}}.godscout.plist      # StartCalendarInterval Weekday=1 03:00 → run-scout.sh
  prompts/
    nightly-tester.md              # full protocol below + {{REPO_CONTEXT}} placeholder
    weekly-scout.md                # full scout spec below + {{KRA_CONTEXT}} placeholder
  linear/
    client.sh                      # search-then-write wrapper (Part C)
```

**`run.sh` — guardrails are shell-enforced, not prompt-enforced:**

```bash
#!/usr/bin/env bash
set -uo pipefail
ROOT="$HOME/.god-agents"
[ -f "$ROOT/PAUSE" ] && exit 0                      # kill switch
COST_CAP="${GOD_COST_CAP:-10}"                       # USD per night
TOTAL=0; DATE=$(date +%F); LOG="$ROOT/logs/$DATE.jsonl"
mkdir -p "$ROOT/logs"

fail() {
  osascript -e "display notification \"$1\" with title \"god-agents\""
  "$ROOT/linear/client.sh" runner-failure "$1" "$LOG"
}
trap 'fail "nightly run crashed (exit $?)"' ERR

for repo in {{REPO_PATHS}}; do
  cd "$repo" || continue
  git fetch --all --quiet
  git checkout -B "god/nightly-$DATE" "origin/{{DEFAULT_BRANCH}}"   # never on main
  OUT=$(claude -p "$(cat "$ROOT/prompts/nightly-tester.md")" --output-format json 2>>"$LOG")
  printf '%s\n' "$OUT" >> "$LOG"
  COST=$(printf '%s' "$OUT" | jq -r '.total_cost_usd // 0')
  TOTAL=$(echo "$TOTAL + $COST" | bc)
  if [ "$(echo "$TOTAL > $COST_CAP" | bc)" = 1 ]; then
    fail "cost cap \$$COST_CAP hit at \$$TOTAL — remaining repos skipped"; break
  fi
  N=$(gh pr list --search "head:god/nightly-$DATE" --json number --jq length)
  [ "$N" -gt 3 ] && fail "$repo opened $N PRs tonight (cap 3) — review before next run"
done
date +%s > "$ROOT/logs/last-success"
```

**`prompts/nightly-tester.md` must encode:**
- One concern per PR; a PR touching 9 unrelated files never gets reviewed.
- A PR opens ONLY if the full suite passes. If tests fail and the fix isn't safe,
  file a Linear issue via `~/.god-agents/linear/client.sh` and abandon the branch.
- Max 3 PRs (the shell verifies post-hoc; the prompt is the first line of defense).
- The Linear write protocol (Part C) verbatim.
- **Read Linear before writing to Linear.** Search every fingerprint first.

---

# Part B — private repo (user performs; builder ships the template)

1. Create private repo `xhanthis/god-agents-runtime`; copy `runtime-template/` in.
2. Fill placeholders: repo paths (SaffronStays backend, admin_app, Ownspce),
   default branches, Linear team ID for the **God Agents** team, FY27 KRA context
   in `weekly-scout.md`, macOS username in plists.
3. Clone to `~/.god-agents`, `export LINEAR_API_KEY` (or read from Keychain in
   `client.sh`), `launchctl bootstrap gui/$UID` both plists.
4. Kill switch: `touch ~/.god-agents/PAUSE`. Delete the file to resume.

---

# Part C — Linear integration + dedup

Headless caveat: interactively-authenticated MCP servers are often absent in
`claude -p` runs. Therefore the runtime uses the **Linear REST/GraphQL API directly**
via `linear/client.sh` (auth: `LINEAR_API_KEY`), called through Bash. Deterministic
and unit-testable without Claude in the loop.

**Fingerprint** (in every issue description, machine-readable):

```
<!-- god-fingerprint: {repo}:{file_path}:{rule_id}:{symbol} -->      # tester
<!-- god-fingerprint: scout:{module}:{pattern} -->                    # scout
```

Line numbers are deliberately excluded — they shift on every unrelated edit and
would break dedup instantly. Scout fingerprints on `module + pattern` so
"extraction, store module" can only ever be filed once regardless of wording.

**`client.sh` subcommands** (each a thin GraphQL call):
- `search <fingerprint>` → issue ID + state, or empty
- `create <title> <body-file> <label...>` → creates in the God Agents team
- `comment <issue-id> <text>` → recurrence comment
- `reopen <issue-id>` → reopen + add `regression` label
- `runner-failure <message> <log-file>` → failure issue with log tail
- `list-scout-titles` → titles of all open scout issues (for conceptual dedup)

**Write protocol — the agent MUST follow in order:**
1. `search` the fingerprint.
2. Found + open → `comment` with recurrence count. Do not create.
3. Found + closed → `reopen`, label `regression`.
4. No match → `create`.

**Issue shape:** title `[god-tester] <one line, no jargon>`; labels `god-agent`,
`<agent-name>`, severity; team **God Agents** (never pollutes the human backlog);
body = finding, evidence (test output or file:line), suggested fix, fingerprint.

---

# Part D — god-scout full spec (goes verbatim into `prompts/weekly-scout.md` and, condensed, into `skills/god-scout/SKILL.md` if it drifts)

Scout is the highest-risk agent: tester has ground truth, scout has none. Asked to
"find opportunities," a model will confidently generate plausible ideas forever.
Every rule below exists to prevent that.

**Rule 1 — Evidence first, idea second.** Scout does not generate ideas; it reports
observations with an attached hypothesis. Every finding cites something that
physically exists: a table with a row count, a function duplicated across N files,
an analytics event with volume, a config flag untouched for 8 months.
**No citation → no issue.** This kills ~80% of the slop.

**Rule 2 — Four search patterns, not brainstorming:**

| Pattern | Looks for | Example signal |
|---|---|---|
| Extraction | Internal module w/ clean boundaries solving a problem others have | Store module: few shared deps, generic domain |
| Compounding | Data collected but never queried | Table written constantly, read by nothing |
| Repetition | Same logic/manual process implemented 3+ times | Three hand-rolled retry loops |
| Abandonment | Shipped, instrumented, unused | Feature live 6 months, near-zero events |

**Rule 3 — Tiers with a hard quota.**
- **Low**: helps one internal team, no revenue path → batched into one weekly digest issue.
- **Medium**: touches guest/host experience, removes recurring manual work, or moves
  an owned metric — must name the metric and current baseline → filed individually.
- **High**: has a buyer *outside* the company or changes unit economics → must answer
  (1) who pays — a named buyer category; (2) what already exists — requires a live
  web search, name the competitors found; (3) why us, why now — usually proprietary
  data or distribution. Any unanswered → automatic downgrade.
- **Quota: max 1 High and 3 Medium per week.** A second High must argue which of the
  two is stronger and file only that one.

**Rule 4 — Adversarial pass before filing.** Second turn against its own draft:
"Argue this is not worth building: it already exists, effort is underestimated, the
signal is coincidental, it conflicts with current priorities." If the counter wins,
drop silently. Expect this to kill roughly half of what survives Rule 1.

**Rule 5 — Read the backlog before proposing.** Load open Linear issues AND
previously-closed scout findings (a rejected idea stays rejected), plus
`{{KRA_CONTEXT}}`. KRA alignment is scoring context, **not a filter** — an off-KRA
finding is still valid, it just says "Off-KRA. Worth parking." Filtering to KRAs
would make scout a backlog echo.

**Output shape per issue:**

```
Observation:   <what exists, with evidence>
Hypothesis:    <what it could become>
Tier:          Low | Medium | High
Cheapest kill: <how to disprove this in under 2 days>
Counter:       <strongest surviving argument against>
Fingerprint:   <!-- god-fingerprint: scout:{module}:{pattern} -->
```

"Cheapest kill" is the most valuable field — it converts an idea into a decision
makeable this week. Before filing, scout also reads `list-scout-titles` output and
self-checks for conceptual overlap beyond the fingerprint.

**Runtime:** weekly, read-only analysis across all three repos (Ownspce included —
no test harness needed). Headless scout runs as the lead session under
`run-scout.sh`; the prompt forbids writes, commits, and PRs, and the script never
creates branches. Model: Opus — reasoning quality is the entire product here.

---

# Build order (do not reorder M4/M5)

**M1 — Manifest + generator.** A1 + A2 + A3. *Done when:* `npx god-skills --agents
--dry-run` emits 7 valid agent files, `--agents -g` installs them, and in a scratch
project a code-change request spawns architect → dev **unprompted** (by description
alone, without naming them).

**M2 — Router.** A5 + the cos output contract. *Done when:* a vague request through
`/god` produces a correct chain and the specialist outputs stay visible in the main
session.

**M3 — Hooks.** A4 + installer `--hooks`. *Done when:* (a) an edit made without a
subsequent tester PASS provably blocks the session from finishing, then unblocks
after god-tester runs; (b) writing string-concatenated SQL is blocked with a clear
reason; (c) `chain.jsonl` accumulates tagged entries from inside subagents.

**M4 — Linear layer.** Part C, `client.sh` + protocol text in prompts. Unit-test
with two identical findings: *done when* the second produces a comment on the first
issue, not a new issue, and a closed-then-refound issue reopens with `regression`.

**M5 — Nightly runner.** A6 + Part B docs. *Done when:* three consecutive nights
run with zero duplicate issues, ≤3 PRs per repo, nothing on `main`, and PAUSE stops
it. **Do not start M5 before M4 passes — a runner without dedup floods Linear on
night one.**

**M6 — Scout.** Part D. Ships last; least verifiable. *Done when:* four consecutive
weeks produce ≤1 High each, zero conceptual duplicates, and at least one finding is
acted on.

---

# Acceptance test for the whole system

Run one week. Pass criteria:
- Zero duplicate Linear issues.
- Every auto-PR merged or closed within 48h (pile-up means autonomy is set too
  high — drop to file-issues-only).
- No PR ever touched `main` directly.
- The user did not have to read a single nightly log to trust the output.

---

# Out of scope for v1

The other 22 agents (skills remain available as-is); Ownspce headless E2E;
auto-merge of any PR; cost-based model downgrade; hook gates for non-engineering
skills.

# Builder notes

- Verify subagent frontmatter fields and hook events against the live docs before
  coding: https://code.claude.com/docs/en/sub-agents and
  https://code.claude.com/docs/en/hooks . Fields used here (`name`, `description`,
  `tools`, `model` with alias values) and events (`PreToolUse`, `PostToolUse`,
  `SubagentStop`, `Stop`) are confirmed valid as of 2026-08.
- Do not rewrite skill bodies (single exception: the cos output contract in A5).
  Agents are generated, never hand-copied.
- Keep the installer zero-dependency (Node built-ins only) and keep existing
  commands/flags backward compatible.
- Hook scripts must degrade gracefully: missing `jq` → `python3` fallback; missing
  log dir → create it; unparseable input → exit 0 (never block on a gate's own bug).
