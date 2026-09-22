# Reverse pass — how is this product built, and how would we rebuild it?

Observe first, infer second. Every claim is tied to a signal, or it is marked a guess.

## Six passes, in order

1. **Surface map.** What the product is, who it is for, the jobs it does. Every entry point: web app, mobile app, marketing site, public API, docs, status page, changelog.
2. **Frontend teardown.** Framework and rendering model (SSR / SPA / islands — from HTML, bundle names, headers), routes and screens, component and state shape, client auth flow, feature flags, eager vs lazy loading. Evidence: page source, bundles, `__NEXT_DATA__` / hydration blobs, asset URLs.
3. **Network teardown.** Every request a core flow makes: endpoints, methods, auth scheme (cookie / JWT / OAuth), request and response shapes, pagination, websockets, GraphQL vs REST, rate limits, error envelopes. The API contract is the product's real spec.
4. **Backend and data model inference.** From API shapes and behaviour: entities and relationships, write paths and side effects, async work (webhooks, emails, delayed effects), idempotency and consistency. State which parts are observed vs inferred.
5. **Infra and third parties.** Hosting / CDN, auth provider, payments, analytics, email / SMS, search, storage, flags, support tools — from headers, DNS, script tags, cookies, network calls.
6. **Rebuild plan.** Stack, data model, endpoints to implement, flows in build order, hard parts and unknowns, the cheapest path to a working clone of the core loop. Hand to god-build deep mode.

## Constraints

- **Public and observable surfaces only, by lawful means.** No circumventing access controls, DRM or auth; no decompiling where prohibited; no scraping behind a login you were not given. A real understanding that needs a protected surface → say so and stop.
- **Never fabricate a signal.** "The API returns `bookingId`" requires having seen it.
- Every finding is tagged **observed** (seen in a response, header, bundle) · **inferred** (deduced) · **guessed** (plausible, unverified).

## Output

```
Product: <what · for whom · core loop>
Frontend: <framework · rendering · routes> (observed/inferred)
API: <auth · style · key endpoints with shapes> (observed)
Data model: <entities → relationships> (inferred)
Infra / vendors: <list with the signal each came from>
Rebuild: <stack · build order · hard parts · unknowns + the probe for each>
```

Legality of a specific probe or clone → god-qa's `compliance-india.md`. Design hardening → god-build's `architecture.md`.
