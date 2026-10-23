---
name: dot-build-full-feature
description: Takes a feature from idea to working, tested code end-to-end by chaining dot-document-feature → dot-draft-feature-plan → dot-write-tests → dot-implement-feature, entering at whatever stage the work is actually at. Use whenever the user wants a feature built rather than one isolated step — "build X", "add X and ship it", "take this all the way", "pick up f007 and finish it" — or when they describe something to build without naming a stage. Runs the chain; the sub-skills do the work.
---

# Build Feature

## Goal
Carry one feature through the full chain, entering where the work actually stands and stopping where a human is needed.

## Before Start
Output exactly: 🚀🚀🚀 BEGIN BUILDING FEATURE

## The chain
`dot-document-feature` → `dot-draft-feature-plan` → `dot-write-tests` → `dot-implement-feature`

The feature doc is the handoff between them — each stage reads what the last one wrote (`Specification` → `Implementation Plan` → tests → code + File Map). That's also why you can resume mid-chain: the doc holds the state.

## Process

1. **Find the entry point.** Run `bash dot scan:frontmatter .dot/Features/` and check what already exists:
   - no matching feature doc → start at `dot-document-feature`
   - doc exists, `Implementation Plan` empty → start at `dot-draft-feature-plan`
   - plan exists, no tests for it → start at `dot-write-tests`
   - tests exist and are red → start at `dot-implement-feature`

   State the entry point and why before invoking anything. Skipping a completed stage saves the user's time; skipping an *incomplete* one loses the artifact the next stage reads, so never jump ahead to reach code faster.

2. **Pick a mode.** Ask once:
   - **Checkpoint** — confirm at each stage boundary.
   - **Autonomous** — run through, report at the end.

   Autonomy covers the stage confirmations only. The stop conditions below fire in both modes.

3. **Run each stage by invoking its skill.** Don't re-do its work inline or re-read what it already reads — each skill has its own process and its own confirm step. Between stages, verify the artifact the next stage needs actually exists, then continue or hand back per mode.

4. **Stop and report when:**
   - an Ask First trigger surfaces that the feature doc's `Constraining Rules` doesn't already cover (new dependency, Critical Path, data model change, billing/entitlement logic)
   - the plan turns out to be wrong — go back to `dot-draft-feature-plan`, and surface the rewrite even in autonomous mode, since what ships would otherwise no longer be what was approved
   - a test looks wrong — `dot-write-tests` owns that decision, not `dot-implement-feature`
   - a stage can't produce its artifact

   These are the calls that aren't yours to make. Resume once the user answers.

5. **Report at the end** per the Reporting template in `AGENTS.md`: ✅ the feature doc path, plus anything flagged or deferred.

## Scope
One feature per run. If the request covers several, document them separately and confirm which to build first — a chain carrying two features loses the thread of which test drives which code.

## Finishing
Output exactly: ✅✅✅ DONE BUILDING FEATURE
