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

What gets linked where is yours to decide in `.dot/sync.map` (`origin::destination` per line): by default `AGENTS.md` into the project root and each of dotdot's skills into `.claude/skills/`, one line each, plus a block every plugin adds. A harness plugin wires it into a coding agent, linking every skill and agent into the harness's directories and the docs where the harness reads them:

- [x] Claude Code — `bash dot plugins:add dotdot-sh/claude-code` (source in this repo's `plugins/claude-code/`)
- [ ] OpenCode
- [ ] Codex
- [ ] Copilot
- [ ] Cursor

## `dot` command

The `dot` at your project root is dotdot's handy command line. It gives you and your agents a straightforward way to manage common dotdot actions such as creating notes, features, decisions, and tasks, scanning docs, managing plugins, and syncing or updating dotdot itself. Run `bash dot` to list the available commands, and pass `--help` to each to learn more about their usage.

> **Tip:** To run the command simply as `dot` instead of `bash dot`, consider adding `dot() { bash dot "$@"; }` to your shell.

Examples:
```sh
dot sync                               # link what .dot/sync.map lists into your harness, after adding or renaming skills
dot notes:create --slug "Cache idea"   # a new note in .dot/Notes/
dot tasks:list                         # the project's tasks
```

## Plugins

dotdot ships with what it needs: notes, feature specifications, decisions, tasks, releases, and Claude Code settings are all part of its core. A plugin adds more, from any GitHub repo you choose: there is no catalog, and nobody vets plugins for you.

```sh
bash dot plugins:add acme/laravel           # github.com/acme/laravel, its dotdot/ folder
bash dot plugins:add acme/svelte@v1.0.0     # at a branch, tag, or commit
bash dot plugins:update                     # every installed plugin, each reviewed again
bash dot plugins:remove acme/laravel
```

A plugin is code and instructions from its author. It can run anything on your machine and steer your agents, so every add and update shows a warning and the full list of what changes (scripts flagged), and goes ahead only when you confirm at a terminal; `--yes` skips the question but still needs a terminal, so no agent or script can add or update a plugin. dotdot never runs plugin code while adding it.

Only the repo's `dotdot/` folder is installed, into `.dot/.plugins/<owner>/<name>/`. Its commands run as `bash dot <owner>:<command>`; a plugin whose owner is one of dotdot's own command names, or whose commands another plugin already has, is refused, its skills and agents must be named `<name>-…`, and nothing it links may clash with what dotdot or an earlier plugin links. Its context goes into dotdot's top-level docs: into the doc with the same name, between `<!-- <owner>/<name>/<File> -->` markers, or else as a new `<File>-<owner>-<name>.md` (map it elsewhere with `.dot/.plugins/pluginsmap.conf` lines such as `acme/laravel/GUIDELINES.md:STANDARDS.md`). Removing a plugin removes its context regions and the docs it created; the records, seeded files, and plugin data it leaves are listed for you to review.

### GitHub identity

Plugins and the tasks kept as GitHub issues use your `gh` login by default. To run them as another account for this project only, such as a team bot, put a token in dotdot's git-ignored `.dot/.env` as `GH_TOKEN`.

dotdot hands it to every `gh` call it makes, and to its direct GitHub downloads, so they act as the token's owner whatever account `gh auth` is logged in as; your own shell's `gh` is unaffected. The token's scopes limit what dotdot can do (private downloads and issues need repository access, creating labels needs write access). It covers github.com only.

### Writing a plugin

`bash dot plugins:new <owner>/<name>` scaffolds a repo. Everything dotdot installs lives in its `dotdot/` folder; the rest of the repo is yours:

- `dotdot/plugin.conf` — `REQUIRES` (the plugin API), `DESCRIPTION`, `DEPENDS` (binaries or `framework.integrations.<name>`, reported but never installed), `DIRECTORIES` (records directories it keeps, such as `Recipes`), and for a harness plugin `HARNESS_SKILLS` / `HARNESS_AGENTS` (where every dotdot and plugin skill and agent is linked, such as `.claude/skills`) and `LINKS` (`<origin>::<destination>` pairs, comma-separated: a path in the plugin, or `@<Doc>.md` for one of dotdot's top-level docs, linked to a project path outside `.dot/` and `.git/`).
- `dotdot/commands/*.sh` — commands, run as `bash dot <owner>:<command>` (`commands/db/seed.sh` is `<owner>:db:seed`).
- `dotdot/context/*.md` — merged into dotdot's docs as described above.
- `dotdot/skills/`, `dotdot/agents/` — each entry named `<name>-…`, linked by `bash dot sync` into every harness directory a harness plugin declares.
- `dotdot/stubs/<path>.stub` — seeds `<path>` in the project when missing; `stubs/env.stub` declares the plugin's settings and adds the ones `.dot/.env` lacks. Every setting a plugin declares, reads, or saves is named `<OWNER>__<NAME>__…` (`ACME__WIDGETS__API_KEY` for `acme/widgets`), so it can't touch dotdot's or another plugin's.
- Anything else, organized as you like, loaded with `dot::use plugins.<owner>.<name>.<path>`.

Try it locally with `bash dot plugins:add <owner>/<name> --from ./<repo-directory>`, then publish it as `github.com/<owner>/<name>`.

A command declares a `DESCRIPTION`, a `usage` function for its `--help`, and a `handle` function that receives the arguments:

```bash
#!/usr/bin/env bash

DESCRIPTION="Seed the database."

dot::use framework.console.args framework.console.output

usage() {
  framework.console.output::line "bash dot $DOT_COMMAND [--fresh]"
}

handle() {
  [ $# -le 1 ] || framework.console.args::unexpected "$2"
  framework.console.output::success "Seeded."
}
```

Plugin code may use, and only use:

- `dot::use`, `dot::path project|dotdot|plugin`, `dot::config` (a setting from `.dot/.env`; unset stops with how to set it), `dot::optional_config` (the same, or nothing), `dot::save_config`, `dot::relative`, `dot::call`, `dot::raise`, `dot::abort`, `dot::on_exit`.
- `framework.helpers.*` — `fs`, `text`, `kv`, `date`, `frontmatter`, `template`, `record`, `json`, `net`, `emoji`.
- `framework.console.*` — `output`, `prompt`, `terminal`, `args`.
- `framework.integrations.<name>.service` — `github-api`, `github-cli`.
- its own `plugins.<owner>.<name>.*`.

`dot::use` refuses anything else (dotdot's `core.*` modules, any `internal` part of a framework module, another plugin), and every function is named after its module: `framework.console.output::success`, `plugins.acme.laravel.db::seed`.

## Structure

- `.dot/*.md` and `.dot/Features/`, `Decisions/`, `Tasks/`, `Notes/` — the project's context and records, owned by the project.
- `.dot/sync.map` — every link `bash dot sync` makes, created from dotdot's default at install; a block per plugin, written from its `plugin.conf` when added and dropped when removed. Edit it freely; `bash dot sync --refresh <owner>/<name>` rewrites a plugin's block.
- `.dot/.core/` — dotdot itself, refreshed by `bash dot update`:
  - `system/` — what dotdot needs to run: `bin/dot`, `boot.sh` (module loading and the `dot::` API, the only API plugins may use), `kernel.sh` (the command registry, listing, and dispatch), `paths.sh`, and `plugins`, `sync`, `update`, loaded as `core.system.<part>.*`.
  - `modules/` — what dotdot can do: `onboarding`, `ready`, `frontmatter`, `housekeeping`, `notes`, `features`, `decisions`, `tasks`, `release`, each with its commands and skills, loaded as `core.modules.<module>.*`.
  - `framework/` — the only shared code, loaded as `framework.*` by the system, the modules, and plugins alike: `helpers/` (project-agnostic building blocks), `console/` (command-line input and output), and `integrations/` (external services, each exposing only `service.sh`; its `internal/` parts load only from inside that integration).
  - `.env.example` (dotdot's settings with their defaults, which the installer starts `.dot/.env` from; never read at run time), `version` (the commit installed), and `dotdot_ready` (set once the context is prepared); `bash dot update` keeps the last two.
  - Every system part and module loads only from inside its own folder.
- `.dot/.plugins/<owner>/<name>/` — installed plugins, with `plugins.lock`. A plugin writes nothing outside its folder but its stubs, its settings in `.dot/.env`, and the project records it declares (`DIRECTORIES`).

Everything runs on bash 3.2+ with standard Unix tools (macOS included).

## Agents Brevity Flags

Agents are instructed to reply concisely by settings, however, you can also add a flag to your prompt to adjust its output mode for that specific reply:

- `--short` / `--s`: the concise answers.
- `--expand` / `--xp`: a little more detail than usual, while the default remains unchanged.
