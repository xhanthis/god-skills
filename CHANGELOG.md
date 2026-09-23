# Changelog

All notable changes to `god-skills` and `god-agents`. Dates are release dates.

## Unreleased

### Added
- **`zen-report.js --line`, god-ally's one-line status after every skill's reply:** `🧘 $49.53 today · intensity 1.4× vs 7d · 0.9× vs 30d · Zen 8 · 7d avg 7.1 (+13%)` — dollars burned today, today's tokens against the average of the previous 7 and 30 working days, and today's Zen Score against the previous 7 scored days. Computed from the same records as the daily report, never by hand; a number the script cannot know prints as `—`. It reuses the history when it was written in the last 10 minutes and recollects otherwise.

### Changed
- **Renamed two skills and their subagents.** `god-writer` → `god-cmo`, `god-zen` → `god-ally`. The team is now god-ceo, god-pm, god-dev, god-qa, god-cfo, god-cmo and god-ally.
- Install removes the old `god-writer` and `god-zen` skill folders and agent files it once wrote.
- **One reply shape per skill, in native Markdown.** The code-fenced block every skill had borrowed from god-ally renders as a monospace box in chat and IDE clients, so each skill now replies in the shape its job needs — headings, bold labels, bullets and tables that read the same in a terminal, in chat and in an IDE. Only god-ally keeps a fenced report (the daily score, and the week view, which drops its table for the daily chart).
  - **god-dev** is a build report: an H1 title, the plain-English line as a heading under it, every PR and doc link next, then QA, week and needs-you under one rule.
  - **god-qa** titles the verdict (`Result: PASS` stays in the title for the hook gates), lists what ran as a checklist and every issue as a table row in what a user would see.
  - **god-ceo** is a decision memo: the verdict as the title, the call in one sentence, a numbered why, a before/after table, conditions and chain; it asks 1–3 quick questions when a priority is unclear.
  - **god-cfo** is a numbers memo: the definition in everyday words, a worked example with real numbers as a table, a split or trend as a table with bars, issues with their money effect in rupees; it asks 1–3 quick questions when a definition or policy is unclear instead of guessing.
  - **god-pm** is a product brief: one customer moment as a quote, evidence in a table with a source and date per row, then the test and the win.
  - **god-cmo** puts the final text first and closes with a four-line edit note; the draft and the AI-tell audit stay out of the reply.
- **god-dev's ship gate and god-qa's reviewer-gate scan now mirror the org's `pr-reviewer` rules line by line** — the backend, frontend and DPDP / ISO 27001 checklists, the diff-scoped secret scan its CI runs (provider key prefixes, tracked credential files, credential-shaped assignments, `bash -n`), the injection detector's markers, the size tiers, and the one-review-per-push mechanics. BLOCKER / WARN / NIT map to god-qa scores 5 / 4 / 2. The gate is met, never gamed: no renaming or encoding to dodge a pattern, no draft or skip label to avoid the review, no text aimed at the reviewer, no claimed test that did not run; a rule that cannot be met is written under **Known gaps** in the PR body.
- **PR titles carry the deploy tokens.** god-dev titles every PR `type(scope): description --deploy`, with `--all` as well on the node backend; god-qa's PR-shape check fails a title without them.
- **god-ally closes every skill's reply.** The learning loop's last step prints god-ally's status line and then, only when a signal is specific, one more 🧘 line, chosen from today's numbers and god-ally's signals or the rare quote. Every skill's reply template now carries both slots (god-cfo, god-pm and god-cmo had none).
- **Learnings stay local, only three docs are published, universal rules leave as PRs** — stated once in the loop and in every skill. Lessons, candidates, scorecards and decision records are files under `~/.claude/god/<skill>/`; the only private artifacts any skill creates are god-dev's flowchart + change log and god-qa's test cases and manual guide; god-pm's PRDs, god-cfo's deeper math and god-ally's weekly summary go to a doc only when the user asks. A lesson that would help everyone leaves the machine only as the loop's automatic upstream PR.
- Three new tests: no skill text trips the reviewer's injection detector or the org CI's provider-credential scan (skills are copied into reviewed repos on a project install; one literal in god-qa's fixture rule would have failed that scan), and every template's fences and table rows are well-formed. Two memory-table rows with unescaped pipes (god-dev, god-ally) rendered short in GFM and are fixed.
- **No more hardcoded quotes or signatures.** `quotes.json` and the fixed signer list are gone. `--quote` now returns a brief of the moment (mood, score, what went wrong, lines to avoid) and the skill writes a fresh line for it, recorded with `--quote-said` so it never repeats. Each PR signature is written for that PR and logged in `signatures.jsonl`.
- **Removed the weekly scout runner** (`run-scout.sh`, `prompts/weekly-scout.md`, the `godscout` launchd plist, `SCOUT_REPOS` / `GOD_SCOUT_COST_CAP`, and Linear's `list-scout-titles`). god-scout was folded into god-pm in 3.0; the nightly tester is the only scheduled runner now.
- god-ally keeps its data in `~/.god-ally/` and `~/.claude/god/god-ally/`; move the old `god-zen` folders there to keep your history.

## 3.1.0 — 2026-09-22

### Added
- **God Zen's daily report.** `/god-zen` now prints a Zen Score out of 10 for the day, a 30-day graph of it, what the month is costing, and one thing to change tomorrow. Fully passive — it never asks a question, and a source that is missing is named in the footer instead of blocking the score.
- `skills/god-zen/scripts/zen-report.js` collects git commit times, Claude Code token usage (`ccusage`, falling back to the raw session logs) and Apple Health sleep exported to iCloud; `scripts/zen-score.js` holds the scoring on its own so it can be tested without a machine to run it on.
- The skill gathers timestamps from whichever MCP tools are connected — Google Calendar, Slack, Gmail, Linear, Notion — and hands them to the script as JSON. Missing connectors are skipped silently.
- Config and history in `~/.god-zen/`, created on first run, which backfills 30 days. Numbers and timestamps only; no message, commit or event content is ever read or stored.
- README: how the score is built, the `cleanupPeriodDays` bump that keeps enough log history, and the iOS Shortcut that exports last night's sleep.
- **A rare word of encouragement.** `/god-zen` itself is numbers and one action, never a quote. At the close of *another* skill's reply, `--quote` occasionally returns a single line — only when the day scored under 6, none has been shown in three days, and a one-in-twenty draw lands. Most calls print nothing. The mood comes from the same weakest-component calculation that produces the advice, so the line and the action agree, and none repeats for 21 days.
- `test/zen.test.sh` runs the report's own `node --test` suite — every scoring function, the 3.3 worked example, the past-midnight cap, the quote bank, and a full run with every source missing.

### Changed
- `god-zen`'s SKILL.md documents the report, its MCP payload and the new storage files. Scoring is the script's job; the skill is told never to recompute a score by hand, and to print the report inside a fenced code block so its columns survive any renderer.
- The graph is the **last seven days**, one labelled bar each: the y-axis is the score, so taller is a better day, and the date and that day's score sit under every bar. Thirty thin bars blurred together and a line plot was worse; seven fat ones read at a glance. No charting dependency.
- `god-dev`'s PR signature list is trimmed to 20 signers, and the credit verb now belongs to whoever signs it — the Bug Whisperer debugs a PR, Stack Overflow copy-pastes it, Senna drives it. `Authored by` remains the default.
- `test/skills.test.sh` no longer hardcodes a name from god-dev's signature list — it derives the last entry and addresses it directly, so editing the list cannot make the suite flaky.
- `god-dev`'s final message gets room to breathe: a blank line between every block and between each PR link, one divider above the closing block, and anything beyond the template in its own short paragraph.

## 3.0.0 — 2026-09-15

- The 30 skills became seven — a CEO, a builder, a QA gate, a CFO, a PM, a writer and a wellbeing assistant — each owning a domain and handing work to the next.
- One shared learning loop, scoped universal / repo / personal.
- `god-agents` ships subagents, hook gates and an unattended runner.
- `--codex`, `--gemini` and `--agents-md` targets for other CLIs.

Older releases: see the `v2.4.0` tag.
