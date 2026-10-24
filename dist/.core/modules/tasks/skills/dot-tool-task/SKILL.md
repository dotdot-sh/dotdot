---
name: dot-tool-task
description: Lists, shows, creates, updates, and moves the project's tasks with the bash dot tasks:* commands (tasks:list, tasks:show, tasks:create, tasks:update, tasks:doing, tasks:done, ...) — the same whichever service holds them: plain files in .dot/Tasks/ or GitHub issues. Use it whenever work is tracked as tasks — "what's on the list", "what am I doing", "start t004", "mark it done", "pause that", "drop that task", "add the rate limit to its checklist". Reach for it rather than editing task files or calling gh directly, which skips the status rules and the updated timestamp. To write a new task from a description, use dot-create-task.
metadata:
  internal: true
---

## Usage
```sh
bash dot tasks:list --help
bash dot tasks:show --help
bash dot tasks:create --help
bash dot tasks:update --help
```

- Statuses are `todo`, `doing`, `paused`, `done`, `discarded`; move one with `bash dot tasks:<status> <id>` (e.g. `tasks:doing t004`), or with `--<status>` on `tasks:update` alongside other changes. Read a task with `bash dot tasks:show <id>`; without a terminal it prints.
- Ids are whatever the list shows (`t004`, `#12`).
- Working on a task the user hands you: move it to `doing` when you start, record progress and answers in it with `bash dot tasks:update <id> --<section> "..."` (ticking its `Done When` items), and move it to `done` once every item is checked.
- If tasks are not set up yet, or a task must be deleted, the command says so: both need the user at a terminal (`bash dot tasks:initialize`, `bash dot tasks:delete <id>`). Ask them; never work around it.
