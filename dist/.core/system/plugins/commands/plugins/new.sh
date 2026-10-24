#!/usr/bin/env bash

DESCRIPTION="Scaffold a new plugin repo, ready to fill and publish."

dot::use framework.console.args framework.console.output core.system.plugins.console core.system.plugins.manifest core.system.plugins.service framework.helpers.fs

usage() {
  cat <<USAGE
bash dot plugins:new — scaffold a plugin repo for <owner>/<name>, with one
example of each part to replace with your own. Everything dotdot installs
lives in the repo's $PLUGIN_ROOT/ folder; the rest of the repo is yours.

  $PLUGIN_ROOT/$PLUGIN_MANIFEST   REQUIRES (the plugin API, $PLUGIN_API), DESCRIPTION, DEPENDS
                    (binaries or framework.integrations.<name>, reported only),
                    DIRECTORIES (top-level dotdot directories it keeps records in);
                    a harness plugin adds HARNESS_SKILLS / HARNESS_AGENTS (where
                    every skill and agent is linked) and LINKS (<origin>::<destination>,
                    a plugin path or @<Doc>.md, into the project outside $DOTDOT_NAME/ and .git/)
  $PLUGIN_ROOT/commands/    commands, run as bash dot <owner>:<command>; each declares
                    DESCRIPTION, usage(), and handle()
  $PLUGIN_ROOT/context/     merged into dotdot's top-level docs
  $PLUGIN_ROOT/skills/, agents/, claude/hooks/
                    each entry named <name>-..., linked into the harness by bash dot sync
  $PLUGIN_ROOT/stubs/       *.stub files seed the project; env.stub declares its settings,
                    named <OWNER>__<NAME>__..., and adds the ones .env lacks
  anything else     your code, loaded as plugins.<owner>.<name>.<path>

Code may load dotdot's framework.helpers.*, framework.console.*, and framework.integrations.<name>.service,
plus its own files; nothing else.

Usage:
  bash dot plugins:new <owner>/<name> [--path <directory>]
  bash dot plugins:new --help

The repo goes into <directory> (default: <name> in the project root), which
must not exist yet. Try it with bash dot plugins:add <owner>/<name> --from
./<directory>, then publish it as github.com/<owner>/<name>.
USAGE
}

handle() {
  local plugin="" path="" target
  while [ $# -gt 0 ]; do
    case "$1" in
      --path) framework.console.args::require_value "$@"; path="$2"; shift 2 ;;
      -*) framework.console.args::unexpected "$1" ;;
      *) [ -z "$plugin" ] || framework.console.args::unexpected "$1"; plugin="$1"; shift ;;
    esac
  done
  [ -n "$plugin" ] || framework.console.args::invalid "A plugin is required, as <owner>/<name>."
  plugin=$(core.system.plugins.console::plugin "$plugin")
  target=$(framework.helpers.fs::within "${path:-${plugin#*/}}" "$BASE") || framework.console.output::fail "The plugin must be created inside the project."
  [ ! -e "$target" ] || framework.console.output::fail "$(dot::relative "$target") already exists."
  core.system.plugins.service::scaffold "$plugin" "$target" || framework.console.output::fail "Could not create the plugin in $(dot::relative "$target")."
  framework.console.output::success "Plugin $plugin scaffolded"
  framework.console.output::detail "$(dot::relative "$target")"
}
