---
name: god-writer
description: "Writing and editing. Use for any prose going to a person or the public — PR descriptions, docs, memos, emails, release notes, blog posts, tweets — and whenever the user asks to humanize, de-AI, tighten, shorten, or edit text. Makes it clearer and shorter without making it weaker, strips AI tells, matches the user's voice, and learns the user's style over time."
license: MIT
author: Siqi Chen (@blader, https://github.com/blader/humanizer); adapted as "God Write" for Claude Code
---

# God Writer

Core question: **Can this be clearer, shorter, and sound like a person wrote it?**
Principle: editing is compression, not reinterpretation — clearer and shorter without weaker.

Identify and remove signs of AI-generated text to make writing sound natural and human. Based on Wikipedia's "Signs of AI writing" guide (maintained by WikiProject AI Cleanup), derived from observations of thousands of AI-generated text instances.

**Key insight:** LLMs use statistical algorithms to guess what should come next. The result tends toward the most statistically likely completion, which is how the telltale patterns below get baked in.

## When to use this skill

Load this skill whenever the user asks to:
- "humanize", "de-AI", "de-slop", or "un-ChatGPT" a piece of text
- rewrite something so it doesn't sound like it was written by an LLM
- edit a draft (blog post, essay, PR description, docs, memo, email, tweet, resume bullet) to sound more natural
- match their voice in writing they're producing
- review text for AI tells before publishing

Also apply this skill to **your own** output when writing user-facing prose — release notes, PR descriptions, documentation, long-form explanations, summaries. Your baseline voice already strips most of these, but a focused pass catches what slips through.

## How to use it in Claude Code

The text usually arrives one of three ways:
1. **Inline** — user pastes the text directly into the message. Work on it in-place, reply with the rewrite.
2. **File** — user points at a file. Use `Read` to load it, then `Edit` or `Write` to apply edits. For markdown docs in a repo, a targeted `Edit` per section is cleaner than rewriting the whole file.
3. **Voice calibration sample** — user provides an additional sample of their own writing (inline or by file path) and asks you to match it. Read the sample first, then rewrite. See the Voice Calibration section below.

Always show the rewrite to the user. For file edits, show a diff or the changed section — don't silently overwrite.

## Your task

When given text to humanize:

1. **Identify AI patterns** — scan for the 29 patterns listed below.
2. **Rewrite problematic sections** — replace AI-isms with natural alternatives.
3. **Preserve meaning** — keep the core message intact.
4. **Maintain voice** — match the intended tone (formal, casual, technical, etc.). If a voice sample was provided, match it specifically.
5. **Add soul** — don't just remove bad patterns, inject actual personality. See PERSONALITY AND SOUL below.
6. **Do a final anti-AI pass** — ask yourself: "What makes the below so obviously AI generated?" Answer briefly with any remaining tells, then revise one more time.


## Editor pass (every piece, before the humanize pass)

- Surface the conclusion to the top; details follow.
- Remove unnecessary words, redundancy, and contradictions — every sentence must survive the delete test.
- One idea per paragraph; headers only where a reader would scan for them.
- Adapt to the audience (engineer, investor, customer, a 15-year-old) without dumbing down.
- Preserve meaning exactly.

## Humanize pass

The 29 patterns, voice calibration, and the worked example live in `references/ai-patterns.md` — load it when rewriting anything longer than a paragraph.

## Process

1. Read the input text carefully (use `Read` if it's a file).
2. Identify all instances of the patterns above.
3. Rewrite each problematic section.
4. Ensure the revised text:
   - Sounds natural when read aloud
   - Varies sentence structure naturally
   - Uses specific details over vague claims
   - Maintains appropriate tone for context
   - Uses simple constructions (is/are/has) where appropriate
5. Present a draft humanized version.
6. Prompt yourself: "What makes the below so obviously AI generated?"
7. Answer briefly with the remaining tells (if any).
8. Prompt yourself: "Now make it not obviously AI generated."
9. Present the final version (revised after the audit).
10. If the text came from a file, apply the edit with `Edit` (targeted) or `Write` (full rewrite) and show the user what changed.

## Output Format

Provide:
1. Draft rewrite
2. "What makes the below so obviously AI generated?" (brief bullets)
3. Final rewrite
4. A brief summary of changes made (optional, if helpful)


## Learn

Close every run with `god-ceo/references/learning-loop.md`. Capture: the user re-editing a sentence you produced (record the before/after as a voice rule), a phrase the user flags as AI-sounding, a self-review line. Voice rules are **personal** scope and live in `~/.claude/god/god-writer/lessons/personal.md`; read them first on every run. A pattern that fools every user is universal and may be promoted to `references/ai-patterns.md`.

## Attribution

This skill is ported from [blader/humanizer](https://github.com/blader/humanizer) (MIT licensed), which is itself based on [Wikipedia: Signs of AI writing](https://en.wikipedia.org/wiki/Wikipedia:Signs_of_AI_writing), maintained by WikiProject AI Cleanup. The patterns documented there come from observations of thousands of instances of AI-generated text on Wikipedia.

Original author: Siqi Chen ([@blader](https://github.com/blader)). Original repo: https://github.com/blader/humanizer (version 2.5.1). Adapted as **God Write** for Claude Code with Claude Code tool references (`Read`, `Edit`, `Write`) and guidance for when to load the skill; the 29 patterns, personality/soul section, and full worked example are preserved verbatim from the source. Original MIT license preserved in the `LICENSE` file alongside this `SKILL.md`.

Key insight from Wikipedia: "LLMs use statistical algorithms to guess what should come next. The result tends toward the most statistically likely result that applies to the widest variety of cases."
