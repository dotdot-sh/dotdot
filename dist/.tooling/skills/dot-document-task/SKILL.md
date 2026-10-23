---
name: dot-document-task
description: Turns a description of a piece of work into a documented task, following the bundled task template, and creates it with bash dot task:create in whichever service the project uses (plain files or GitHub issues). Use whenever the user wants something tracked as a task — "add a task for X", "make that a task", "track this", "put it on the list", "we need to do Y later" — or asks to break a feature or note into tasks. Documents only; never starts the work.
---

# Document a Task

## Goal
Given a description of work, in any level of detail, create one complete task that follows `task-template.md` (bundled with this skill), without making the user write it.

**This skill documents the task. It does not do the work.** Stop once the task is created and confirmed.

## Before Start

Inform the user of your invocation of this skill by outputting exactly: 📌📌📌 BEGIN DOCUMENTING TASK

## Process
1. **Confirm intent.** Unless the user asked for a task (or named this skill), ask whether they want this tracked as a task. If not, stop.
2. **Duplicate check.** Run `bash dot task:list --status todo,doing,paused`. If an open task already covers it, show it with `bash dot task:show <id>` and ask whether to update that one instead (`bash dot task:update <id> --<section> "..."`) or create a new one.
3. **Gather context.** Use the context already in your window. For related records, survey with `bash dot scan:frontmatter .dot/Features/` (and `Decisions/`, `Notes/`) rather than reading files.
4. **Draft** the title and every template section from the request and that context. Ask only what you can't reasonably infer, in **one** Interview Tool round (e.g. Claude Code's `AskUserQuestion`), proposing your best guess in each question. Usually nothing needs asking.
5. **Create** it with `bash dot task:create --title "..." --<section> "..."` (run `bash dot task:create --help` for the template-derived flags). Never write a task file or call the service yourself.
6. **Confirm.** Run `bash dot task:show <id>` rather than pasting it, then report per the Reporting template in `AGENTS.md`: ✅ the task id, and ask whether it is right.

## Template
The task's shape lives in `task-template.md`, in this skill's directory; `bash dot task:create` builds the body from it.

- **Title:** one short imperative sentence ("Throttle failed logins on the login route"), never a topic.
- **Done When:** checkable outcomes as a `- [ ]` list, not steps.
- **Related sections:** filenames or project paths only, one per line, no descriptions.
- **Empty sections:** exactly `None` (the default when a flag is left out). Never pad them with prose.
- **Status:** new tasks start as `todo`. Pass `--status` only when the user says the work is already under way.

## Finishing

Your very last step is to respond with exactly: ✅✅✅ DONE DOCUMENTING TASK

Then stop. Do not start the task.
