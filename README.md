# God Skills

Seven [Claude Code](https://claude.com/claude-code) skills that behave like one company instead of one assistant guessing outside its expertise — a CEO, a builder, a QA gate, a CFO, a PM, a writer and a wellbeing assistant. Each owns a domain, hands work to the next, and **learns from every run**: a lesson that would help every user becomes a pull request to this repo; a lesson about you stays on your machine.

Two packages ship from this repo:

| Package | What it installs |
|---|---|
| **[`god-skills`](https://www.npmjs.com/package/god-skills)** | the 7 skills — knowledge, loaded into your session |
| **[`god-agents`](https://www.npmjs.com/package/god-agents)** | subagents generated from those skills, hook gates that enforce them, the god-ally activity hook, and an unattended runner ([docs](god-agents/README.md)) |

## Install

```bash
npx god-skills            # every skill, asks global or project
npx god-skills list       # see the 7
npx god-skills doctor     # verify the install, flag leftovers from older versions
```

```bash
npx god-skills dev qa --global      # just these two
npx god-skills --project --force    # overwrite in this repo
npx god-agents --all                # subagents, /god, and the hook gates
```

| Flag | Does |
|---|---|
| `-g, --global` | installs to `~/.claude` (every project) |
| `-p, --project` | installs to `./.claude` (this repo, checked in for the team) |
| `-a, --all` | every skill, no prompt |
| `-f, --force` | overwrite files already there |
| `-y, --yes` | no prompts, defaults to global |

Short names work: `npx god-skills dev` installs `god-dev`. Upgrading from 2.x: the install removes the retired skill folders it once wrote (never a folder of yours that happens to share a name) and `doctor` names any left behind. `v2.4.0` is tagged if you need the old 30.

Restart Claude Code after installing — skills load at session start.

## Other CLIs — Codex, Gemini, Cursor, Copilot

The skills are plain Markdown, so any agent that reads an instruction file can follow them:

```bash
npx god-skills --codex                            # ./AGENTS.md   (OpenAI Codex CLI)
npx god-skills --gemini                           # ./GEMINI.md   (Gemini CLI)
npx god-skills --agents-md .cursor/rules/god.md   # any instruction file
```

Each copies the 7 skills to `./.god-skills/` and adds one marker-delimited index block to the file (re-runs replace the block; the rest of the file is untouched). What does **not** port: the hook gates (`Result: PASS` before a session can end), the auto-trigger card, and the Claude Docs / gstack browse integrations — those are Claude Code features. The agent reads a skill when its trigger matches and runs them in sequence itself.

## The seven

| Skill | Core question | Absorbed |
|---|---|---|
| **god-ceo** | What is the real problem, is it worth doing, who does it, and what is the final call? | context, cos, historian, da, god |
| **god-dev** | How do we design and implement this correctly, fast, and better than last time? | architect, simplifier |
| **god-qa** | Does it actually work, is it safe, and can we prove it? | tester, security, police, pl |
| **god-cfo** | Do the numbers reconcile, what should we charge, and what does the data say? | pricer, data |
| **god-pm** | What should we build, why, for whom, how does it run, and how is the competitor built? | customer, ops, strategist, scout, researcher, reverse |
| **god-cmo** | Is this clear, short, and does it read like a human wrote it? | write, editor |
| **god-ally** | Is this pace sustainable — and should you be working right now? | plan, health |

Each replies in its own shape, in plain Markdown that reads the same in a terminal, in chat and in an IDE: god-dev a build report (title, one-line summary, the links, then QA and what needs you), god-qa a verdict with a checklist and an issues table, god-ceo a decision memo with a before/after, god-cfo a worked example in tables, god-pm a customer moment with sourced evidence, god-cmo the rewrite itself with a short edit note. god-ally alone prints a fenced report, so its bars keep their columns.

Every skill's `SKILL.md` stays under 150 lines; the heavier passes live in `references/` and load only when the task needs them (god-qa's four-viewport frontend pass only when UI changed, its security pass only when auth or input is touched, god-dev's architecture pass only in deep mode).

## God Ally's daily report

`/god-ally` prints one screen: a **Zen Score out of 10** for today, a 30-day graph, what you spent, and one thing to change tomorrow. It never asks you a question — a source that isn't there is listed as missing and the score is computed without it.

```
node ~/.claude/skills/god-ally/scripts/zen-report.js        # or just ask for /god-ally
```

| Component | Weight | Full marks |
|---|---|---|
| Day length | 35% | first to last activity within 8 hours |
| Sleep | 30% | 7h30m asleep and nothing logged after 21:00 |
| Intensity | 20% | tokens and commits at or under your own 28-day median |
| Recovery | 15% | two days off in the last seven |

Any activity past midnight, or a night under five hours, caps the score at 5. **8–10 Balanced · 5–7.9 Stretched · under 5 Burnout risk.** The day runs 05:00 → 05:00 in `Asia/Kolkata`, so a 00:29 commit counts against the day before — change both in the config.

**Where it reads from,** timestamps and counts only, never content: your git commits across the repo roots in the config; Claude Code token usage via `npx ccusage@latest daily --json`, falling back to `~/.claude/projects/**/*.jsonl`; Apple Health sleep exported to iCloud; and, when they are connected, Google Calendar, Slack, Gmail, Linear and Notion through MCP — the skill fetches those timestamps and hands them to the script. Config and history live in `~/.god-ally/`, created on the first run, which also backfills 30 days.

**Keep enough history.** Claude Code deletes its logs after 30 days. Raise it in `~/.claude/settings.json` so the baseline has something to stand on:

```json
{ "cleanupPeriodDays": 120 }
```

**Sleep, from your watch.** The script reads `~/Library/Mobile Documents/com~apple~CloudDocs/GodAlly/sleep/YYYY-MM-DD.json`, each holding `{"date":"2026-09-22","asleep_minutes":412,"bedtime":"01:10","wake":"08:02"}`. Build it once with an iOS Shortcut, on the iPhone that has your Health data:

1. **Shortcuts → Automation → + → Time of Day.** Pick a time after you normally wake (09:00 works), *Daily*, and turn on **Run Immediately** so it never asks.
2. Add **Find Health Samples** → type **Sleep Analysis**, *Sort by* Start Date, and set the date range to today.
3. Add **Calculate Statistics** (or **Get Numbers from Input**) to total the asleep minutes, then **Text** to build the JSON above — the sample's start is your bedtime, its end your wake time.
4. Add **Save File**, destination **iCloud Drive → GodAlly → sleep**, filename `<today's date, yyyy-MM-dd>.json`, *Overwrite if file exists* on.

Skip it and the report still works: sleep is then scored on when you stopped working alone, and the footer lists `apple health sleep` as missing.

**The graph** is the last seven days, one bar per day: the y-axis is the score out of ten, so taller is a better day, and the date and that day's score sit under every bar. A day off has no bar. It is drawn by the script itself — nothing to install.

**A rare word of encouragement.** The report itself is numbers and one action, never a quote. But at the close of *another* skill's reply, `--quote` will occasionally return a single line — only when the day scored under 6, none has been shown in three days, and a one-in-twenty draw lands. Most calls print nothing, which is the point. There is no quote list: the script describes the moment, the skill writes a fresh line for it, and every line shown is remembered so none repeats.

```
node ~/.claude/skills/god-ally/scripts/zen-report.js --quote
```

**Keep enough history.** Claude Code deletes its logs after 30 days. Raise it in `~/.claude/settings.json` so the baseline has something to stand on:

```json
{ "cleanupPeriodDays": 120 }
```

**Sleep, from your watch.** The script reads `~/Library/Mobile Documents/com~apple~CloudDocs/GodAlly/sleep/YYYY-MM-DD.json`, each holding `{"date":"2026-09-22","asleep_minutes":412,"bedtime":"01:10","wake":"08:02"}`. Build it once with an iOS Shortcut, on the iPhone that has your Health data:

1. **Shortcuts → Automation → + → Time of Day.** Pick a time after you normally wake (09:00 works), *Daily*, and turn on **Run Immediately** so it never asks.
2. Add **Find Health Samples** → type **Sleep Analysis**, *Sort by* Start Date, and set the date range to today.
3. Add **Calculate Statistics** (or **Get Numbers from Input**) to total the asleep minutes, then **Text** to build the JSON above — the sample's start is your bedtime, its end your wake time.
4. Add **Save File**, destination **iCloud Drive → GodAlly → sleep**, filename `<today's date, yyyy-MM-dd>.json`, *Overwrite if file exists* on.

Skip it and the report still works: sleep is then scored on when you stopped working alone, and the footer lists `apple health sleep` as missing.

## How a request flows

```
USER → god-ceo (vague or multi-skill asks only) → god-dev → god-qa → EXECUTE
```

- **Vague request** ("order amount is wrong") → **god-ceo** investigates the codebase, reconstructs the real problem, says whether it is worth doing and where it ranks this week, and picks the minimum chain. A clear single-skill ask skips it.
- **Writing code** → **god-dev** picks a mode — **small** (≤30 lines, no revenue / business logic / data), **normal**, **deep** (anything touching money, data, auth, or >300 lines; designs first and waits for your OK) — you can override with one word. It syncs git, checks for an unmerged branch already doing the work, loads the repo profile and lessons, plans with a what-could-go-wrong list, removes before it adds, self-scores on god-qa's 1–5 scale and fixes every 4–5, then runs god-qa itself in the same mode — every change is tested by default — and returns one message: title, a plain-English sentence, PR links, the flowchart doc, the test cases, the manual checks.
- **Proving it** → **god-qa** extends the same risk list, writes and runs tests (backend; frontend at 390×844, 820×1180, 1512×982, 1440×900 via gstack browse; accessibility; perf and a 50-call burst on local/staging only; simulated low network), runs the security and Indian-compliance passes when the diff touches them, re-runs past failures first, spot-checks its own evidence, scores every issue (5 = cannot go live … 1 = backlog; any 5 or two 4s = FAIL), fixes and retests up to three times, and ends with a one-screen verdict plus two Claude Docs — the test cases with results, and a manual guide with ready-to-run curls.
- **Money in the diff** → **god-cfo** recomputes it a second way before it is trusted.
- **Any significant decision** → **god-ceo** attacks it, decides (BUILD · MODIFY · CHEAPEST TEST FIRST · DEFER · INVESTIGATE · DO NOT BUILD · SHIP · DO NOT SHIP · STOP), records why in `docs/decisions/`, and answers "why does this exist" later.
- **Every skill's final message** ends with **god-ally's** status line — dollars burned today, intensity against the last 7 and 30 days, Zen Score against the week (`zen-report.js --line`) — and one more 🧘 line whenever it has something specific: stop for tonight, take a break, don't start this before the meeting, eat, go deep now. On a strong signal it asks before you continue.

Failure loops: `qa → dev → qa` (max 3) · `cfo → dev → cfo` · stuck anywhere → `god-ceo` (sensei).

## The learning loop

One shared loop, `god-ceo/references/learning-loop.md`, used by all seven. A learning is captured from four triggers — you correcting the skill, another skill failing its work, an outcome later (a reverted PR, a wrong decision), and a one-line self-review. It is then judged on **who it is true for**, not on how often it repeats:

| Scope | Test | Goes to |
|---|---|---|
| **universal** | would hold for a stranger in another repo at another company | `lessons/global.md`; may become a PR here |
| **repo** | true only in that codebase | `lessons/<repo>.md`, local |
| **personal** | your taste, tools, style | `lessons/personal.md`, local — even after 100 sightings |

Value = **severity × reach × confidence**. A universal lesson scoring ≥ 18 (or any severity-5 finding) opens a PR on its **first** sighting; 6–17 is stored and promoted as confidence grows; below 6 waits as a candidate. The PR carries a summarized rule only — never code, paths, names or tokens — is opened from the user's fork, labelled `learning`, at most one a day, and is never merged by a machine. On by default; `"share_learnings": false` in `~/.claude/god/config.json` turns it off. CI rejects a learning PR that touches anything but skill text, exceeds 40 lines, lacks its `Scope:` / `Score:` lines, or contains anything identifying.

Memory lives in `~/.claude/god/<skill>/` — lessons, scorecards, god-dev's repo profiles, god-qa's regression files, god-ceo's decisions and priorities, god-ally's activity log. Nothing there is ever sent anywhere except the summarized rules described above. The only documents any skill publishes are god-dev's flowchart + change log and god-qa's test cases and manual guide.

## The rules every God obeys

**No fabrication.** Numbers come from the repo, your analytics, or a named public source. Unknown impact is reported as unknown, plus what to instrument to find out. Legal sections and citations are verified, never remembered.

**Proof over claims.** Tests that could not run return `UNVERIFIED`, never `PASS`. A screenshot that was not looked at is not a test.

**Adversarial before final.** Nothing significant reaches a decision without god-ceo trying to destroy it first, and nothing reaches a PASS without god-qa's what-could-go-wrong list.

**Integrity gate.** god-qa's integrity pass re-runs one test, re-verifies one claim, and greps the final diff for what the org PR reviewer hard-blocks before any PASS — sampling catches most shortcuts.

**Ship gate.** god-dev writes to, and god-qa fails on, the org PR auto-reviewer's own checklist, line by line: raw errors in responses, unindexed or unbounded SQL, PII in logs / URLs / third parties / error bodies, missing authz, XSS, secrets and credential-shaped fixtures, the injection markers, size caps, red CI. The gate is met, never gamed — a rule that cannot be met is written into the PR body instead.

**Brevity.** Lead with the finding, one line per point, max three points outside the templates, no prose on a pass. If the review is longer than the change, the review is wrong.

## Hooks (god-agents)

| Event | Gate |
|---|---|
| `Stop` | the session cannot finish while god-dev edits lack a god-qa `Result: PASS` — read from the chain log for subagents and the transcript for inline skills |
| `SubagentStop` on god-qa | the verdict is recorded so the Stop gate has ground truth |
| `PreToolUse` on Edit/Write | string-concatenated SQL and reviewer tripwires are blocked before they land |
| `SessionStart` / `UserPromptSubmit` / `Stop` | god-ally's collector logs the event and, before a prompt, warns when a meeting is minutes away or you are past your stop time |

## Proof

`npm test` runs 320 assertions across both packages — no credentials, no network — and CI runs them on every pull request:

| Suite | Covers |
|---|---|
| `skills.test.sh` | installer, force and retire semantics, doctor, tarball, the `--codex` target, every skill's contract (verdict tokens, viewports, modes, memory paths, ≤150-line cores) |
| `agents.test.sh` | generation, tool boundaries, settings-merge safety, retired-agent cleanup, doctor |
| `hooks.test.sh` | every gate incl. the god-ally collector, both jq and python3 paths, fail-open behaviour |
| `linear.test.sh` | the dedup protocol against a mock Linear server |
| `runner.test.sh` | runner guardrails against real throwaway git repos |
| `zen.test.sh` | god-ally's scoring units, the 3.3 worked example, the day boundary, the caps, the fresh-line brief, and a full run with every source missing |

`PLAN.md` is the original 30-skill design and is kept for history.

## License

MIT. `god-cmo`'s pattern catalog is adapted from [blader/humanizer](https://github.com/blader/humanizer) (MIT).
