# God Skills

[Claude Code](https://claude.com/claude-code) skills I use every day, turned into
an agent system. What started as two skills is now 30 specialists that behave
like one organization instead of one assistant guessing outside its expertise —
plus subagents with real tool boundaries, hooks that enforce the rules, and an
unattended runner that files what it finds.

Each God owns a domain, knows what it should not do, and hands work to the next
God rather than winging it.

## Install

One command, no clone:

```bash
npx god-skills            # every skill, asks global or project
npx god-skills --agents   # generate + install the subagents and /god
npx god-skills --hooks    # install the hook gates
npx god-skills doctor     # verify the install
```

```bash
npx god-skills dev tester security --global   # just these three
npx god-skills list                           # see all 30
npx god-skills --project --force              # overwrite in this repo
```

| Flag | Does |
|---|---|
| `-g, --global` | installs to `~/.claude` (every project) |
| `-p, --project` | installs to `./.claude` (this repo, checked in for the team) |
| `-a, --all` | every skill, no prompt |
| `-f, --force` | overwrite files already there |
| `-y, --yes` | no prompts, defaults to global |
| `--agents` | generate subagents from skills + manifest, install `/god` |
| `--hooks` | install the gate scripts and merge them into `settings.json` |
| `--dry-run` | with `--agents`/`--hooks`: print what would happen, write nothing |

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

Restart Claude Code after installing — skills and agents load at session start.

## Three layers

Each layer does something the one above it can't.

```
skills/          knowledge      what good work looks like
  ↓ generated
agents/          isolation      own context, own tools, own model
  ↓ enforced by
hooks/           rules          a prompt can be ignored; a hook cannot
  ↓ driven by
runtime-template/ autonomy      scheduled runs, caps, findings filed
```

### 1. Skills → agents, generated not copied

`agents/manifest.json` holds only frontmatter — tools and model. The installer
glues it to `skills/<name>/SKILL.md` at install time, so an agent is that skill
running in its own context window with a tool allowlist. Nothing is duplicated,
so nothing can drift; `doctor` regenerates and compares to prove it.

| Agent | Tools | Model |
|---|---|---|
| god-cos | Agent, Read, Grep, Glob | haiku |
| god-architect | Read, Grep, Glob, Write | opus |
| god-dev | Read, Write, Edit, Grep, Glob, Bash | opus |
| god-tester | Read, Write, Edit, Bash, Grep, Glob | opus |
| god-security | Read, Grep, Glob | opus |
| god-police | Read, Grep, Bash | sonnet |
| god-scout | Read, Grep, Glob, WebSearch | opus |
| god-reverse | Read, Grep, Glob, Bash, WebSearch, WebFetch, Write | opus |

`tools` is a security boundary, not a convenience: god-security physically
cannot edit the code it audits, and god-scout cannot run commands. Models are
pinned explicitly, because an unpinned subagent inherits the lead's model and
silently burns Opus on triage.

**`/god <request>`** asks god-cos for a chain as JSON, then runs each specialist
from the main session — so their findings stay visible instead of buried in a
router's summary. Tester FAIL loops back to dev, up to three times.

### 2. Hooks, because prompts get ignored

| Event | Gate |
|---|---|
| `Stop` | the session cannot finish while god-dev edits lack a god-tester PASS |
| `PreToolUse` on Edit/Write | string-built SQL is blocked outright |
| `PostToolUse` on Edit/Write | every edit is logged to `.claude/logs/chain.jsonl` |
| `SubagentStop` on god-tester | the verdict is recorded, so the Stop gate has ground truth |

That is the difference between "god-dev should call god-tester" and god-dev being
unable to finish without one. `FAIL` and `UNVERIFIED` don't unblock it either.

Every gate falls back to `python3` when `jq` is absent, and exits 0 on its own
parse failure — a bug in a gate must never block your work.

### 3. Autonomy, with the caps in shell

`runtime-template/` is a sanitized seed for a private repo cloned to
`~/.god-agents`. Your repo paths, KRAs, and Linear config live there, never in
this public package.

- `launchd` schedules a nightly tester and a weekly scout.
- Every run starts on a fresh `god/nightly-<date>` branch. Never `main`.
- Cost caps, a PR cap, and a `PAUSE` kill switch are enforced in the shell around
  the model call — a prompt can be argued out of a limit, a script cannot.
- `GOD_DRY_RUN=1 ./run.sh` runs the whole flow with the model stubbed, so the
  guardrails can be proven before anything spends money.

**Findings go to Linear, deduplicated.** Every finding carries a fingerprint
(`repo:file:rule:symbol` — no line numbers, they shift on unrelated edits). The
client searches for it before every write: already open, it comments; closed, it
reopens as a regression; new, it creates. That is why a nightly run doesn't file
the same twelve issues every night.

Issues are authored as **God** and labelled `god`, so agent findings sit in your
normal team without burying it. Authorship needs an OAuth app token authorized
with `actor=app` — Linear does not let a personal key set the author, and
`client.sh whoami` tells you which you have rather than pretending.

## Proof

`npm test` runs 103 assertions — no credentials, no network:

| Suite | Covers |
|---|---|
| `hooks.test.sh` | every gate, both jq and python3 paths, fail-open behaviour |
| `install.test.sh` | generation, tool boundaries, settings-merge safety, doctor |
| `linear.test.sh` | the dedup protocol against a mock Linear server |
| `runner.test.sh` | runner guardrails against real throwaway git repos |

See `PLAN.md` for the design and per-phase status, `runtime-template/README.md`
for unattended setup.

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
| **god-reverse** | How is this product built, and how would we rebuild it? |
| **god-historian** | Why did we get here? |
| **god-plan** | Highest-leverage use of the day? |
| **god-health** | Is this pace sustainable? |
| **god-write** | Does this read like a human wrote it? |

Eight of these have agent counterparts today; the rest run as skills. Adding one
is a manifest entry, not a rewrite.

## How a request flows

```
USER → god-context → god-cos → specialists → god-da → god → god-police → EXECUTE
```

- **Vague request** ("booking amount is wrong") → **god-context** investigates the codebase and reconstructs the real problem before anyone writes code.
- **god-cos** picks the minimum set of specialists and the order they run in.
- **Writing code** → **god-architect** → **god-dev** → **god-tester** (auto-chained) → **god-security**.
- **Any significant decision** → **god-da** attacks it → **god** decides → **god-police** checks nobody cheated to get there.

Failure loops: `tester → dev → tester` · `security → dev → tester → security` · `cfo → dev → tester` · `police → agent → rework → police`

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
