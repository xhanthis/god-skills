# God Skills

[Claude Code](https://claude.com/claude-code) skills I use every day. Two so far.

| Skill | What it does | Fires on |
|---|---|---|
| **[God Dev](#god-dev)** | Puts every change through three review gates — senior engineer, product manager, CEO — once on the plan and once on the diff. | `/god-dev`, or on its own when you write, review, refactor, or plan code or a PR. |
| **[God Write](#god-write)** | Strips AI-isms from prose and puts a human voice back in. Codifies the 29 tells from Wikipedia's "Signs of AI writing". | `/god-write`, or when you humanize, de-slop, or match-voice a draft before publishing. |

## Install

Each skill is a single `SKILL.md`. Put it under `~/.claude/skills/<name>/` for every project, or `.claude/skills/<name>/` to check it into one repo. Restart Claude Code — skills load at session start.

```bash
# all projects — swap god-dev for god-write to install the other
git clone https://github.com/xhanthis/god-skills.git /tmp/god-skills
mkdir -p ~/.claude/skills/god-dev
cp /tmp/god-skills/skills/god-dev/SKILL.md ~/.claude/skills/god-dev/SKILL.md
```

```bash
# one repo, checked in for the team
mkdir -p .claude/skills/god-write
curl -sL https://raw.githubusercontent.com/xhanthis/god-skills/main/skills/god-write/SKILL.md \
  -o .claude/skills/god-write/SKILL.md
```

---

## God Dev

Most AI coding assistants optimize for "did it compile". This one also asks *should this exist* and *what does it cost the business to own forever*.

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

`SHIP` = all three pass. `FIX FIRST` = engineering flags only. `RETHINK` = the PM or CEO gate failed, so implementation stops until you resolve it.

Hard cap of 10 lines before the verdict, one line per flag (`file:line — problem. fix.`), max three flags per gate. A gate that passes says `PASS` and nothing else. If the review is longer than the change, the review is wrong.

**Ground rule:** any number in a review must be real — from the repo, your analytics, or a named public source. Unknown impact is reported as **unknown**, alongside what to instrument to find out. No invented statistics.

## God Write

Sterile, voiceless writing is as obvious as slop, so this skill does two things: it removes the AI tells, then it puts a human back in. The 29 patterns come from Wikipedia's [Signs of AI writing](https://en.wikipedia.org/wiki/Wikipedia:Signs_of_AI_writing) — significance inflation, copula avoidance ("serves as" for "is"), the rule of three, em-dash overuse, chatbot artifacts ("Great question!"), knowledge-cutoff hedging, and the rest.

Load it when you ask to humanize, de-AI, or de-slop text, rewrite a draft (blog post, PR description, docs, email, tweet) to sound natural, match a supplied voice sample, or review prose for AI tells before publishing. It also applies to Claude's own user-facing prose — release notes, PR bodies, long explanations.

Adapted from [blader/humanizer](https://github.com/blader/humanizer) (MIT, Siqi Chen). The 29 patterns, the personality/soul section, and the worked example are preserved verbatim; only the tool references were swapped for Claude Code (`Read`/`Edit`/`Write`). Original license lives in `skills/god-write/LICENSE`.

## License

MIT — see [`LICENSE`](LICENSE). God Write keeps its own MIT license (Siqi Chen) in [`skills/god-write/LICENSE`](skills/god-write/LICENSE).
