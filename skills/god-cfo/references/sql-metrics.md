# SQL, metrics and experiments (load when writing queries or judging data)

Core question: **what does the data actually tell us?**

## Metrics

- **Definition first, always:** what counts, what is excluded, the grain (per order, per day, per user), the timezone (IST unless the codebase says otherwise), how the current incomplete period is handled. Write it in the CFO's `definitions/<repo-slug>.md` if it is new.
- **Reproduce a second way** before trusting a number that will drive a decision.
- **Funnels, cohorts, retention:** fixed cohort definitions, same window for every cohort, survivorship bias named, small cells flagged (n < 30).
- **Experiments:** pre-registered metric and sample size, no peeking, report the interval not just the point; a "winner" without the sample size is a guess.
- **Correlation ≠ causation**; say which one you have and what would distinguish them.
- **Forecasts** carry their assumptions and a range; a single number is a guess dressed up.

## Writing SQL

- Follow the project's CLAUDE.md conventions (single line, named columns).
- Every query that ships in code passes the reviewer: `WHERE` on indexed columns only, `LIMIT` on every list query, named columns (no `SELECT *`), parameterized always, no queries in loops, bulk writes batched, no DDL in app code. `ORDER_ID` is varchar `PREFIX-NNNN` — never match on its numeric suffix.
- Money: sum in the smallest unit or a decimal type; round once at the boundary the definition names; never `FLOAT` for money.
- **Exports and datasets are PII surfaces under DPDP:** pull the minimum personal fields, mask or hash identifiers the analysis does not need, never place a dump where an unauthenticated URL can reach it, and never paste real rows into a doc or chat — synthesize them.

## Output (≤ 12 lines)

```
Definition: <metric — counts · excludes · grain · tz>
Query: <single line, named columns, LIMIT>
Result: <the number(s) with the period and n>
Cross-check: <second method and whether it agrees>
Caveats: <data quality · sample · causation>
```
