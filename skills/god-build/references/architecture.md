# Architecture pass (deep mode, or a new API / schema / service)

Core question: **what should the system look like before implementation?** The best architecture is the simplest one that survives the next order of magnitude.

## Design, in this order

1. **Data model and API contracts first** — code follows shape. Name every entity, its key, and the invariants a write must keep.
2. **Boundaries by what changes together.** A module or service boundary exists because two things change at different rates or by different teams; otherwise it is accidental complexity.
3. **Plan for failure:** timeouts on every call, retries with jitter and an idempotency key, queues for spiky load, caching with explicit invalidation, and what the user sees when each dependency is down.
4. **Migrations are first-class:** forward path, rollback path, backward compatibility during rollout. Every schema or API change is expand → migrate → contract, one PR per step, old and new readable throughout.
5. **Flags:** anything user-facing or money-touching ships behind a feature flag with a kill switch; name the flag and what "off" looks like.
6. **Observability up front:** the metric or log each new path emits, the request id it carries, the SLO it protects, and what pages someone at 3am.
7. **Reject accidental complexity:** no new service, dependency, or pattern without a reason the current stack cannot satisfy. Run the remove-first question on the design itself.
8. **Design so the PR reviewer has nothing to block:** every read on a production table is index-backed and every list endpoint paginated with a hard cap; `ORDER_ID` (`PREFIX-NNNN`, varchar) is the only order key; personal data never rides in a URL, never lands in logs or third-party sinks without a stated purpose, and every endpoint returning it has an object-level authz check and a minimal field set; the error contract is a sanitized message with detail in logs; new PII storage names purpose and retention.

## Output (posted with the plan card, ≤ 20 lines)

```
Entities: <name (key) — invariants>
Contracts: <METHOD /path → request · response · errors>
Boundaries: <module/service — why it is separate>
Failure: <dependency → timeout · retry · degraded behaviour>
Rollout: <expand → migrate → contract steps · flag name · rollback>
Observability: <metric/log per path · SLO>
Removed from the first draft: <what, and why nothing broke>
```

Security-sensitive designs are reviewed by god-qa's `security.md` at handoff; money flows by god-cfo. A product-scope question that the design cannot settle → god-ceo.
