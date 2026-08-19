# God Dev

A [Claude Code](https://claude.com/claude-code) skill that puts every change through three review gates — **senior engineer**, **product manager**, and **CEO** — once on the plan and once on the diff.

Most AI coding assistants optimize for "did it compile". This one also asks *should this exist* and *what does it cost the business to own forever*.

## The three gates

| Gate | Asks |
|---|---|
| **Senior Engineer** | Is it the simplest thing that works? Edge cases named? Queries parameterized? Failures loud? Tests present? |
| **Product Manager** | WHO hits WHAT pain WHEN? What's the evidence? What's the thinnest slice? What metric proves it worked? |
| **CEO** | Which business metric moves, and via what chain? What's the worst realistic failure? Who maintains it in three years? What are the kill criteria? |

Every review ends with a fixed verdict block:

```
**God Dev Verdict**
- **Engineer:** PASS / FLAG — <most important issue, with file/line>
- **PM:** PASS / FLAG — <problem statement + success metric, or what's missing>
- **CEO:** PASS / FLAG — <expected business impact or the unknown blocking it>
- **Call:** SHIP / FIX FIRST / RETHINK
```

`SHIP` = all three pass. `FIX FIRST` = engineering flags only. `RETHINK` = the PM or CEO gate failed — implementation stops until you resolve it.

## Install

**All projects** (user-level):

```bash
git clone https://github.com/xhanthis/god-dev.git /tmp/god-dev
mkdir -p ~/.claude/skills/god-dev
cp /tmp/god-dev/skills/god-dev/SKILL.md ~/.claude/skills/god-dev/SKILL.md
```

**One project** (repo-level, checked in for the whole team):

```bash
mkdir -p .claude/skills/god-dev
curl -sL https://raw.githubusercontent.com/xhanthis/god-dev/main/skills/god-dev/SKILL.md \
  -o .claude/skills/god-dev/SKILL.md
```

Restart Claude Code — skills load at session start.

## Use

Invoke explicitly with `/god-dev`, or let it fire on its own. The description triggers it whenever you ask Claude to write, review, refactor, or plan code, whenever a diff or PR is being prepared, and whenever a new feature idea shows up — including the bare questions "should we build this?" and "is this code good?".

## Ground rule

Any number in a review must be real — from the repo, your analytics, or a named public source. Unknown impact is reported as **unknown**, alongside what to instrument to find out. No invented statistics.

## License

MIT
