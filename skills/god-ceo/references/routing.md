# Routing

## Problem statement (step 1 output — always this structure)

- **Problem** — what is actually wrong
- **Current Behavior** / **Expected Behavior**
- **Root Cause** — what appears to cause it
- **Scope** — components affected; what must NOT change
- **Relevant Code** — files, modules, functions, services
- **Relevant Data** — tables, columns, APIs, events
- **Requirements** — what the implementation must accomplish
- **Edge Cases** — what must not break
- **Constraints** — technical, product, business, security, financial, legal
- **Proposed Direction** — high-level approach if determinable
- **Acceptance Criteria** — how correctness will be judged
- **Open Questions** — only genuinely unanswerable ones
- **Confidence** — High / Medium / Low, with why

## Who does what

| Skill | Owns |
|---|---|
| **god-dev** | design + code, modes small / normal / deep, architecture pass, remove-first |
| **god-qa** | tests, 4-viewport UI, a11y, perf, low network, security, Indian compliance, integrity, PASS / FAIL |
| **god-cfo** | every number: money math, splits, slabs, pricing, SQL, metrics, forecasts |
| **god-pm** | what to build and why, PRDs, customers, research, competitors, ops processes, reverse-engineering a product |
| **god-writer** | prose for people: edit, shorten, humanize, match voice |
| **god-zen** | the user's hours, breaks, sleep, focus, meetings — speaks through other skills |
| **god-ceo** | this file: problem, worth, priority, route, attack, decide, record, review |

## Standard chains (adapt, never inflate)

- **Bug or feature in code:** god-ceo (problem) → god-dev → god-qa. Money in the diff → god-cfo after god-qa.
- **Product question:** god-ceo → god-pm (+ god-cfo for economics) → god-ceo decides.
- **Financial question:** god-ceo → god-cfo → god-ceo decides.
- **Research / competitor / market:** god-pm (research pass) → god-ceo decides.
- **Rebuild an existing product:** god-pm (reverse pass) → god-dev deep → god-qa.
- **Process / SOP:** god-pm (ops pass) → god-dev if tooling → god-qa.
- **Text for people:** god-writer alone.
- **Personal pace / planning:** god-zen alone.

## Chain contract (when asked to plan, e.g. by `/god`)

Return ONLY this JSON — no prose:

```json
{"chain": ["god-dev", "god-qa"], "mode": "normal", "reason": "<one line>"}
```

- `chain` lists skill names in execution order, minimum set only; `mode` is god-dev's mode when god-dev is in the chain.
- The caller executes the chain sequentially and inline; god-ceo does not.
- Rework loops: god-qa FAIL → god-dev → god-qa, max 3 cycles. god-cfo disagreement → god-dev → god-cfo re-check. Conflicts between skills come back to god-ceo.
