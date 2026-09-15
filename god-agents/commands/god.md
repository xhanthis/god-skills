---
description: Route a request through the God chain — god-cos plans, each specialist runs inline in this session
---

# /god

Request: $ARGUMENTS

Run the God chain for this request. Follow these steps exactly.

Every step runs in this session through the Skill tool, so the user watches each
specialist work. Do not use the Agent tool, a Workflow, or a background task for
any step unless the user explicitly asked for subagents in this request.

## 1. Plan

Invoke the `god-cos` skill with the request verbatim and produce its plan as
strict JSON:

```json
{"chain": ["god-architect", "god-dev", "god-tester"], "reason": "<one line>"}
```

Show the plan to the user before executing it.

## 2. Execute

Run each specialist in `chain` **sequentially from this session** by invoking its
skill with the Skill tool — one finishes before the next starts. Give each:

1. The original request.
2. The findings and verdicts from every specialist that already ran, in order.
3. The current `git diff` (and `git diff --stat` if the diff is large).

Surface each specialist's findings as they land — never summarize them away.

## 3. Failure loop

If god-tester returns FAIL, invoke the god-dev skill again with the failure
report, then god-tester again. Maximum 3 dev↔tester cycles; after that, stop and
report exactly what is still broken.

## 4. Integrity gate

If any specialist issued a verdict during this run, invoke the `god-police` skill
last with those findings and the chain log at `.claude/logs/chain.jsonl` if it
exists.

## 5. Report

End with: the chain that ran, each specialist's one-line summary, the final verdict.
