---
name: dot-onboarding
description: Onboards you to this project the way a team would onboard a new engineer — what the project is, the rules that bind your work, where the context lives, which tools and skills you have, and how work flows from feature to plan to tests to code. Run this at the start of a session, immediately after a context compaction, and whenever you are spawned as a subagent with no prior context — before touching code, answering a question about the codebase, or picking up a task. If you are unsure whether you have been onboarded in this session, you have not; run it.
---

# Onboarding

## Before Start

Output exactly: 👋👋👋 STARTING MY ONBOARDING

## 0. Is dotdot ready?

Check whether `.dot/.tooling/conf/ready` exists, with a single `test -f` — the only file check this onboarding makes.

- **It exists:** the context is prepared. Go on.
- **It is missing:** dotdot is installed but not prepared yet: its context files are still templates (`ignore: true`), with nothing yet to guide your work. Before anything else, ask the user in one plain message:

  "👋 I see this project uses **dotdot** (in `.dot/`), but it isn't set up yet. Want to get it ready now? You tell me about the project and I'll turn it into its context — it only takes a minute."

  If they agree, or their message already asks for it ("I'm using dotdot", "set it up"), invoke the `dot-ready` skill, and finish this onboarding once it's done. If they decline, finish onboarding and keep in mind that files marked `ignore: true` hold placeholders, not facts; offer `dot-ready` again when the work needs context they would hold.

## 1. What this project is, and dotdot, which describes it

Your instructions are already loaded: the harness reads `AGENTS.md` at session start. The project's purpose, principles, and your working agreement are in that text — read purely from what is already loaded in your context window. Apart from the check in step 0, do not call Read, Grep, Glob, Bash, or any subagent, and do not re-open files from disk to understand this context.

Do not scan the repository to work out what the project is. Directory listings and file trees describe structure, not intent, and reconstructing intent from them is slow, unreliable, and against the rules. If the purpose genuinely isn't in your context, use the `dot-tool-scan-frontmatter` skill against `.dot/` to guide you.

Everything that governs your work lives in dotdot (`.dot/`). Its job is to make your work comply with this project's specifications. It holds:

- Context: one Markdown file per concern at the top of `.dot/`, plus `.dot/Decisions/` — information you need to understand the project and its constraints.
- Tools: `bash dot` — tools available to help you work faster, easier, and more reliable.
- Features: `.dot/Features/` — what each product feature is, exactly as specified; the source of truth for building it.
- Tasks: `.dot/Tasks/` work to be done and completed. These are optional for our work. If the dir doesn't exist or is empty, the user may not intend to use them.
- Notes: `.dot/Notes/` — personal notes for discussion and exploration; no commitments. These are optional for our work. If the dir doesn't exist or is empty, the user may not intend to use them.

Tasks and Notes are the user's to raise: open them only when the user's request is about them, never on your own initiative.

When working on a note or a task, answer inside it, not in the chat; the chat reply is only "✅ Done: <path or link>". This overrides the Reporting template in AGENTS.md.

## 2. The rules bind you

`.dot/RULES.md` is already in your context. It is not advisory and not a style preference: its **Never**, **Always**, and **Ask First** lists are the difference between work that ships and work that gets reverted. Reread them now, and treat anything in Ask First as a genuine stop — asking costs one message, guessing wrong costs the user's trust.

## 3. Where the rest of the context lives

`.dot/` holds one Markdown file per concern, named for what it covers:

Read them on demand, not upfront — pulling all of them in wastes the context you need for the actual work. Each declares a `description` in its frontmatter saying exactly when it's the right file to open, so survey a directory with the `dot-tool-scan-frontmatter` skill and read in full only what the task calls for. `Decisions/` and `Features/` are directories worth surveying that way before you assume something is undocumented.

## 4. You have tools and skills — use them

- **Skills** — your agentic skills and workflow skills. Discover them and invoke them when you need them.
- `bash dot` — dotdot's commands, artisan style. `bash dot` lists them; every one answers `--help` with what it does and when to reach for it. Check for one before writing your own grep, scan, or one-off script. The most useful ones are discoverable as part of your agentic skills.
- **Kits** — `bash dot kit:list` shows the installed ones. Their commands run as `bash dot <kit>:<command>`, their skills and agents are prefixed `<kit>-`, and their context sits in the top-level docs, between `<!-- <kit>/<File> -->` markers or in `<File>-<kit>.md`.

The tools encode exclusions, paths, and conventions you would otherwise have to rediscover, wrongly, every session. Run custom commands only when these tools genuinely don't cover your needs.

## 5. How work flows here

Feature → plan → tests → code, in that order, each stage written down before the next begins:

1. `dot-document-feature` — the idea becomes `.dot/Features/fNNN--<slug>.md`: specification in Given/When/Then, constraints, decisions.
2. `dot-draft-feature-plan` — a concrete implementation plan written into that same file, grounded in the Context docs.
3. `dot-write-tests` — tests derived from the specification, written and failing **before** any implementation exists.
4. `dot-implement-feature` — code written against those failing tests, one at a time, in the codebase's existing conventions.

`dot-build-full-feature` chains all four and enters wherever the work actually is. The order is the point: the specification is what the tests are derived from, and the failing tests are what tells you the implementation is done. Skipping ahead to code means writing tests that describe what you built rather than what was asked for.

Before calling anything done: ensure you cover the Definition of Done for each feature. It's an **Always** rule, so neither is optional.

## Finishing

State in one or two sentences what this project is and what you understand the task to be. Confirm you've read the rules. Then continue with the user's request. If nothing was asked yet, say you're ready and stop.

Then output exactly: 🤘🤘🤘 FINISHED MY ONBOARDING!
