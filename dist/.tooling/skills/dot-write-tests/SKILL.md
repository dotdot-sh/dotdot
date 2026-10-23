---
name: dot-write-tests
description: Derives and writes meaningful tests from a feature's Specification and Implementation Plan, before any implementation exists, so the tests drive the build (TDD). Use whenever a plan is approved and work is about to start, or the user says anything like "write the tests", "let's do this TDD", "add coverage for X", or asks to implement a planned feature — the tests come first, so reach for this even when they sound ready to write the code itself. Writes and runs tests only; never implements the feature.
---

# Write Tests

## Goal
Turn a feature's `## Specification` scenarios and `## Implementation Plan` steps into tests that fail for the right reason, so implementation has a concrete target.

## This skill writes tests; it does not implement the code
Test files are the only thing you write. The tests are supposed to fail when you're done — that's the deliverable, not a problem to fix. Making them pass is the next, separate step.

## Before Start
Output exactly: 🧪🧪🧪 BEGIN WRITING TESTS

## Process

1. **Read the feature doc.** `Specification` gives the `Golden`, `Edge`, and `Adversarial` scenarios — port every one, don't re-derive them. `Implementation Plan` gives the steps, the real file paths, and what's out of scope. `Constraining Rules` gives anything the tests must respect.

2. **Read one or two existing test files** covering code nearest to what you're testing — from the File Map, or the matching directory in the suite. Match what you find: base test class, test-function style, fixtures or factories, helpers, data-driven style, naming, assertion order and grouping. Conventions are discovered, never invented. When a kit installed a `<kit>-write-tests` skill, follow it too for the framework's specifics.

3. **Map scenarios to tests before writing any.** One test per behavior. Every scenario becomes at least one test, and every plan step is covered by at least one. A plan step with no scenario behind it is a gap — say so rather than inventing a scenario to cover it.

4. **Then attack it.** The Specification lists the cases the product implies; it does not list the ones the implementation invites. For each golden behaviour, ask what a careless caller or a misbehaving dependency would do to it (Edge, for reliability) and what a hostile caller would (Adversarial, for security), and write a test for each answer that would actually break something:
   - **Input:** empty, blank, absent, wrong type, far too long, zero, negative, duplicate.
   - **Security:** untrusted text reaching a shell, a query, a file path, a log, or a flag position. Anything that widens permissions by omission.
   - **Boundaries:** the first and last item, the page boundary, the moment on the watermark, an empty collection.
   - **Dependencies:** an error, a timeout, a success carrying a failure flag, a malformed or partial payload, a missing key.
   - **Money and side effects:** anything that spends, writes, or sends when it should not have.

   These are yours to invent. Name the ones you add and why in the report.

5. **Write the tests**, ordered to match the plan's steps so implementation can go one step at a time.

6. **Run them and read the failures.** Each must fail because the behavior is missing, not because of a typo or setup error. A test that errors before reaching its assertion proves nothing. Fix the test until it fails for the intended reason.

7. **Verify each one can fail.** Break the behaviour a test covers and confirm that test goes red. A test whose setup guarantees its own assertion proves nothing.

8. **Report** per the Reporting template in `AGENTS.md`: the Edge and Adversarial tests you invented beyond the Specification, and any scenario you could not test and why.

## What makes a test meaningful

- **One test, one behavior.** The name states that behavior — "rejects a reset link after 30 minutes", not "tests reset". If you need "and" in the name, it's two tests.
- **Assert the actual consequence.** The failure mode to avoid is a test that would pass against a stub: asserting only a 200, that no exception was thrown, or that a method got called. Assert the state or output the user would notice — the row is gone, the token is rejected, the response carries the right value.
- **Test observable behavior, not internals.** Private methods, call counts, and mocks of code you own bind tests to one implementation and break on refactors that changed nothing real.
- **Arrange, act, assert — no branching.** No `if`, loops, or try/catch in a test body. A test that needs control flow is testing more than one thing; split it. Use the framework's data-driven tests for the same assertion over varying input.
- **Minimal setup.** Only what the behavior needs. Reach for the suite's existing fixtures or factories rather than hand-building data. Sprawling setup usually means the test is aimed too wide.
- **Independently failing.** When it goes red, it should be obvious which single thing broke.
- **Don't test the framework.** Validation rules firing, relationships loading, a route resolving — the framework has its own tests. Test what your feature decided.

## Structure
`STANDARDS.md` is the authority; the shape it requires:

- One directory per feature, named for it: `fNNN--<slug>/`, in the suite's feature-test location.
- Files named for a **product behaviour**, never a class — "caching notes", not "sync command". Technical angles go with the unit tests.
- Each file groups its tests, in order: `Golden`, `Edge`, `Adversarial`. No prefixes on test names, no deeper nesting — split into another file instead.
- A file with no `Edge` group, or no `Adversarial` group where untrusted input reaches the code, is unfinished.

## Scope
Test what the plan covers. Anything the plan lists as out of scope gets no test. If a step genuinely can't carry an automated test, say which manual verification replaces it instead of writing a hollow one to fill the slot.

## Finishing
Output exactly: ✅✅✅ DONE WRITING TESTS

Then stop. The tests are red by design — do not write implementation code to turn them green.
