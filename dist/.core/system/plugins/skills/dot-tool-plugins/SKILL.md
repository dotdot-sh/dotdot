---
name: dot-tool-plugins
description: Lists installed plugins with bash dot plugins:list, and explains plugins:add, plugins:update, plugins:remove, and plugins:new. A plugin is a GitHub repo (<owner>/<name>) whose dotdot/ folder brings commands (bash dot <owner>:<command>), skills, and context. Use it whenever the user asks which plugins are installed, wants to add, update, remove, or write one. Plugins are unvetted code the user must trust, and adding, updating, and removing need a person at a terminal, so you only list and explain: never add, update, or remove a plugin yourself; tell the user the exact command to run.
metadata:
  internal: true
---

## Usage
```sh
bash dot plugins:list
bash dot plugins:add --help
bash dot plugins:update --help
bash dot plugins:remove --help
bash dot plugins:new --help
```

- A harness plugin wires dotdot into a coding agent: it links every skill, agent, and core doc where that agent reads them. Without one, only `AGENTS.md` is linked. For Claude Code it is `dotdot-sh/claude-code`.
