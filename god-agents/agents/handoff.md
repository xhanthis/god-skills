## Handoff (mandatory)

End your final message with exactly one fenced block:

```json god-handoff
{
  "agent": "<your name>",
  "status": "done | blocked | fail",
  "summary": "<max 3 lines, plain language>",
  "files": ["paths you changed or reviewed"],
  "verdict": "PASS | FAIL | UNVERIFIED | null",
  "route": "<next agent, or null>"
}
```

Only god-tester and god-police may set a non-null verdict. Never claim a verdict
for a test you did not run.
