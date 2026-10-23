---
name: dot-draft-feature-plan
description: Drafts a sound, concrete implementation plan into a feature's Implementation Plan section, grounded in dotdot's Context docs instead of a fresh read of the codebase. Use whenever the user asks to plan, scope, sequence, or "figure out how to build" something, picks up a .dot/Features/fNNN doc to start work on it, or says anything like "how would we implement this", "what's the approach", or "let's build X" — reach for it even when they sound ready to jump straight into code. Plans only; never implements.
---

# Draft a Plan

## Goal
Fill the `## Implementation Plan` section of `.dot/Features/fNNN--<slug>.md` with a plan concrete enough to build from without further discovery. This skill does not replace the way you plan work, it simply gives you a place to document it and a few tools to work with files and relations.

## This skill plans; it does not build
The feature doc is the only file you write. No source, migrations, tests, or other Context docs. Stop once the section is filled and the user has seen it — including when the request sounded like "just build it".

## Before Start
Output exactly: 🗺️🗺️🗺️ BEGIN DRAFTING PLAN

## Process

1. **Find the feature doc.** Named or linked, read it in full. Otherwise, run `bash dot scan:frontmatter .dot/Features/` and ask about any plausible match. If there's no match, confirm with the user if they want to create one, if yes, run the `dot-document-feature` skill first; otherwise proceed with planning a feature or task as you normally do.

2. **Gather only what this feature touches.** Reuse what's already in your context window. Use `bash dot scan:frontmatter .dot/` to read descriptions first, pull full bodies only where they matter. A doc with `ignore: true` was never filled in, and you can skip it.

3. **Discover files in this order. Stop as soon as you have what you need.**
   1. **The feature's own File Map** — `filepath@method`, `filepath:lines`.
   2. **Related Features' File Maps** — open only the docs named in `Related Features`. A file appearing there means that feature is affected; name it in the plan.
   3. **Sensible browsing** — only for what steps 1–2 left uncovered. A targeted search with a kit's references command when one is installed (`bash dot` lists them), or reading a specific directory you have concrete reason to expect the file in. Never a project-wide sweep: RULES.md forbids scanning the whole project, and an untyped search is that scan in disguise.

   File Maps are tool-generated after implementation, so unimplemented features have none and older ones lag. Empty is not evidence of no impact — it means the check can't answer and the next level has to. If level 3 still can't answer, record it as an open question rather than widening the search.

4. **Surface a wrong feature doc.** If what you read contradicts or under-specifies the doc, say so — don't quietly plan around it. Note it as an open question, or suggest re-running `dot-document-feature` if scope actually moved.

5. **Resolve gaps.** One Interview Tool round, batched, each question carrying your best guess and why. Ask only what blocks drafting. Don't reopen what `dot-document-feature` already settled.

6. **Draft the plan** to the bar below, then write it into the doc's `## Implementation Plan` section yourself, replacing whatever body is there. Leave every other section untouched, and leave the `### DoD` checklist at the end of the section exactly as it stands — ticks included.

7. **Confirm.** `cat` the file rather than pasting it into your response, print its path, ask the user to confirm.

## What makes a plan sound
Ordered, concrete steps:

- **Name real files** from step 3 — `src/auth/reset-controller` and the exact function, not "the controller." Couldn't determine a path? Open question, not a guess.
- **Each step independently verifiable.** When implementation can't go green, the failure must localize to one step. Three giant steps leave a stuck implementer nowhere to return to, and that's where improvising against an unapproved spec starts.
- **State important decisions, don't bury them** — approach chosen over which alternative, and why. That's the raw material for a `.dot/Decisions/` entry at sync time.
- **List affected features by name**, with what about them is affected.
- **State what's out of scope**, so implementation doesn't wander.
- **Open questions are their own items**, visible, not smoothed over.
- **No step may require a scan to execute.** "Find everywhere X is used" gets resolved now or recorded as an open question.

**Keep the DoD checklist** that sits at the end of the Implementation Plan section — it is not part of the plan body you replace. Drop only a line this feature categorically can't touch; whether the rest apply is usually only knowable once the code exists.

## Finishing
Output exactly: ✅✅✅ DONE DRAFTING PLAN

Then stop. No tests, no implementation code, however obvious the next step looks.
