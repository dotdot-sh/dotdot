---
name: dot-ready
description: Gets dotdot ready for this project — turns what the user tells you about the project, its tech, the company, and their rules into the context files at the top of .dot/. Use it when the user says they're using dotdot or just installed it, asks to set up, prepare, fill, or refine the project's context (or one file of it, e.g. "let's write PRODUCT.md"), or agrees to prepare it when onboarding finds dotdot not ready (.dot/.tooling/conf/ready missing). If that file exists, the context was prepared before: offer to refine it instead.
---

# Get dotdot ready

## Goal
Short, accurate, project-specific context files, derived from the user talking freely — not from a questionnaire, and not from them writing the files.

## Before Start
Output exactly: 🧭🧭🧭 GETTING DOTDOT READY

## Scope
The Markdown files at the top of `.dot/`. Survey them with the `dot-tool-scan-frontmatter` skill: `ignore: true` marks a file still to fill. Read a file in full only once something goes into it.

- `RULES.md`, `SECURITY.md`, and `STANDARDS.md` ship with defaults: keep them, only extend them and replace placeholders.
- `USER.md` holds the user's personal preferences: fill it only with what they say about how they like to work.
- Out of scope: `AGENTS.md`, `SCHEMA.md` (generated), and kit regions (between `<!-- <kit>/<File> -->` markers).

## 1. Invite
One friendly plain chat message, not the Interview Tool, then wait for the answer. If `.dot/.tooling/conf/ready` exists, say the context was prepared before and ask what they'd like to add or change. Otherwise, invite them to talk, for example:

"Tell me about your project: what it is and who it's for, the tech it's built with, the company behind it, how you like to work, and any rules I must always follow. Write as much or as little as you like, in any order — pasting existing docs works too."

If the user named one file, ask about that file's topics only.

## 2. Derive
Sorting is your job, not theirs: place each piece of what they shared into the section it belongs to, in whichever file.

- `COMPANY.md`, `PRODUCT.md`, `DESIGN.md`: one to three short declarative sentences per section, no bullets, no marketing language.
- Every other file: short bullets, one fact or rule each.
- Never invent. A section nothing fits keeps its placeholder; a topic no section fits gets a new section.
- Replace a section's italic `_..._` prompt with the real content; leave sections already written alone, unless the user asked to change them.
- Remove `ignore: true` from a file once its main sections hold real content.

The Interview Tool stays available whenever a choice is genuinely clearer as options — e.g. two statements that conflict — never as a survey.

Then create `.dot/.tooling/conf/ready`.

## 3. Report
Tell the user, in the Reporting template of `AGENTS.md`, that the context is ready based on what they shared:

- ✅ The files prepared.
- ⚠️ Only the gaps that would weaken the work — a file still empty, or a section too thin to guide decisions (e.g. no tech stack, no audience for the product) — each with what would make it sound. Don't list every empty section, and don't ask questions for their own sake; they can add more anytime by just telling you.
- 🌀 When no kit is installed, the kits `bash dot kit:list` offers, to add with `bash dot kit:add <name>`.

## Finishing
Output exactly: ✅✅✅ DOTDOT IS READY

Then stop: don't touch any other file, nor code anything. If onboarding invoked you, it picks up from here.
