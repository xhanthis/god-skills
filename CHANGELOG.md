# Changelog

All notable changes to `god-skills` and `god-agents`. Dates are release dates.

## 3.1.0 — 2026-09-22

### Added
- **God Zen's daily report.** `/god-zen` now prints a Zen Score out of 10 for the day, a 30-day graph of it, what the month is costing, and one thing to change tomorrow. Fully passive — it never asks a question, and a source that is missing is named in the footer instead of blocking the score.
- `skills/god-zen/scripts/zen-report.js` collects git commit times, Claude Code token usage (`ccusage`, falling back to the raw session logs) and Apple Health sleep exported to iCloud; `scripts/zen-score.js` holds the scoring on its own so it can be tested without a machine to run it on.
- The skill gathers timestamps from whichever MCP tools are connected — Google Calendar, Slack, Gmail, Linear, Notion — and hands them to the script as JSON. Missing connectors are skipped silently.
- Config and history in `~/.god-zen/`, created on first run, which backfills 30 days. Numbers and timestamps only; no message, commit or event content is ever read or stored.
- README: how the score is built, the `cleanupPeriodDays` bump that keeps enough log history, and the iOS Shortcut that exports last night's sleep.
- **A motivational line**, picked for how the day actually went rather than at random — the weakest component and the day's band choose the mood. The same quote holds all day and none repeats for 21 days. `--quote` returns just that line from stored history, instantly, so any skill's closing 🧘 can carry it when it has no specific signal of its own.
- `test/zen.test.sh` runs the report's own `node --test` suite — every scoring function, the 3.3 worked example, the past-midnight cap, the quote bank, and a full run with every source missing.

### Changed
- `god-zen`'s SKILL.md documents the report, its MCP payload and the new storage files. Scoring is the script's job; the skill is told never to recompute a score by hand, and to print the report inside a fenced code block so its columns survive any renderer.
- The 30-day graph is a bar chart with the 7-day average on its own sparkline row, replacing the line plot — a score is a level, not a path, and bars stay readable in a terminal and in a chat client. No charting dependency.
- `god-dev`'s final message gets room to breathe: a blank line between every block and between each PR link, one divider above the closing block, and anything beyond the template in its own short paragraph.

## 3.0.0 — 2026-09-15

- The 30 skills became seven — a CEO, a builder, a QA gate, a CFO, a PM, a writer and a wellbeing assistant — each owning a domain and handing work to the next.
- One shared learning loop, scoped universal / repo / personal.
- `god-agents` ships subagents, hook gates and an unattended runner.
- `--codex`, `--gemini` and `--agents-md` targets for other CLIs.

Older releases: see the `v2.4.0` tag.
