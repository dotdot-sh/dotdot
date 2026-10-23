---
name: dot-align-and-clean
description: Autonomously audits and realigns a project so concept, dotdot docs, decisions, tests, and code agree — fixes drift, dead code and dead docs, tests that cannot fail, stale File Maps, and violated or missing decisions, involving the user only for decisions that are genuinely theirs. Use when the user asks for a cleanup, an alignment pass, a health check, "make sure docs and code match", "is anything stale or dead", "check the test suite", "clean up the features/decisions", or after a large rework.
---

# Align and Clean

## Goal
Concept, Context docs, Decisions, Feature docs, tests, and code say the same thing, with nothing dead, duplicated, or unverifiable left — with as little of the user's time as possible.

## Before Start
Output exactly: 🧹🧹🧹 BEGIN ALIGN AND CLEAN

## Autonomy
Do the work. Decide and fix everything you can settle from the sources of truth, the rules, and the existing patterns.

Involve the user only when:
- the fix hits an Ask First item (see RULES.md);
- concept and code disagree and neither side is clearly the stale one;
- the fix is destructive or irreversible.

Then interview once, batched:
- Each option is a complete resolution path, not a single edit. For a drifting feature, that means the code change, the spec and its BDD cases, the tests, the File Map, the decisions, and the wording.
- Put the recommended option first, and say why in one line.
- Keep working on everything else while waiting; never stop the whole pass for one question.

## Rules
- Never skip, delete, or weaken a test to go green. Removing a duplicate is fine; removing coverage is not.
- Throwaway scripts live in the scratchpad, never in the project.
- Write for the reader: lists over tables, minimum words, no history.

## Process

### 1. Sources of truth
Use the product doc, accepted decisions, and features. Ask only if drafts or ideas could change the outcome.

### 2. Audit
Read Context docs, Decisions, and Features in full, then the code module by module. Look for:
- **Code vs concept:** behaviour that differs from a spec or decision.
- **Dead code:**
  - unreachable branches (guards the constructor, type system, or defaults already rule out);
  - test-only production code;
  - enum cases or statuses nothing transitions to;
  - unused dependencies.
- **Duplication:** constants restating config defaults, copied patterns or formats, repeated methods across classes.
- **Stale docs:**
  - old paths and namespaces;
  - historical plan steps;
  - "out of scope" lists contradicting what was built;
  - lifecycle lists missing states;
  - docs contradicting each other.
- **Decisions:** each one holds, is violated, or describes something never built.

Confirm code is "dead" with a kit's references command when one is installed (`bash dot` lists them), re-checking with its loosest search before removing anything.

### 3. Fix the code
- Every behaviour change is test-first: a failing test, then the fix.
- Keep a branch the static analyser needs, and add a standard comment above it; for this occasion is ok to add code comments.
- Run the full suite, static analysis, and the formatter after each batch.

### 4. Fix the tests
- **Profile** the suite: anything slow usually means a real sleep or a real wait.
- **Find tests that cannot fail:**
  - a fake implementing the very behaviour under test;
  - dataset closures that are never executed (a parameter typed `Closure` receives the wrapper, not its result);
  - assertions with slack (`<=`, `not empty`) where an exact value is known.
- **Drop duplicates;** merge near-identical tests into datasets.
- **Add missing edges:** failure handlers, cleanup of child records, inputs with no declaration, crash and redelivery paths.
- **Mutation-check every new or fixed test:** break the code it guards, see it fail, restore, see it pass. Back up files before mutating.

### 5. Fix the Feature specs
Ensure each section fits its respective template.

**Specification:**
- One `Given`, `When`, and `Then` per scenario; extra conditions or outcomes on `And` lines, overrides on `But`.
- Alternatives in one scenario only when they share the outcome; otherwise split.
- Check both directions: every scenario has a test, and every test has a scenario.

**File Map** in three lists:
- **Owns:** directories the feature introduced, code and tests. Single files only when their directory is shared.
- **Touches:** `file@method` in other features' code that this feature changed.
- **Used by:** `file@method` outside Owns that use its code. Generate it from real references (imports plus same-namespace use, mapped to the enclosing method), then drop import-only, constructor-injection, and docblock-only hits. One line per file: `file@a, @b`.
- Verify every listed path and method exists.

Add decision backlinks to the features each decision affects.

### 6. Reconcile decisions
- **Holds:** leave it.
- **Too strict for reality:** reword it, keep the status, refresh the timestamp with the update tool.
- **Never built:** set it to draft.
- **Missing:** record cross-cutting rules settled during the cleanup with `dot-document-decision`, then backlink them from the features.
- **Unrun gates:** a test matrix or real-infrastructure test a decision requires is either run or turned into a test.

### 7. Verify
Full suite, static analysis, and formatter check all pass.

## Report
Per the Reporting template in `AGENTS.md`:
- `✅ <area>: <what was fixed>` — one line per area.
- `⚠️ Critical Path: <what changed>` — every Critical Path change, always listed.
- `🌀 <item>: <why it needs the user>` — only items still open.
- Nothing to fix: `✅ All aligned.`

## Finishing
Output exactly: ✅✅✅ DONE ALIGN AND CLEAN
