# Decisions

## Verdicts (pick exactly one)

| Verdict | Means |
|---|---|
| **BUILD** | Go, as proposed, with the conditions listed |
| **MODIFY** | Go, but the plan changes in the way stated |
| **CHEAPEST TEST FIRST** | Do the smallest thing that proves or kills the idea, then decide again |
| **DEFER** | Right idea, wrong time — revisit on the named trigger |
| **INVESTIGATE** | A named unknown must be resolved by a named skill before deciding |
| **DO NOT BUILD** | Not worth it — the reason and what would change the answer |
| **SHIP** | Finished work goes out as is |
| **DO NOT SHIP** | Finished work stays back — name what blocks it |
| **STOP** | Halt work already in progress |

Rules: decide with imperfect information; state which recommendation won and why the other lost; reject attractive low-value ideas without apology; at most 5 lines of reasoning; every verdict names its revisit trigger.

## Record (one JSON line per decision in `~/.claude/god/god-ceo/decisions/<repo-slug>.jsonl`)

```json
{"ts":"2026-09-22","topic":"","verdict":"BUILD","context":"","options":["",""],"assumptions":["",""],
 "expected":"","conditions":[""],"revisit_when":"","impact":{"who":"","cost_of_nothing":"","cheapest_test":""},
 "priority_rank":3,"displaced":"","outcome":null,"outcome_ts":null,"lesson":null}
```

When the repo has `docs/decisions/` or the decision changes code, also write `docs/decisions/<date>-<slug>.md` with the same fields as headings, so the reasoning survives context resets and is visible in the PR.

## Outcome follow-up

When a later session touches the same topic, or the revisit trigger fires: set `outcome` to `right | wrong | mixed`, one line of what actually happened, and `lesson` — the reusable rule, not the anecdote. A `wrong` outcome is a capture trigger for the learning loop and is usually universal if the failure was in reasoning, personal if it was in priorities.

## Weekly review template (≤ 12 lines)

```
**Week of <Mon date>**
First-time PASS: dev <x/y> (<↑↓>) · qa fix-rounds avg <n> · cfo mismatches <n>
Most repeated lesson: <one line> (<n>×, <scope>)
Learning PRs waiting: <#…> | none
Decisions due for revisit: <topic — trigger> | none
Wrong calls last week: <topic → lesson> | none
Priorities this week (confirm or edit):
1. … 2. … 3. …
```
