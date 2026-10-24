---
name: dot-tool-sync
description: Activates dotdot with bash dot sync — seeds USER.md if missing and symlinks what .dot/sync.map lists (the user's map of every link: AGENTS.md by default, plus a block per plugin, such as the harness plugin dotdot-sh/claude-code linking every skill, agent, and doc where its agent reads them). Never edit .dot/sync.map unless the user asks. Use it after installing dotdot or creating a worktree, and whenever a skill, agent, or harness file has been added, renamed, or removed in .dot/.core/system/*/skills/, .dot/.core/modules/*/skills/, .dot/.plugins/, or AGENTS.md — a new skill won't be visible to any agent until this runs. Every run previews its changes and needs a [y/N] answered at a real terminal, so you can only preview: run it to show what would change, then ask the user to run `bash dot sync` themselves (adding --override only if they want existing destinations replaced). Never pass -y: it approves the changes on the user's behalf and is reserved for the installer.
metadata:
  internal: true
---

## Usage
```sh
bash dot sync --help
```
