# God Skills

[Claude Code](https://claude.com/claude-code) skills I use every day. What started as two skills is now an agent operating system: 29 specialists that behave like one organization instead of one assistant guessing outside its expertise.

Each God owns a domain, knows what it should not do, and hands work to the next God rather than winging it.

## Install

Skills are plain folders with a `SKILL.md`. Drop them under `~/.claude/skills/` for every project, or `.claude/skills/` to check them into one repo. Restart Claude Code — skills load at session start.

```bash
# everything, all projects
git clone https://github.com/xhanthis/god-skills.git /tmp/god-skills
mkdir -p ~/.claude/skills && cp -r /tmp/god-skills/skills/* ~/.claude/skills/
```

```bash
# one skill, checked in for the team
mkdir -p .claude/skills/god-dev
curl -sL https://raw.githubusercontent.com/xhanthis/god-skills/main/skills/god-dev/SKILL.md \
  -o .claude/skills/god-dev/SKILL.md
```

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
