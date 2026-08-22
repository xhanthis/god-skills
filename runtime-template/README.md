# God Agents runtime

Seed for the **private** repo that drives the God agents unattended
(`xhanthis/god-agents-runtime`, cloned to `~/.god-agents`).

This template ships in the public `god-skills` package with every business
detail replaced by a `{{PLACEHOLDER}}`. Fill them in inside your private repo —
repo paths, Linear team, and KRA context must never land in the public package.

## Why a separate private repo

The prompts here carry business context (KRAs, metric baselines, repo layout,
Linear team IDs). That cannot ship in a public npm tarball, and stripping it
would gut the prompts — scout's Rule 5 depends on it.

Versioning it also means the kill switch, guardrail caps, and prompt tuning
survive a laptop migration, and every change to what the runner does is a commit
you can diff when a run misbehaves.

## Setup

1. Create the private repo from this directory and clone it:

   ```bash
   git clone git@github.com:{{USER}}/god-agents-runtime.git ~/.god-agents
   ```

2. Fill the placeholders:

   | Placeholder | Where | Value |
   |---|---|---|
   | `{{REPO_PATHS}}` | `run.sh` | space-separated quoted paths, e.g. `"$HOME/code/backend" "$HOME/code/admin_app"` |
   | `{{SCOUT_REPO_PATHS}}` | `run-scout.sh` | same, plus read-only repos with no test harness |
   | `{{DEFAULT_BRANCH}}` | `run.sh`, `prompts/nightly-tester.md` | usually `main` |
   | `{{REPO_CONTEXT}}` | `prompts/nightly-tester.md` | stack, how to run the suite, what matters |
   | `{{KRA_CONTEXT}}` | `prompts/weekly-scout.md` | current KRAs and owned metrics with baselines |
   | `{{USER}}`, `{{HOME}}` | both plists | macOS username, absolute home path |

3. Credentials — never commit these:

   ```bash
   security add-generic-password -a "$USER" -s god-linear -w   # paste the key
   ```

   and in your shell profile:

   ```bash
   export LINEAR_API_KEY=$(security find-generic-password -a "$USER" -s god-linear -w)
   export LINEAR_TEAM_ID="<the God Agents team id>"
   ```

   Create a dedicated **God Agents** team in Linear so agent findings never
   pollute the human backlog.

4. Install the schedules:

   ```bash
   cp com.*.plist ~/Library/LaunchAgents/
   launchctl bootstrap gui/$UID ~/Library/LaunchAgents/com.{{USER}}.godagents.plist
   launchctl bootstrap gui/$UID ~/Library/LaunchAgents/com.{{USER}}.godscout.plist
   ```

   Nightly tester at 02:00, weekly scout Mondays at 03:00.

## Kill switch

```bash
touch ~/.god-agents/PAUSE     # both runners exit immediately
rm ~/.god-agents/PAUSE        # resume
```

## Guardrails (enforced in shell, not in prompts)

| Guardrail | Default | Override |
|---|---|---|
| Cost cap, nightly, across repos | $10 | `GOD_COST_CAP` |
| Cost cap, weekly scout | $8 | `GOD_SCOUT_COST_CAP` |
| PRs per repo per night | 3 | `GOD_PR_CAP` |
| Branch | never the default branch | — |

On a cost-cap breach the run aborts the remaining repos, notifies, and files a
Linear issue. There is no silent model downgrade: predictable behaviour beats
clever degradation.

## Did it run?

```bash
date -r "$(cat ~/.god-agents/logs/last-success)"        # nightly
date -r "$(cat ~/.god-agents/logs/last-scout-success)"  # scout
tail ~/.god-agents/logs/failures.log
```

A crash notifies via macOS notification and files a `[god-runner]` Linear issue.
A stale `last-success` is how you catch a silent death that never reached either.

## Order of operations

Do not schedule the nightly runner before the Linear dedup layer works. Test it
by hand first: file the same finding twice and confirm the second call produces a
comment on the first issue, not a new issue.

```bash
./linear/client.sh file "<!-- god-fingerprint: test:a:b:c -->" "[god-tester] dedup test" body.md
./linear/client.sh file "<!-- god-fingerprint: test:a:b:c -->" "[god-tester] dedup test" body.md
```
