# The two documents (step 16)

Load the Claude Docs skill the session lists (for example `anthropic-skills:docs`) before the first docs call and follow its instructions. No Claude Docs connector → write both as Markdown in the session scratchpad and return the paths.

- **One pair per repo + branch.** Look up the links in `~/.claude/god/god-qa/regressions/<repo-slug>.json` → `branches.<branch>.docs`. If present, update the same docs: a new dated `Run N` section at the top, older runs kept below, so links never change. Otherwise create both and save the links.
- A PR exists → add both links under **Test evidence** in its body (`gh pr edit`).

## Doc A — `Test Cases — <repo> / <branch>`

- Verdict and a one-line summary.
- Issues table: score · area · `file:line` · problem · status (open/fixed).
- "What could go wrong": each `R` id → the test that covers it, or why it can't be tested here.
- Test case table: ID · area (API/UI/a11y/perf/network/security/regression) · scenario · steps · expected · actual · result (✅/❌/⚠️).
- Viewport matrix: page/state × Mobile / Tablet / 14" / 15" → ✅ or the issue.
- Perf and load numbers, CI results, re-checked past failures, `Integrity: PASS (sampled …)`.

## Doc B — `Manual Test Guide — <repo> / <branch>` (a non-engineer can follow it)

- Setup: how to run locally; env vars `BASE_URL` and `TOKEN`; how to get a token, never a real one.
- Per touched endpoint (read the route and handler first so no field is guessed): one ready-to-run `curl` using `$BASE_URL` / `$TOKEN`; a sample response and expected status; the negative curls (no token, another user's id, bad input) with expected statuses. Write calls marked **⚠️ local/staging only**.
- UI walkthrough: numbered steps for the primary flow, what you should see, and how to check each of the 4 viewports in Chrome DevTools device mode.
- Low network: DevTools → Network → "Slow 4G" / "Offline", steps and expected behavior.
- Synthetic data only. No real names, phones, emails, or tokens anywhere.

## Regression memory file

```json
{ "branches": { "<branch>": { "docs": { "cases": "<url>", "manual": "<url>" }, "last_run": "<ISO date>" } },
  "open_failures": [{ "id": "", "test": "", "file": "", "score": 0, "first_seen": "", "last_seen": "" }],
  "fixed": [{ "id": "", "test": "", "fixed_on": "" }] }
```

Unresolved issues: if a deferred-findings tracker rule is installed (`~/.claude/god-skills-shared/linear-deferred-findings.md`), file per it — scores 5/4/3 → `Bug` priority 1/2/3, scores 2/1 → `Improvement` priority 3/4. Otherwise Doc A is the record.
