---
name: dot-document-decision
description: Turns a project decision the user has made into a documented decision in .dot/Decisions/, following the bundled decision template — after establishing what they actually mean, which existing decisions bear on it, and which built features it disturbs. Use whenever the user settles a question about how the project works and wants it written down: "we've decided to X", "from now on we always Y", "let's standardise on Z", "document this decision", "record an ADR", or when they state a rule or a tradeoff as though it is now settled. Reach for it even when they don't use the word "decision" — a sentence in the shape of "we should always/never ..." is one.
metadata:
  internal: true
---

# Document a Decision

## Goal
Produce `.dot/Decisions/dNNN--<slug>.md` from a decision the user has made, following `decision-template.md` (bundled alongside this skill).

**This skill documents the decision. It does not implement it.** Stop once the file is written and confirmed. Features the decision contradicts get reported, never edited.

## Before Start

Output exactly: 🔏🔏🔏 BEGIN DOCUMENTING DECISION

## Process

### 1. Confirm intent
If the user did not explicitly ask to document a decision, ask before doing any work. If they decline, stop and continue as a normal conversation.

### 2. Establish the decision
A decision is a rule that constrains future work, plus the reason it exists. You need three things:

- **Rule** — what must now always or never happen, and to whom.
- **Reason** — what it buys and what it costs. No cost recorded usually means a preference, not a decision, and the first person to hit the cost will overturn it.
- **Boundary** — where it stops applying.

Never invent the reason. A missing rationale is better than a plausible one the user never gave, which will be cited later as though they did.

### 3. Find related decisions
```sh
bash dot scan:frontmatter .dot/Decisions/
```
Sort every hit into one case:

- **Duplicate** — already recorded. Show the user (`cat <path>`), ask whether to update it instead, and wait. Updating prose has no tool: edit the file, keep its number, bump `modified`.
- **Influence** — shaped this one → `## Influenced By`.
- **Replacement** — this one takes over → retire it with `bash dot decisions:update <NNN> --superseded <new NNN>`, only with the user's agreement and only once the new decision has a number.
- **Partial change** — narrows it, adds an exception, makes it conditional → **stop and ask**: edit that decision, or supersede and rewrite it. Never record this as a link; the old decision would go on reading `accepted` while being wrong, in the file people actually read.

Only open a decision in full to corroborate your findings, or when the index cannot settle which case applies.

### 4. Find impacted features
Both passes, in this order — declared links first, guesses second (when in doubt run command with `--help` flag for usage):

```sh
bash dot decisions:impact --decisions "<the influences from step 3>"
bash dot decisions:impact --terms "<nouns the decision constrains>"
```
The first finds features that cite those decisions, so they were built on ground this decision is moving — the likeliest contradictions. Skip it only if step 3 found no influences. The second catches what nobody declared; precise nouns beat broad ones.

Sort every hit:

- **Contradicted** — the feature now violates the decision → `## Impacts`, and name it in step 7.
- **Constrained** — compatible, but now bound by it → `## Impacts`.
- **Coincidental** — omit. A section padded with unjudged hits is worth less than an empty one.

No hits is an answer, not a failed search.

### 5. Fill the gaps
Draft every part of the template, marking each **confident**, **best guess**, or **blank**. Collapse the blanks into one Interview Tool round (the harness's interactive-question capability — e.g. Claude Code's `AskUserQuestion`). A second round only if an answer opens a genuinely new question.

### 6. Write
```sh
bash dot decisions:create --help
```
Run it rather than writing the file yourself; never construct the filename or number.

### 7. Verify, then confirm
```sh
bash dot decisions:impact --check
```
Then `cat` the file, print its path, and state which decisions shaped it, which it supersedes, and which features it **contradicts** — named, with the specific conflict.

The contradictions are the only part needing the user's judgment; the rest is filing. Ask whether it is correct. An unchallenged draft counts as accepted, but they must see it first.

## Criteria
- **References** — pass numbers (`002`, `7`) and let the scripts resolve and link them. Never hand-write a link.
- **Reverse lookups** — every relation is stored once, on the decision that declares it. Run `bash dot decisions:impact --inbound <NNN>` before leaning on or changing an existing decision.
- **Length** — a decision needing three screens is two decisions, or an essay. Say so and offer to split it.

## Interviewing
- Never ask what the user already told you.
- Put your best guess in the question, grounded in something real, and say why briefly. Target 2–4, in one batch.
- The tradeoff is the question most worth asking: users skip it, and it is what makes the decision defensible later.
- If your guess is the only plausible answer, state it as an assumption instead of asking.
- The user's answer always overrides your guess.

## Finishing

Output exactly: ✅✅✅ DONE DOCUMENTING DECISION

Then stop. Implementing the decision, refactoring to comply with it, or editing the features it affects are separate, explicit asks.
