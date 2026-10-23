# dotdot

A model-agnostic distro for AI coding agents.

## Installation

1. From your project's root, run `curl -fsSL https://raw.githubusercontent.com/dotdot-sh/dotdot/main/install.sh | bash`

2. Tell your coding agent you're using dotdot: it will ask about your project and prepare dotdot's context from your answers (the `dot-ready` skill).

3. Start building!

The installer will create the `.dot/` directory and the handy `dot` command at your project root. Then it'll sync the context with your harness.

## Objective

Define instructions, tools, and rules that help AI coding agents work in compliance with project requirements, organization policies, and personal user preferences.

## Core Principles

1. **Simplicity** — prefer the smallest set of instructions that achieves the goal.
2. **Reliability** — instructions must produce consistent agent behavior across sessions and models.
3. **Efficiency** — minimize the instructions, context, and steps an agent needs to do the right thing.

## Taxonomy

dotdot covers 3 categories that cover the basic elements of AI coding agent work:

- **Context**: The information the agent needs to understand the project, its goals, and its constraints (desitions, standards, rules, …).
- **Tools**: The tools available to help the agent work faster, more effectively, and reliably (skills, binaries, harness settings, …).
- **Work**: The specifications and operational artifacts that guide how the agent should work (ideas, feature specifications, plans, …).

Each category is present as contextual, instructional, and tooling artifacts: MD files, scripts, skills, specifications, plans, and templates.

## Rules

**dotdot is not a harness**, so it does not define or enforce a rules hierarchy on its own. It assumes you, your team, or your organization provisions a set of hierarchical shared instructions, and that dotdot's material lives beneath whatever rules your organization defines.

Since not all harnesses enforce rule hierarchies and contributors can edit dotdot locally, its content can fully drive agent behavior in practice. As a safeguard, dotdot directs agents to flag rule conflicts to the user rather than resolve them silently.

The list below is a recommended way to think about rules precedence, not one dotdot enforces. In order of precedence:

1. **Organization Policies**: Configurations and instructions defined by your organization and provisioned in your local system. Ideally read-only by you, fully enforced with top precedence by your agent.
2. **Project Guidelines** (dotdot): All information necessary to understand and work productively in the given project. Ideally agreed and committed by the team in the project repository.
3. **User Preferences**: Your individual user preferences for your local agents within this project. Ideally not tracked by your SCM tool and defined in the .dot/USER.md file.

## Delivery Model

dotdot is an opinionated starting point, not a long-term dependency. A one-time init step copies the `.dot/` directory into the parent project and symlinks dotdot sources into harness-specific instruction files (e.g. `CLAUDE.md`, `AGENTS.md`, `.claude/*`). From that point on, the project fully owns the result, and you're free to edit, extend, or remove any of it. It is recommended to track dotdot in your SCM.

## Supported Settings

Although the core content is harness-agnostic, dotdot includes configurations for these platforms:

- [x] Claude Code
- [ ] OpenCode
- [ ] Codex
- [ ] Copilot
- [ ] Cursor

## `dot` command

The `dot` at your project root is dotdot's handy command line. It gives you and your agents a straightforward way to manage common dotdot actions such as creating tasks, notes and decisions, scans docs, finds code references, and syncs or updates dotdot itself. Run `bash dot` to list the available commands, and pass `--help` to each to learn more about their usage.

> **Tip:** To run the command simply as `dot` instead of `bash dot`, consider adding `dot() { bash dot "$@"; }` to your shell.

Examples:
```sh
dot sync                       # relink dotdot into your harness after adding or renaming skills
dot note --slug "Cache idea"   # creates a new note in .dot/Notes/ to explore your idea
dot task:list                  # list the project's tasks tracked in your configured provider
```

## Kits

dotdot's core is stack-agnostic. A kit adds the context, skills, agents, and commands of one stack or tool (Laravel, Svelte, an SDK). Kits live in their own GitHub repos, public or private (with `gh` logged in or `GH_TOKEN` in `.dot/.env`), and are listed in the [dotdot-kits](https://github.com/dotdot-sh/dotdot-kits) registry.

```sh
bash dot kit:add laravel                      # from the registry
bash dot kit:add https://github.com/acme/dotdot-kit-svelte@v1.0.0
bash dot kit:update                           # every installed kit
```

A kit's context goes into dotdot's top-level docs: into the doc with the same name, between `<!-- <kit>/<File> -->` markers, or else as a new `<File>-<kit>.md`. Map it elsewhere with `.dot/.tooling/conf/kitsmap.conf` lines such as `laravel/GUIDELINES.md:STANDARDS.md`. Its commands run as `bash dot <kit>:<command>`. Updates and removals just apply; review them with `git diff`.

## Agents Brevity Flags

Agents are instructed to reply concisely by settings, however, you can also add a flag to your prompt to adjust its output mode for that specific reply:

- `--short` / `--s`: the concise answers.
- `--expand` / `--xp`: a little more detail than usual, while the default remains unchanged.
