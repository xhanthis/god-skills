# God Skills

[Claude Code](https://claude.com/claude-code) skills I use every day. What started as two skills is now an agent operating system: 29 specialists that behave like one organization instead of one assistant guessing outside its expertise.

Each God owns a domain, knows what it should not do, and hands work to the next God rather than winging it.

## Install

One command, no clone:

```bash
npx god-skills            # every skill, asks global or project
```

```bash
npx god-skills dev tester security --global   # just these three
npx god-skills list                           # see all 29
npx god-skills --project --force              # overwrite in this repo
```

| Flag | Does |
|---|---|
| `-g, --global` | installs to `~/.claude/skills` (every project) |
| `-p, --project` | installs to `./.claude/skills` (this repo, checked in for the team) |
| `-a, --all` | every skill, no prompt |
| `-f, --force` | overwrite skills already there |
| `-y, --yes` | no prompts, defaults to global |

Short names work: `npx god-skills dev` installs `god-dev`.

<details>
<summary>Manual install</summary>

Skills are plain folders with a `SKILL.md`. Copy them anywhere Claude Code looks:

```bash
git clone https://github.com/xhanthis/god-skills.git /tmp/god-skills
mkdir -p ~/.claude/skills && cp -r /tmp/god-skills/skills/* ~/.claude/skills/
```

```bash
# one skill
mkdir -p .claude/skills/god-dev
curl -sL https://raw.githubusercontent.com/xhanthis/god-skills/main/skills/god-dev/SKILL.md \
  -o .claude/skills/god-dev/SKILL.md
```

</details>

Restart Claude Code after installing — skills load at session start.

## How it runs

```
USER → god-context → god-cos → specialists → god-da → god → god-police → EXECUTE
```

- **Vague request** ("booking amount is wrong") → **god-context** investigates the codebase and reconstructs the real problem before anyone writes code.
- **god-cos** picks the minimum set of specialists and the order they run in.
- **Writing code** → **god-architect** → **god-dev** → **god-tester** (auto-chained) → **god-security**.
- **Any significant decision** → **god-da** attacks it → **god** decides → **god-police** checks nobody cheated to get there.

Failure loops: `tester → dev → tester` · `security → dev → tester → security` · `cfo → dev → tester` · `police → agent → rework → police`

## The skills

| Skill | Core question |
|---|---|
| **god-context** | What is the user actually trying to solve? |
| **god-cos** | Who handles this, in what order? |
| **god-pm** | What should we build, and how does it get delivered? |
| **god-researcher** | What is actually true, and what is changing? |
| **god-data** | What does the data say? |
| **god-growth** | Where is the real bottleneck? |
| **god-designer** | How should the experience work? |
| **god-customer** | Would customers actually care? |
| **god-strategist** | Where should the business go? |
| **god-cfo** | Do the numbers reconcile? |
| **god-pricer** | What should we charge, and why? |
| **god-cmo** | How do we get the right people to care? |
| **god-sales** | How do we convert the right prospects? |
| **god-ops** | How does this work repeatedly without heroics? |
| **god-architect** | What should the system look like before we build? |
| **god-dev** | How do we implement this correctly? |
| **god-tester** | Does it actually work — and can we prove it? |
| **god-security** | How could this be exploited? |
| **god-pl** | What does Indian law require? |
| **god-da** | Why might we be wrong? |
| **god** | What is the final decision? |
| **god-police** | Did anyone take shortcuts? |
| **god-editor** | Can this be clearer and shorter? |
| **god-simplifier** | What can we remove? |
| **god-scout** | What opportunity are we missing? |
| **god-historian** | Why did we get here? |
| **god-plan** | Highest-leverage use of the day? |
| **god-health** | Is this pace sustainable? |
| **god-write** | Does this read like a human wrote it? |

## Agents, gates, and autonomy

The skills above are the knowledge layer. Three commands turn them into an agent
system — skills stay the single source of truth; agents are generated from them.

```bash
npx god-skills --agents     # generate + install 7 subagents and the /god command
npx god-skills --hooks      # install the hook gates (global)
```

**Subagents** (`~/.claude/agents/`) are built at install time from
`skills/<name>/SKILL.md` plus `agents/manifest.json`, so an agent can never drift
from its skill. The manifest is where tool access and model are set:

| Agent | Tools | Model |
|---|---|---|
| god-cos | Agent, Read, Grep, Glob | haiku |
| god-architect | Read, Grep, Glob, Write | opus |
| god-dev | Read, Write, Edit, Grep, Glob, Bash | opus |
| god-tester | Read, Write, Edit, Bash, Grep, Glob | opus |
| god-security | Read, Grep, Glob | opus |
| god-police | Read, Grep, Bash | sonnet |
| god-scout | Read, Grep, Glob, WebSearch | opus |

`tools` is a security boundary, not a convenience: god-security cannot edit the
code it audits.

**`/god <request>`** asks god-cos for a chain, then runs each specialist from the
main session so their output stays visible instead of buried in a router summary.

**Hook gates** are what make the rules real — a prompt can be ignored, a hook
cannot:

- `Stop` → the session cannot finish while god-dev edits lack a god-tester PASS.
- `PreToolUse` on Edit/Write → string-built SQL is blocked outright.
- `PostToolUse` on Edit/Write → every edit is logged to `.claude/logs/chain.jsonl`,
  which is what god-police samples.

**`npx god-skills doctor`** verifies an install: agents present and not drifted
from their skills, hooks wired and executable, gate events registered.

**Unattended runs** use `runtime-template/` — a sanitized seed for a private repo
cloned to `~/.god-agents`: launchd schedules, cost and PR caps enforced in shell,
a `PAUSE` kill switch, and a Linear client whose `file` subcommand searches by
fingerprint before every write so a nightly run cannot flood the backlog with
duplicates. `GOD_DRY_RUN=1 ./run.sh` exercises the whole flow with the model call
stubbed, so the guardrails can be proven before anything spends money.

`npm test` runs 93 assertions covering the gates, the installer, the dedup
protocol (against a mock Linear server) and the runner guardrails — no
credentials or network needed. See `PLAN.md` for the design and phase status,
and `runtime-template/README.md` for setup.

## The rules every God obeys

**No fabrication.** Numbers come from the repo, your analytics, or a named public source. Unknown impact is reported as unknown, plus what to instrument to find out. Legal sections and citations are verified, never remembered.

**Proof over claims.** god-tester writes tests and actually runs them. Tests that could not run return `UNVERIFIED`, never `PASS`. On `FAIL` it fixes and retests, capped at three cycles before it hands the failure back.

**Adversarial before final.** Nothing significant reaches a decision without god-da trying to destroy it first.

**Integrity gate.** god-police audits the trail before any PASS or SHIP — skipped research, fabricated citations, hidden failures, false test claims, bypassed specialists. It re-runs one test and re-checks one citation, because sampling catches most shortcuts.

**Brevity.** Every skill ends with the same output discipline: lead with the finding, one line per point, max three points, no prose on a pass. If the review is longer than the change, the review is wrong.

## Highlights

### god-dev
Senior engineer standards while coding: search before writing so nothing gets a parallel implementation, simplest design that survives a junior's reading, edge cases named explicitly (null, retries, concurrency, idempotency, pagination, timezones, unicode), parameterized queries, loud failures. Not done when it runs — done when god-tester returns PASS.

### god-tester
Reads the diff, scans for redundancy and N+1 queries, writes unit/integration/E2E tests, runs them for real, auto-fixes failures, and ends with a fixed verdict block: tests run, found, fixed, remaining, `PASS / FAIL / UNVERIFIED`.

### god-cfo
Owns every rupee: booking bifurcation, revenue-share slabs, partner splits, commissions, settlements. Reconciles totals, hunts leakage and double counting, and validates slab boundaries with edge cases (exactly at the slab edge, zero, refunds, GST-inclusive vs exclusive). Financial logic in code gets recomputed independently before it's trusted.

### god-write
Strips AI-isms from prose and puts a human voice back in, built on the 29 tells from Wikipedia's [Signs of AI writing](https://en.wikipedia.org/wiki/Wikipedia:Signs_of_AI_writing) — significance inflation, copula avoidance, the rule of three, em-dash overuse, chatbot artifacts, cutoff hedging.

## License

MIT.
