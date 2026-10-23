---
name: dot-tool-kit
description: Lists, adds, updates, and removes kits (laravel, svelte, …) with bash dot kit:list, kit:add, kit:update, and kit:remove. A kit brings a stack's or tool's context (merged into dotdot's top-level docs), skills, agents, and <kit>:<command> commands. Use it whenever the user asks which stacks are available or installed, wants a stack's conventions or tools, or says "add laravel", "update the stacks", "remove svelte". Adding, updating, and removing need a [y/N] at a real terminal, so you can only list and preview: run the command to show what would change, then ask the user to run it themselves.
---

## Usage
```sh
bash dot kit:list
bash dot kit:add --help
bash dot kit:update --help
bash dot kit:remove --help
```
