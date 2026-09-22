# Security review (step 13)

Core question: **how could this be exploited, leaked, abused, or compromised?** Assume someone will try. Load when the diff touches auth, tokens, sessions, secrets, external input, or personal data — always in deep mode.

## Checklist (each hit scored 1–5; org-reviewer BLOCKERs are 5)

- **Secrets:** scan diff and repo for hardcoded keys, tokens, passwords, connection strings, committed `.env`. A leaked key is a 5 — rotate it, don't just delete the line.
- **Injection:** SQL, command, template, header, path — on every external input.
- **AuthN/AuthZ:** every endpoint verifies identity AND permission; object-level check (user A cannot fetch user B's order by changing an id); admin routes not reachable by role downgrade.
- **Data exposure:** responses carry only the fields the caller needs and may see; PII never in logs, Sentry/Datadog/ELK, Slack sinks (opaque id or last-4 only), never in a URL / query string / GET param, never to analytics, pixels, CRM widgets or an external API without a stated purpose; new PII storage names purpose and retention; plaintext where the codebase encrypts equivalents.
- **Error leakage:** no stack trace, DB error string, `err.Error()` / `exception.message` in any response — a 5.
- **Sessions and tokens:** expiry, rotation, revocation, secure/httpOnly/sameSite flags, no token in localStorage when a cookie is the codebase's norm.
- **Dependencies:** known-vulnerable packages (`npm audit`, `govulncheck`, `pip-audit` — run the one the repo has), unnecessary new dependencies.
- **Abuse:** rate limits, replay, enumeration, business-logic abuse (free-cancellation loops, coupon stacking, refund double-claims).
- **Frontend:** `dangerouslySetInnerHTML` / `innerHTML` / `insertAdjacentHTML` with unsanitized data, `javascript:` hrefs, user input concatenated into query strings or payloads, secrets in the bundle.

## Proof-of-concept hygiene

A PoC or regression test for a finding must stay out of the reviewer's tripwires: no credential-shaped literal, no reviewer-directed phrasing, no credential variable names — payloads live in base64 or joined-string constants.

## Report

`[score] file:line — vulnerability. fix.` Critical (5) blocks SHIP and must never reach the PR. A design-level fix → god-dev in deep mode.
