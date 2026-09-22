# God Skills

[Claude Code](https://claude.com/claude-code) skills I use every day. What
started as two skills is now 30 specialists that behave like one organization
instead of one assistant guessing outside its expertise.

Each God owns a domain, knows what it should not do, and hands work to the next
God rather than winging it.

Two packages ship from this repo:

| Package | What it installs |
|---|---|
| **[`god-skills`](https://www.npmjs.com/package/god-skills)** | the 7 skills — knowledge, loaded into your session |
| **[`god-agents`](https://www.npmjs.com/package/god-agents)** | subagents generated from those skills, hook gates that enforce them, and an unattended runner ([docs](god-agents/README.md)) |

## Install

One command, no clone:

```bash
npx god-skills            # every skill, asks global or project
npx god-skills list       # see all 30
npx god-skills doctor     # verify the install
```

```bash
npx god-skills dev tester security --global   # just these three
npx god-skills --project --force              # overwrite in this repo
```

| Flag | Does |
|---|---|
| `-g, --global` | installs to `~/.claude` (every project) |
| `-p, --project` | installs to `./.claude` (this repo, checked in for the team) |
| `-a, --all` | every skill, no prompt |
| `-f, --force` | overwrite files already there |
| `-y, --yes` | no prompts, defaults to global |

Short names work: `npx god-skills dev` installs `god-dev`.

`doctor` compares every installed skill against the packaged copy, so a skill
that drifted after a hand-edit gets named rather than silently used.

Want the subagents, the hook gates and the nightly runner too:

```bash
npx god-agents --all      # agents, /god and the gates
```

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

## The skills

| Skill | Core question |
|---|---|
| **god-pm** | What should we build, why, for whom, how does it run, and how is the competitor built? |
| **god-zen** | Is this pace sustainable — and should you be working right now? |
| **god-cfo** | Do the numbers reconcile, what should we charge, and what does the data say? |
| **god-dev** | How do we design and implement this correctly, fast, and better than last time? |
| **god-qa** | Does it actually work, is it safe, and can we prove it? |
| **god-ceo** | What is the real problem, is it worth doing, who does it, and what is the final call? |
| **god-writer** | Is this clear, short, and does it read like a human wrote it? |

Eight of these have agent counterparts in `god-agents` today; the rest run as
skills. Adding one is a manifest entry, not a rewrite.

## How a request flows

```
USER → god-ceo → specialists → god-qa → EXECUTE
```

- **Vague request** ("booking amount is wrong") → **god-ceo** investigates the codebase, reconstructs the real problem, decides if it is worth doing, and picks the minimum set of specialists and their order.
- **Writing code** → **god-dev** (architecture inside, deep mode) → **god-qa** (tests, security, integrity — auto-chained).
- **Engineering habits:** god-dev ships every PR with Problem / Approach / Alternatives rejected / Rollout-rollback / Test evidence, timeouts + jittered retries + idempotency on every external call, expand → migrate → contract for schema and API changes, flags with kill switches, owned TODOs; god-qa writes table-driven tests and fails a perf claim with no before/after number.
- **Ship gate:** god-dev writes to, and god-qa fails on, the org PR auto-reviewer's own blocker list (raw errors in responses, unindexed or unbounded SQL, PII in logs/URLs/third parties, missing authz, XSS, secrets, credential-shaped fixtures, red CI) — so a god-skills PR is meant to pass review the first time.
- **Any significant decision** → **god-ceo** attacks it, decides, and records why; **god-qa** checks nobody cheated to get there.

Failure loops: `tester → dev → tester` · `security → dev → tester → security` · `cfo → dev → tester` · `police → agent → rework → police`

## The rules every God obeys

**No fabrication.** Numbers come from the repo, your analytics, or a named public source. Unknown impact is reported as unknown, plus what to instrument to find out. Legal sections and citations are verified, never remembered.

**Proof over claims.** god-qa opens with a devil's-advocate pass (what could go wrong: input, state, access, environment, scale, UI) and turns every scenario into a test case. It writes tests and actually runs them: backend, frontend at four viewports (mobile 390×844, tablet 820×1180, 14" laptop 1512×982, 15" laptop 1440×900) through gstack browse, accessibility, page and API perf with a 50-call burst on local/staging only, and simulated low network. Past failures are re-run first from a per-repo memory. Every issue gets a 1–5 score (5 = cannot go live, 4 = deploy but fix first, 3 = high, 2 = later, 1 = backlog); any 5 or two 4s is `FAIL`. Tests that could not run return `UNVERIFIED`, never `PASS`. On `FAIL` it fixes and retests, capped at three cycles before it hands the failure back. It ends with a one-screen verdict plus two Claude Docs: the full test-case list with results, and a manual guide with ready-to-run curls.

**Adversarial before final.** Nothing significant reaches a decision without god-ceo trying to destroy it first, and nothing reaches a PASS without god-qa's what-could-go-wrong list.

**Integrity gate.** god-qa's integrity pass audits the trail before any PASS or SHIP — skipped research, fabricated citations, hidden failures, false test claims, bypassed specialists. It re-runs one test and re-checks one citation, because sampling catches most shortcuts.

**Brevity.** Every skill ends with the same output discipline: lead with the finding, one line per point, max three points, no prose on a pass. If the review is longer than the change, the review is wrong.

## Highlights

### god-dev
Picks a mode for every task first — small (≤30 lines, no revenue/business-logic/data), normal (31–300), deep (touches revenue, business logic, data, or >300 lines; waits for your OK on the plan) — and the user can override with a word. Starts with `git fetch`, a sync with the default branch, and a search for an unmerged branch already doing the work. Keeps a per-repo profile (build/test/lint/dev commands, layout, helpers) so later runs skip rediscovery, and a lessons file fed by every god-qa and reviewer finding; a lesson seen in 3+ repos becomes a proposed PR to this skill. Plans with a shared what-could-go-wrong list that god-qa extends rather than restarts, self-scores the diff on god-qa's 1–5 scale and fixes every 4–5 before handoff, fixes straight from god-qa's `file:line` list on FAIL, and logs a scorecard (first-time PASS rate). Senior engineer standards while coding: search before writing so nothing gets a parallel implementation, simplest design that survives a junior's reading, edge cases named explicitly (null, retries, concurrency, idempotency, pagination, timezones, unicode), parameterized queries, loud failures. Closes with a formatted plain-English summary (title, what shipped, links, needs-you) and a per-session change-log doc topped by an illustrated flowchart. Not done when it runs — done when god-qa returns PASS.

### god-qa
Reads the diff, scans for redundancy and N+1 queries, writes unit/integration/E2E tests, runs them for real, auto-fixes failures, and ends with a fixed verdict block: tests run, found, fixed, remaining, `PASS / FAIL / UNVERIFIED`.

### god-cfo
Owns every rupee: booking bifurcation, revenue-share slabs, partner splits, commissions, settlements. Reconciles totals, hunts leakage and double counting, and validates slab boundaries with edge cases (exactly at the slab edge, zero, refunds, GST-inclusive vs exclusive). Financial logic in code gets recomputed independently before it's trusted.

### god-writer
Strips AI-isms from prose and puts a human voice back in, built on the 29 tells from Wikipedia's [Signs of AI writing](https://en.wikipedia.org/wiki/Wikipedia:Signs_of_AI_writing) — significance inflation, copula avoidance, the rule of three, em-dash overuse, chatbot artifacts, cutoff hedging.

## Proof

`npm test` runs 131 assertions across both packages — no credentials, no network:

| Suite | Covers |
|---|---|
| `skills.test.sh` | the skill installer, force semantics, doctor, tarball contents |
| `agents.test.sh` | generation, tool boundaries, settings-merge safety, doctor |
| `hooks.test.sh` | every gate, both jq and python3 paths, fail-open behaviour |
| `linear.test.sh` | the dedup protocol against a mock Linear server |
| `runner.test.sh` | runner guardrails against real throwaway git repos |

See `PLAN.md` for the design and per-phase status.

## License

MIT.
