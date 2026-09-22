# God Agents

Subagents, hook gates and an unattended runner for [Claude Code](https://claude.com/claude-code),
built on the [`god-skills`](https://www.npmjs.com/package/god-skills) skills.

A skill is knowledge in your session. An agent is that same knowledge running in
its own context window, with its own tool allowlist and its own model — and a
hook is the part a prompt cannot talk its way out of.

Agents are **opt-in**. Every agent description tells Claude Code to run the
matching skill inline, in your session where you watch it work, and to use the
subagent only when you explicitly ask for one: a subagent, a parallel fan-out,
or the headless runner. Nothing is handed off behind your back.

## Install

```bash
npx god-agents            # generate + install every agent and /god
npx god-agents --all      # agents, /god and the hook gates
npx god-agents --hooks    # only the hook gates
npx god-agents doctor     # verify the install
```

```bash
npx god-agents dev tester security --global   # just these three
npx god-agents list                           # agents, tools and models
npx god-agents runtime ~/god-agents-runtime   # scaffold the headless runner
```

| Flag | Does |
|---|---|
| `-g, --global` | installs to `~/.claude` (every project) |
| `-p, --project` | installs to `./.claude` (this repo, checked in for the team) |
| `-a, --all` | agents plus the hook gates |
| `-f, --force` | overwrite files already there |
| `-y, --yes` | no prompts, defaults to global |
| `--dry-run` | print what would happen, write nothing |

Short names work: `npx god-agents dev` installs `god-dev`.

Hooks always install globally — the settings snippet references `$HOME`.

Restart Claude Code after installing — agents load at session start.

## Three layers

Each layer does something the one above it can't.

```
god-skills       knowledge      what good work looks like
  ↓ generated
agents/          isolation      own context, own tools, own model
  ↓ enforced by
hooks/           rules          a prompt can be ignored; a hook cannot
  ↓ driven by
runtime-template/ autonomy      scheduled runs, caps, findings filed
```

### 1. Skills → agents, generated not copied

`agents/manifest.json` holds only frontmatter — tools and model. The installer
glues it to the matching `SKILL.md` from the `god-skills` package at install
time, so an agent is that skill running in its own context window with a tool
allowlist. Nothing is duplicated, so nothing can drift; `doctor` regenerates and
compares to prove it.

| Agent | Tools | Model |
|---|---|---|
| god-ceo | Read, Grep, Glob, Write, Bash | opus |
| god-cfo | Read, Grep, Glob, Bash | opus |
| god-cmo | Read, Write, Edit, Grep, Glob | sonnet |
| god-dev | Read, Write, Edit, Grep, Glob, Bash, Skill, ToolSearch, Claude Docs (guide, batch, update, read) | opus |
| god-qa | Read, Write, Edit, Bash, Grep, Glob, Skill, ToolSearch, Claude Docs (guide, batch, update, read) | opus |
| god-pm | Read, Grep, Glob, Bash, WebSearch, WebFetch, Write | opus |
| god-ally | Read, Grep, Glob, Bash, Write | sonnet |

`tools` is a security boundary, not a convenience: god-qa's security pass runs with the same tools as its tests; the router
cannot spawn agents, and god-ally cannot edit code. Models are
pinned explicitly, because an unpinned subagent inherits the lead's model and
silently burns Opus on triage.

**`/god <request>`** has god-ceo plan a chain as JSON, then runs each specialist
as an inline skill, one after another in the main session. Nothing goes to a
subagent, so every step stays visible. Tester FAIL loops back to dev, up to three
times.

### 2. Hooks, because prompts get ignored

| Event | Gate |
|---|---|
| `Stop` | the session cannot finish while god-dev edits lack a god-qa PASS, whether god-dev ran as a subagent (read from the chain log) or inline as a skill (read from the session transcript) |
| `PreToolUse` on Edit/Write | string-built SQL is blocked outright |
| `PreToolUse` on Edit/Write | credential-shaped literals and reviewer-injection phrasing are blocked in every file, fixtures included — the exact regexes the org PR auto-reviewer greps for |
| `PreToolUse` on Edit/Write | loose ends are blocked: a `TODO` without `(owner, TICKET-123)`, a `requests.*()` call without `timeout=`, Go's timeout-less `http.Get` / `http.DefaultClient` |
| `PostToolUse` on Edit/Write | every edit is logged to `.claude/logs/chain.jsonl` |
| `SubagentStop` on god-qa | the verdict is recorded, so the Stop gate has ground truth |

That is the difference between "god-dev should call god-qa" and god-dev being
unable to finish without one. `FAIL` and `UNVERIFIED` don't unblock it either.

`--hooks` backs up `~/.claude/settings.json` before merging, skips any gate that
is already registered, and refuses to touch a settings file that does not parse.

Every gate falls back to `python3` when `jq` is absent, and exits 0 on its own
parse failure — a bug in a gate must never block your work.

### 3. Autonomy, with the caps in shell

`npx god-agents runtime <dir>` scaffolds a sanitized seed for a private repo
cloned to `~/.god-agents`. Your repo paths, KRAs, and Linear config live there,
never in this public package.

- `launchd` schedules a nightly tester and a weekly scout.
- Every run starts on a fresh `god/nightly-<date>` branch. Never `main`.
- Cost caps, a PR cap, and a `PAUSE` kill switch are enforced in the shell around
  the model call — a prompt can be argued out of a limit, a script cannot.
- `GOD_DRY_RUN=1 ./run.sh` runs the whole flow with the model stubbed, so the
  guardrails can be proven before anything spends money.

**Findings go to Linear, deduplicated.** Every finding carries a fingerprint
(`repo:file:rule:symbol` — no line numbers, they shift on unrelated edits). The
client searches for it before every write: already open, it comments; closed, it
reopens as a regression; new, it creates. That is why a nightly run doesn't file
the same twelve issues every night.

Issues are authored as **God** and labelled `god`, so agent findings sit in your
normal team without burying it. Authorship needs an OAuth app token authorized
with `actor=app` — Linear does not let a personal key set the author, and
`client.sh whoami` tells you which you have rather than pretending.

Setup details: `runtime-template/README.md`.

## Adding an agent

Add an entry to `agents/manifest.json` naming a skill that `god-skills` already
ships, then re-run `npx god-agents --force`. There is no second body to write —
that is the whole point of generating instead of copying.

## Proof

`npm test` runs the repo's full suite — 168 assertions, no credentials, no
network. `agents.test.sh` covers generation, YAML validity, tool boundaries,
model pinning, settings-merge safety and doctor's drift detection.

## License

MIT.
