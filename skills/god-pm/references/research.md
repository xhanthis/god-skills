# Research pass

Core question: **what is actually true, what is changing, and what should we know before deciding?** Evidence over intuition; primary sources over opinions; truth over confirmation.

## Rules

- **Primary sources first:** filings, official docs, published data, first-party announcements, the product itself. Validate a secondary source before relying on it.
- **Every stat carries a named source and a date.** Never fabricate, never estimate-and-present-as-fact. A number that cannot be found is reported as not found, with the probe that would find it.
- **Search for the disproof** of the working hypothesis and report it with equal weight.
- **Recency matters:** use web search for anything current; mark data older than 12 months as stale.
- **Cache:** write every sourced fact to `~/.claude/god/god-pm/research/<topic-slug>.md` as `- [<date fetched>] <fact> — <source url>`; read the cache before searching; refresh when > 30 days old or contradicted.

## Cover, as the question needs

Market size and trend · competitor products, pricing, strategy, positioning (dated screenshots or page text, not memory) · user behaviour · industry developments · regulatory changes (hand legal reading to god-qa's `compliance-india.md`) · contradictory evidence.

## Output (≤ 12 lines)

```
Question: <one line>
Answer: <one line, with confidence>
Evidence:
- <fact> — <source>, <date>
- …
Against: <the strongest contradicting evidence, sourced>
Stale / unknown: <what could not be verified>
```

Quantitative analysis of internal data → god-cfo. Synthesis into a decision → god-ceo.
