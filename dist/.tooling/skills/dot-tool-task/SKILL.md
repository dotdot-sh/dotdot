---
name: dot-tool-task
description: Lists, shows, creates, updates, and moves the project's tasks with the bash dot task:* commands (task:list, task:show, task:create, task:update, task:doing, task:done, ...) — the same whichever service holds them: plain files in .dot/Tasks/ or GitHub issues. Use it whenever work is tracked as tasks — "what's on the list", "what am I doing", "start t004", "mark it done", "pause that", "drop that task", "add the rate limit to its checklist". Reach for it rather than editing task files or calling gh directly, which skips the status rules and the updated timestamp. To write a new task from a description, use dot-document-task.
---

## Usage
```sh
bash dot task:list --help
bash dot task:show --help
bash dot task:create --help
bash dot task:update --help
```

- Statuses are `todo`, `doing`, `paused`, `done`, `discarded`; move one with `bash dot task:<status> <id>` (e.g. `task:doing t004`), or with `--<status>` on `task:update` alongside other changes. Read a task with `bash dot task:show <id>`; without a terminal it prints.
- Ids are whatever the list shows (`t004`, `#12`).
- If tasks are not set up yet, or a task must be deleted, the command says so: both need the user at a terminal (`bash dot task:initialize`, `bash dot task:delete <id>`). Ask them; never work around it.
