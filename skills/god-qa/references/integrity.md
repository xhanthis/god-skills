# Integrity pass (step 15 — before every PASS)

Core question: **did anyone take shortcuts, including me?** No fabricated certainty, no gamed objective.

## Detect

- Tests reported as run that were not executed; hidden failures; a suite that "passed" with zero tests collected.
- Skipped research presented as done; fabricated evidence, numbers, or citations.
- Unsupported assumptions promoted to facts; cherry-picked data; a metric definition changed to make a number pass.
- Ignored security or legal findings; scope quietly reduced; an easier problem solved than the one asked.
- A required specialist bypassed (money code that never saw god-cfo; PII code with `security.md` skipped in a mode that required it).
- Premature success: a PASS issued while an `R` scenario has neither a test nor a stated reason.

## Do (sampling catches most fraud)

1. **Re-run one test** from this run and confirm the output matches what was recorded.
2. **Re-verify one claim** — a number, a citation, a "the endpoint returns X".
3. **Grep the final diff** for what the org PR auto-reviewer hard-blocks: a credential-shaped literal, a credential variable name (the gh CLI's `GH_`-prefixed token, the `ANTHROPIC_`-prefixed key, the `SLACK_`-prefixed webhook), reviewer-directed phrasing, PII in a log call or URL, a raw error in a response, a list query without `LIMIT`. Any hit → the PASS becomes a FAIL with a 5.
4. **Check the `R` list** — every id has a test or a reason.

## Verdict

Clean → `Integrity: PASS (sampled: <test>, <claim>)` inside the Test cases doc, nothing in the reply. A violation → name the step and the shortcut, route back to god-build, re-check after rework. Nothing ships until the re-check passes.
