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

2. Create your config. All settings live in `config.sh`, separate from the
   runner logic, so pulling template updates never clobbers them:

   ```bash
   cd ~/.god-agents && cp config.example.sh config.sh && $EDITOR config.sh
   ```

   | Placeholder | Where | Value |
   |---|---|---|
   | `{{REPO_PATHS}}` | `config.sh` | quoted paths, e.g. `("$HOME/code/backend" "$HOME/code/admin_app")` |
   | `{{SCOUT_REPO_PATHS}}` | `config.sh` | same, plus read-only repos with no test harness |
   | `{{DEFAULT_BRANCH}}` | `config.sh`, `prompts/nightly-tester.md` | usually `main` |
   | `{{LINEAR_TEAM_ID}}` | `config.sh` | the God Agents team id |
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

## Dry run before you schedule anything

`GOD_DRY_RUN=1` runs the entire flow with the model call stubbed out — no spend,
no PRs, no Linear writes — so you can prove the guardrails behave against your
real repo paths first:

```bash
GOD_DRY_RUN=1 ./run.sh          # branches, checks caps, writes logs, calls nothing
GOD_DRY_RUN=1 ./run-scout.sh
```

Verify afterwards that each repo sits on a `god/nightly-<date>` branch and that
`logs/failures.log` is empty.

## Order of operations

Do not schedule the nightly runner before the Linear dedup layer works. A runner
without dedup floods Linear on night one.

The protocol itself is covered by the package's test suite (`npm test` in the
god-skills repo runs it against a mock Linear server). Against your real
workspace, confirm it once by hand — the same finding filed twice must produce
one issue and one comment:

```bash
./linear/client.sh file "<!-- god-fingerprint: test:a:b:c -->" "[god-tester] dedup test" body.md
./linear/client.sh file "<!-- god-fingerprint: test:a:b:c -->" "[god-tester] dedup test" body.md
```

Then delete the test issue.

## Linear setup

Agents file into your **existing team**, alongside human work. Two things keep
that from turning into noise:

**Authorship.** Every issue and comment is written as `God` (configurable via
`GOD_ACTOR_NAME`), so agent findings are distinguishable at a glance. This needs
an OAuth app token authorized with `actor=app` — Linear does not let a personal
API key set the author. Create an OAuth application in your Linear settings,
authorize it with `actor=app`, and use its access token as `LINEAR_API_KEY`.

**A label.** Every issue gets the `god` label (created on first use), so you can
exclude agent findings from your own views with one filter, or build a saved
view that shows only them.

Check which mode you are in before the first live run — this is the difference
between issues authored by God and issues authored by you:

```bash
./linear/client.sh whoami
```

With a personal key it says so plainly rather than pretending. The runtime still
works; only the authorship differs.
