# Learning loop — shared by every god skill

Every god skill learns the same way. This file is the only copy of the rules; a skill's
`## Learn` section points here. Read it at the **close** of a run, not at the start —
the start only reads the lesson files.

## Where things live (fundamental)

- **Learnings stay on this machine.** Every lesson, candidate, scorecard and decision record is a local file under `~/.claude/god/<skill>/` (or the repo's own `docs/decisions/` when it keeps one). None is ever written to a Claude Doc, an artifact, Linear, Slack or any other service.
- **Only three documents are ever published as private artifacts**, by the skills that own them: god-dev's flowchart + change log, god-qa's test cases, god-qa's manual test guide. No other skill creates a doc unless the user asks for one by name.
- **A lesson that would help every user of these skills leaves the machine exactly one way:** as the upstream pull request Step 4 opens automatically, carrying the general rule and nothing else. Repo-specific and personal lessons never leave.

## Memory (`~/.claude/god/<skill>/`)

| File | Holds |
|---|---|
| `lessons/global.md` | Universal lessons, read first on every run |
| `lessons/<repo-slug>.md` | Lessons true only in one codebase |
| `lessons/personal.md` | The user's taste, tools, style, org habits |
| `candidates.jsonl` | Learnings seen once that are not yet worth storing |
| `scorecard.jsonl` | One line per run: `{"ts","repo","mode","first_time_pass","fix_rounds","max_score","minutes"}` |
| `promoted.jsonl` | Lessons already sent upstream as a PR, with the PR url |

Repo slug = `owner-repo` from `git remote get-url origin`, else the folder name. Lesson line:
`- [<date>] <what broke> → <do this instead> (scope: universal|repo|personal · sev 3 · reach 2 · conf 2 · seen 4 · repos: a,b)`.
Caps: 30 lines per lessons file; a lesson unseen for 20 runs is dropped. Lessons files are
read in full at the start of every run; every lesson touching the task's area is a hard rule.

Old layouts (`~/.claude/god-dev/`, `~/.claude/god-tester/`) → move the contents into
`~/.claude/god/god-dev/` and `~/.claude/god/god-qa/` on first use, then delete the old dir.

## What counts as a learning (capture triggers)

1. **User correction** — "no", "wrong", "redo", "not like that", or the user edits the output.
2. **Another skill failed the work** — god-qa FAIL or a scored issue, god-cfo recomputation
   disagrees, god-ceo overturns a call.
3. **Outcome later** — a PR review comment, a reverted PR, a decision later marked wrong.
4. **Self-review** — one line at close: "what would I do differently?" Kept only if specific.

A learning must name the trigger, the wrong behaviour, and the replacement behaviour. "Be more
careful" is not a learning. Anything that cannot be checked is discarded.

## Step 1 — Scope (decides WHERE it goes; nothing overrides it)

| Scope | Test | Goes to |
|---|---|---|
| **universal** | Would it hold for a stranger using this skill in a different repo at a different company? | `lessons/global.md`; may become a PR |
| **repo** | True only in this codebase (its ids, tables, quirks, conventions) | `lessons/<repo>.md`; never a PR |
| **personal** | The user's preference: tone, tools, signature, branch names, how they like questions | `lessons/personal.md`; never a PR, even after 100 sightings |

Repeats raise confidence. They never change scope.

## Step 2 — Value = severity × reach × confidence

| | 1 | 2 | 3 |
|---|---|---|---|
| **Severity** | god-qa's 1–5 scale, capped at 3 for the product; a raw 5 short-circuits (below) | | |
| **Reach** | rare edge case | some stacks or flows | almost every user of this skill |
| **Confidence** | seen once, not reproduced | seen 2–3 times, or confirmed by another person or skill | reproduced, or a test proves it |

## Step 3 — Action

| Scope | Value | Action |
|---|---|---|
| universal | raw severity 5, **or** value ≥ 18 | **PR now**, even on the first sighting |
| universal | 6–17 | store in `lessons/global.md`; PR when confidence growth lifts it to ≥ 18 |
| universal | < 6 | `candidates.jsonl`; dropped if unseen for 20 runs |
| repo · personal | any | store locally; never a PR |
| unverifiable | — | discard |

Personal lessons seen 5+ times → **offer** the user a line for their own CLAUDE.md, once. Never send it anywhere.

Worked examples:
- zsh indexes arrays from 1, so a bash-style picker printed blanks → universal · 3×3×3 = 27 → PR on first sighting.
- A gate accepts any line containing `Result: PASS` → universal · severity 5 → PR on first sighting.
- The user prefers popup questions, seen 100 times → personal → local only.
- A rare edge case in one ORM version, seen once → universal · 2×1×1 = 2 → candidate.

## Step 4 — The upstream PR (skill improvement, opened from the user's machine)

- **Default on.** Off when `~/.claude/god/config.json` has `"share_learnings": false`. The installer
  prints how to opt out. No `gh` in PATH, or `gh auth status` fails → keep the lesson local, say so once.
- **Summary only.** The PR carries a general rule. It never carries code, diffs, repo names, file paths,
  URLs other than public docs, people's names, emails, phones, ids, or tokens. Rewrite until a stranger
  could not tell which company it came from.
- **One rule per PR.** Branch `learning/<skill>-<slug>` on the user's fork (`gh repo fork xhanthis/god-skills --clone=false` once), edit only `skills/<skill>/SKILL.md` or a file under `skills/<skill>/references/`, ≤ 40 changed lines, label `learning`.
- **Dedupe first.** `gh pr list -R xhanthis/god-skills --label learning --search "<slug>"` and `promoted.jsonl`. A match → comment `+1 seen again` on the open PR instead.
- **Rate limit.** At most one learning PR per machine per day; the rest wait in `promoted.jsonl` with `"status":"queued"`.
- **Body** (CI rejects a `learning` PR without the `Scope:` and `Score:` lines):
  ```
  Scope: universal
  Score: sev 3 × reach 3 × conf 3 = 27
  Trigger: <user correction | qa fail | outcome | self-review>

  ## What went wrong
  <one paragraph, general terms>

  ## Rule
  <the exact text added to the skill>

  ## Why this helps everyone
  <one or two lines>
  ```
- **Never merge.** The repo owner merges. Never `gh pr merge`, never push to main.

## Step 5 — Scorecard

Append one line per run. The weekly first-time-PASS rate is the one number to watch; a skill whose
rate falls two weeks running gets its lessons re-read for a rule that is not working.

## Step 6 — god-ally's line (last, right before the final message)

Every skill's final message ends with god-ally's status line, always, and with at most one more `🧘` line when god-ally has something specific. The closing skill decides both here, once per run:

1. Run `node ~/.claude/skills/god-ally/scripts/zen-report.js --line` (`./.claude/skills/…` on a project install; skip silently if the script is missing) and print what it returns verbatim as the last line — dollars today, intensity vs 7 and 30 days, Zen Score vs the week. Never type or adjust those numbers by hand.
2. Then `--json` and `~/.claude/god/god-ally/next.json` against god-ally's Signals: activity past midnight, hours well past the usual stop, a 3rd late night this week, a meeting within 15 minutes, no lunch gap after the usual window, tokens over 2× the baseline, days since a day off. A specific signal — the number, the comparison, the action — becomes one more line (`🧘 3rd night past 1am this week — stop after this PR`). Nothing specific → `--quote`; it speaks rarely and only on a hard day; write the fresh line it briefs and record it with `--quote-said`. Nothing from either → the status line stands alone.
3. Never the same extra line twice in a day (`nudges.jsonl`), never during an incident, silent after `zen off`.
