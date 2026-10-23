---
name: dot-tool-sync
description: Activates dotdot with bash dot sync — seeds USER.md if missing and symlinks dotdot's instruction sources into the locations the harnesses actually read them. Use it after installing dotdot or creating a worktree, and whenever something has been added, renamed, or removed under .dot/.tooling/skills/, .dot/.tooling/agents/, .dot/.tooling/claude/, or AGENTS.md — a new skill won't be visible to any agent until this runs. Every run previews its changes and needs a [y/N] answered at a real terminal, so you can only preview: run it to show what would change, then ask the user to run `bash dot sync` themselves (adding --override only if they want existing destinations replaced). Never pass -y: it approves the changes on the user's behalf and is reserved for the installer.
---

## Usage
```sh
bash dot sync --help
```
