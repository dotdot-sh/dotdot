---
name: dot-document-feature
description: Turns a raw description of a feature idea into a fully documented feature, following the bundled feature template. Use whenever the user describes a new feature, capability, or user-facing change to build.
---

# Document a Feature

## Goal
Given a user's description of a feature (in any level of detail), produce a complete, accurate `.dot/Features/fNNN--<slug>.md` entry following `feature-template.md` (bundled with this skill), without making the user do the writing.

**This skill documents the feature. It does not implement it.** Stop once the file is created/updated and confirmed (Process step 10) — do not write, edit, or scaffold any code, even if the original request read like a build request and even if the next step seems obvious. Implementation is a separate, explicit ask; keeping that boundary is what keeps the user in control and token usage low. If you're unsure whether to keep going, stop and ask rather than continuing into implementation.

## When to invoke
The user is describing something to build, add, or change that's user- or system-facing in nature — not a one-off code edit. Phrasing varies ("we need X", "let's add Y", "I want the app to Z", "new feature"); treat brevity as a cue to derive more and ask less, not as a reason to skip documenting.

## Before Start

Inform the user of your invocation of this skill by outputting exactly: 🧮🧮🧮 BEGIN DOCUMENTING FEATURE

## Process
1. **Confirm intent.** Unless the user explicitly asked to document/create a feature (or named this skill directly), you're invoking this skill on your own judgment — so before gathering context or drafting anything, ask the user directly whether they want to document this as a new feature. A plain question is enough; this doesn't need a full Interview Tool round. If they agree, proceed. If not, stop this skill and continue as a normal conversation using your default process.
2. **Survey existing features.** Run `bash dot scan:frontmatter .dot/Features/` to get a lightweight index (name + description per file) without reading full file bodies.
3. **Duplicate check.** From that index, judge whether an existing feature already covers this request. If a plausible match exists: tell the user its path, run a command to dump its content (e.g. `cat <path>`) rather than pasting it into your response, and ask whether to update that file or proceed with documenting a new one. Wait for their choice before continuing.
4. **Gather remaining context.** Read the related context files (`.dot/*.md`) from your context memory/window (only reload them if they aren't present in your context window). Run `bash dot scan:frontmatter .dot/Decisions/` for candidate matches.
5. **Draft a first pass** at every section of `feature-template.md` using only the request + context gathered. Mark each section **confident**, **best guess**, or **blank/unknown**.
6. **Collapse gaps into questions** — the smallest set that resolves the "best guess"/"blank" sections. See Interviewing Guidelines.
7. If there's anything to ask, run **one** Interview Tool round (the harness's interactive-question capability — e.g. Claude Code's `AskUserQuestion`). Only run a second round if an answer opens up a genuinely new, material question; don't chain rounds by default.
8. Fold answers into the draft.
9. **Create or update the file.** See Output section below to know how.
10. **Confirm.** Run a command to dump its content (e.g. `cat <path>`) rather than pasting it into your response. Then report per the Reporting template in `AGENTS.md`: ✅ the filepath, 👉 ask whether the documentation is correct. Proceeding on an unchallenged draft counts as acceptance, but the user must see it first.

## Interviewing Guidelines
- Never ask about anything explicitly or clearly told by the user.
- For everything else, propose your own best guess as part of the question rather than asking open-ended. Ground the guess in real context (a similar existing feature, a stated product principle, the obvious default) and say why, briefly.
- Batch questions into a single Interview Tool call. Only ask them one at a time or across rounds if a later question can't be framed until an earlier one is answered.
- Target 2–4 questions for a typical feature. If your gap list is longer than that, it usually means the request itself is too vague to document yet — say so, and ask the one clarifying question that unblocks the rest, rather than firing off a long form.
- If your best guess is the only plausible answer given context, don't turn it into a question — state it as an assumption in the draft instead and let the user correct it when they review.
- The user's answer always overrides your guess. No answer / accepting the draft as shown counts as agreeing with the guess.

Cover these dimensions as relevant:
- **Scope:** What exactly is included and excluded?
- **User types:** Which user types interact with this feature (Guest, User, Admin)?
- **Authorization:** Who can do what? What happens on unauthorized access?
- **Behavior:** Golden path, edge cases (honest mistakes and failures), adversarial cases (malicious use), error states.
- **UI/UX:** Where does this appear? What components are involved?
- **Routes:** URL structure and naming.
- **Data model:** New models, relationships, schema changes, attributes.
- **Validation:** Input rules and error messages.
- **Side effects:** Notifications, events, jobs, logging.

## Template
The exact shape of a documented feature lives in `feature-template.md` (bundled alongside this skill, in the same directory). Read it before drafting. Fill every section it defines, in order — see Output for how the result gets written.

**Empty sections.** If a section has nothing relevant, write exactly `None`. Never pad it with prose explaining why it's empty, what might go there later, or restating the section's purpose.

**Naming.** The `--name` slug is `{area}-{subject}`: the area is the part of the codebase whose code the feature owns, the subject a short noun phrase for what it is or adds (never `new-`, `extend-`, `v2`). Check `.dot/Decisions/` for a feature naming decision, which sets the project's areas and wins over this default.

**References.** Every reference to external material (decisions, rules, features, standards, context docs) is the filename alone — list them, one per line. No descriptions, no summaries, no parenthetical explanations of what the file says. If nothing applies, write `None`.

**Feature-Specific Decisions.** Only consequential decisions belong here: a chosen approach or tradeoff that constrains implementation and isn't already visible elsewhere in the doc. Do not restate anything the BDD scenarios already define — a branch, a fork, an error path, or a validation rule expressed as Given/When/Then is not a decision. Most features have none; write `None` rather than inventing entries.

**Specification content.** The Specification is the golden path plus the edge and adversarial cases that follow from the product, and nothing else.

- Write a `Golden` scenario for each thing the feature must do.
- Under each one, write its `Edge` scenarios (honest malfunctions and misuse: what the user gets wrong, what the outside world returns) and its `Adversarial` scenarios (malicious intent: what an attacker tries, what must be refused). A golden and its cases sit together — never a separate section.
- Only **behavioural** cases belong here: ones knowable from the product before the code exists. Mechanical cases found while implementing (a config value that is `""` not `null`, a library returning an unexpected shape) belong in the tests, and get written back here if they matter to the product.
- A golden scenario with no Edges beneath it, or no Adversarials where untrusted input reaches it, means its failure or attack modes have not been thought through. Say so rather than leaving it bare.
- If a scenario cannot be tested (enforced by a third party, needs a live call), say so on the scenario line.

**Specification formatting.** Each scenario is one paragraph: the `**Scenario (Golden|Edge|Adversarial):**` line and its `Given`/`When`/`Then` (and `And`/`But`) lines each start on their own line, with no blank line between them. Use a blank line only to separate one scenario from the next — never within a scenario. For example:

```
**Scenario (Golden):** Successful password reset
**Given** a registered user with a verified email address
**When** they submit a reset request from the login page
**Then** the system sends a reset link valid for 30 minutes

**Scenario (Edge):** Reset link expired
**Given** a user has requested a password reset
**When** they click the link after the 30 minute window has passed
**Then** they see an expired-link error and can request a new one

**Scenario (Adversarial):** Probing for registered email addresses
**Given** an attacker with a list of email addresses
**When** they request a reset for each one
**Then** every response is identical, and only registered addresses receive an email
```

## Output
- **New feature** — run `bash dot document:feature` rather than writing the file yourself. Pass each filled section as its matching flag (e.g. `--description "..."`, `--specification "..."`; run with `--help` for the full, template-derived list). It determines the next `NNN`, builds `.dot/Features/fNNN--<slug>.md`, and writes the content — never construct the filename, number, or write the file yourself.
- **Update** (existing feature chosen during the duplicate check in step 3) — no tool for this yet; edit that file directly, preserving its existing frontmatter `name` and number.

## Finishing

Your very last step before exiting the feature is to inform the user of task completion by responding with exactly: ✅✅✅ DONE DOCUMENTING FEATURE

Then stop. Do not go on to implement the feature, plan the implementation, or touch any code — this skill's job ends at the documented file. Wait for the user to separately ask for implementation.
