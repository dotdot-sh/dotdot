---
name: dot-implement-feature
description: Implements a feature against its failing tests, one test at a time, following the Implementation Plan and the project's existing code style. Use whenever tests are red and the code needs writing, a plan is ready to build, or the user says anything like "make the tests pass", "now implement it", "go build this", or "turn it green".
---

# Implement

## Goal
Turn the feature's failing tests green, one test at a time, writing code that matches how this project already writes code.

## Before Start
Output exactly: 💻💻💻 BEGIN IMPLEMENTING

## Process

1. **Load the target.** Read the feature doc's `Implementation Plan` (steps, file paths, out of scope), `Specification`, and `Constraining Rules`, plus the failing test files. Follow `RULES.md` and `STANDARDS.md`; a `Constraining Rules` entry is a decision already made, not a suggestion.

2. **Confirm red.** Run the feature's tests scoped to their path or filter. Note exactly which fail and why. If something fails for a setup reason rather than missing behavior, fix that first — you can't drive off a broken signal.

3. **Loop, one test at a time.** Take the next failing test in plan order:
   - Read the file you're about to change, or its closest neighbors, before writing. Match their structure, naming, error handling, and helpers. Reuse an existing component or helper over writing a new one — check first.
   - Write the smallest code that makes that one test pass honestly. Not a stub keyed to the assertion, not the next three steps' worth of code.
   - Run that test alone. Green → move on. Red → fix the code.
   - Don't start the next test while this one fails, unless you're stuck.

4. **Never weaken a test to make it pass.** If a test looks wrong or blocks implementation, improve the test but never weaken it — RULES.md forbids weakening tests, and a test bent to fit the code is no longer driving anything. If the test is correct but you cannot implement the code, inform the user.

5. **Stop if the plan is wrong.** If a step can't work as written, report it and wait. Improvising a different design mid-build means shipping something the user never approved.

6. **Ask First on discovery.** A new dependency, Critical Path, data model change, or billing logic that the feature doc's `Constraining Rules` doesn't already cover goes to the user before you write it.

7. **Green, then check for collateral damage.** Run the feature's full test set, then the wider suite for the area you touched. Passing your test while breaking someone else's isn't done. Use the test flags and scope the project's context prescribes.

8. **Run the tooling; don't do its job by hand.** Formatting, linting, and code generation are scripted — hand-editing style wastes turns and diverges from the project's config. Use the formatter, generators, and schema workflow `STANDARDS.md` and `TECHSTACK.md` name, and activate other skills when their domain applies.

9. **Document references and relations.** After each test, update the File Map per the template, DATAMODEL, Decisions, and related features. Find usages with a kit's references command when one is installed (`bash dot` lists them). Re-check all of it once done.

10. **Clean up:** Remove the `Implementation Plan` section once done.

11. **Report** per the Reporting template in `AGENTS.md`.

## Scope
Build what the plan covers, nothing past it. Refactors, cleanups, and improvements you notice along the way get mentioned in the report, not committed silently — unplanned changes are the ones nobody reviews.

## Finishing
Output exactly: ✅✅✅ DONE IMPLEMENTING
