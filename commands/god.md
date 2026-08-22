---
description: Route a request through the God agent chain — cos plans, the main session executes
---

# /god

Request: $ARGUMENTS

Run the God chain for this request. Follow these steps exactly.

## 1. Plan

Spawn the `god-cos` subagent with the request verbatim. It must return strict JSON:

```json
{"chain": ["god-architect", "god-dev", "god-tester"], "reason": "<one line>"}
```

If the output is not parseable JSON with a `chain` array, retry once with
"Return ONLY the JSON plan." If it fails again, ask the user how to proceed.

## 2. Execute

Run each agent in `chain` **sequentially from this session** — do not nest the
chain inside god-cos. For each agent, the prompt is:

1. The original request.
2. Every `god-handoff` JSON block produced so far, in order.
3. The current `git diff` (and `git diff --stat` if the diff is large).

Do not summarize a specialist's output away — surface each agent's findings in
your own updates so the user sees them.

## 3. Failure loop

If god-tester hands off with verdict FAIL, route back to god-dev with the failure
report, then god-tester again. Maximum 3 dev↔tester cycles; after that, stop and
report exactly what is still broken.

## 4. Integrity gate

If any agent issued a verdict during this run, spawn `god-police` last with all
handoff blocks and the chain log at `.claude/logs/chain.jsonl`.

## 5. Report

End with: the chain that ran, each agent's one-line summary, the final verdict.
