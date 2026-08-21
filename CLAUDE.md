# God Skills — routing map

29 skills that behave like one organization. This file is the map: which skill owns
what, in what order they run, and who hands to whom. Read it before picking a skill.

Skills live in `skills/<name>/SKILL.md`. Each is a folder with YAML frontmatter
(`name`, `description`) and a body. The `description` is what makes a skill trigger —
edit it with care.

## The pipeline

```
USER → god-context → god-cos → specialists → god-da → god → god-police → EXECUTE
```

- **god-context** — front door. Any vague or bug-style request ("X is wrong", "this is
  slow") starts here. It investigates before asking and produces a problem statement.
- **god-cos** — router. Picks the minimum set of specialists and their order.
- **god-da** — attacks any significant conclusion before it becomes a decision.
- **god** — issues the final verdict when specialists disagree or a call must be made.
- **god-police** — integrity gate. Audits the trail before any PASS or SHIP.

Skip the front door only when the request already names its domain ("write the pricing
page copy" → god-cmo). Never skip god-police on a PASS or SHIP.

## Where to start

| Situation | Entry skill |
|---|---|
| Vague request, bug report, "X is broken" | god-context |
| Multi-domain request, unclear who owns it | god-cos |
| Writing or changing any code | god-architect → god-dev |
| Verifying code works | god-tester |
| What should we build, and why | god-pm |
| Where should the business go | god-strategist |
| Money, margins, reconciliation | god-cfo |
| What to charge | god-pricer |
| Market, competitors, what is true | god-researcher |
| SQL, funnels, cohorts, metrics | god-data |
| Acquisition, activation, retention | god-growth |
| UX flows, journeys, interaction | god-designer |
| Would customers care | god-customer |
| Positioning, messaging, launch | god-cmo |
| ICP, qualification, sales strategy | god-sales |
| SOPs, process, ownership, SLAs | god-ops |
| Threat modeling, authz, secrets | god-security |
| Indian law and compliance | god-pl |
| Stress-test a decision | god-da |
| Final call, deadlock between agents | god |
| Did anyone cut corners | god-police |
| Tighten prose for an audience | god-editor |
| Strip AI-isms from writing | god-write |
| Remove complexity | god-simplifier |
| What are we missing | god-scout |
| Why did we decide this | god-historian |
| Plan the day or week | god-plan |
| Is this pace sustainable | god-health |

## Standard sequences

- **Engineering** — context → pm → (designer) → architect → dev → tester → security →
  (cfo if financial logic) → (pl if legal) → (da if significant) → police → ship
- **Product** — context → pm → researcher/data/customer/growth/designer → cfo/pricer →
  strategist → pm synthesis → da → god → police
- **Financial** — context → cfo → (pricer/researcher/data/pl) → da → god → police
- **Research** — context → researcher → (data) → pm/strategist/cmo → da → god
- **Operations** — context → pm → ops → simplifier → (architect/dev/tester) → police

Adapt these, don't inflate them. Never invoke a skill for show.

## Failure loops

```
tester → dev → tester
security → dev → tester → security
cfo → dev → tester
police → agent → rework → police
```

god-tester caps at three fix-and-retest cycles, then hands the failure back.

## Hand-offs

Each skill's own `## Route` section is authoritative. The recurring edges:

- Evidence needs: external → **god-researcher**, internal/quantitative → **god-data**,
  desirability → **god-customer**
- Implementation: design → **god-architect**, code → **god-dev**, proof → **god-tester**
- Validation: money → **god-cfo**, exploitability → **god-security**, Indian law → **god-pl**
- Decisions: **god-da** → **god** → **god-police**

## Rules every skill obeys

- **No fabrication.** Numbers come from the repo, real analytics, or a named public
  source. Unknown impact is reported as unknown, plus what to instrument.
- **Proof over claims.** Tests that could not run return `UNVERIFIED`, never `PASS`.
- **Adversarial before final.** Nothing significant reaches a decision without god-da.
- **Brevity.** Lead with the finding, one line per point, max three points, no prose on
  a pass. If the review is longer than the change, the review is wrong.

## Working on this repo

- Skill bodies are prose, not code — there is no build or test step.
- A skill's `description` is its trigger. Write it as a condition ("Use when…",
  "Use BEFORE…"), not as a description of behavior.
- `name:` must match the folder name exactly; the installer keys off the folder.
- Adding a skill: create `skills/<name>/SKILL.md`, then add it to the README table and
  the tables above. `bin/god-skills.js` discovers skills from the folder, so it needs
  no change.
