#!/usr/bin/env bash

DESCRIPTION="Add a plugin from a GitHub repo you trust: its dotdot/ folder, its commands, skills, and context."

dot::use framework.console.args framework.console.output core.system.plugins.console core.system.plugins.manifest

usage() {
  cat <<USAGE
bash dot plugins:add — add a plugin from a GitHub repo, <owner>/<name>.

Only the repo's dotdot/ folder is installed, into
$(dot::relative "$PLUGINS_DIR")/<owner>/<name>/. Its commands run as
bash dot <owner>:<command>. It is refused when its owner is one of dotdot's
own command names, when another plugin has one of its commands, or when one of
its skills, agents, or hooks isn't named <name>-... or clashes with dotdot's or
another plugin's. Its code loads as plugins.<owner>.<name>.*.

Plugins are not vetted by anyone: you decide whom to trust. Everything the
plugin brings is previewed, scripts flagged, and nothing changes until you
confirm at a terminal. -y / --yes skips the question, but still needs a
terminal, so no agent or script can add a plugin.

The plugin's context/*.md is merged into dotdot's top-level docs (a region in
the doc of the same name, or a new <File>-<owner>-<name>.md;
$(dot::relative "$PLUGINS_MAP") lines "<owner>/<name>/<File>.md:<Dest>.md"
override it). Its stubs seed the project without overwriting anything, and
the directories it declares are created. Dependencies are reported, never
installed. Then bash dot sync writes its block into .dot/sync.map and links it.

Private repos need gh logged in, or GH_TOKEN in $(dot::relative "$ENV_FILE").

Usage:
  bash dot plugins:add <owner>/<name>[@ref] [--yes]
  bash dot plugins:add <owner>/<name> --from ./<repo-directory> [--yes]
  bash dot plugins:add --help

The ref (branch, tag, or commit) defaults to $PLUGIN_DEFAULT_REF. --from takes a
local checkout of the repo inside the project, for developing a plugin.

Examples:
  bash dot plugins:add acme/laravel
  bash dot plugins:add acme/svelte@v1.0.0
USAGE
}

handle() {
  local source="" path="" confirmed=false plugin ref=""
  while [ $# -gt 0 ]; do
    case "$1" in
      -y | --yes) confirmed=true; shift ;;
      --from) framework.console.args::require_value "$@"; path="$2"; shift 2 ;;
      -*) framework.console.args::unexpected "$1" ;;
      *) [ -z "$source" ] || framework.console.args::unexpected "$1"; source="$1"; shift ;;
    esac
  done
  [ -n "$source" ] || framework.console.args::invalid "A plugin is required, as <owner>/<name>."
  [ "${source%@*}" = "$source" ] || ref="${source##*@}"
  plugin=$(core.system.plugins.console::plugin "${source%@*}")
  ! core.system.plugins.manifest::lock_entry "$plugin" >/dev/null \
    || framework.console.output::fail "$plugin is already installed; use bash dot plugins:update $plugin."
  core.system.plugins.console::fetch "$plugin" "$ref" "$path"
  core.system.plugins.manifest::validate "$PLUGIN_SOURCE" "$plugin" || exit 1
  core.system.plugins.console::warn "$plugin"
  framework.console.output::line "Plugin $plugin ($PLUGIN_ORIGIN${PLUGIN_COMMIT:+ @ ${PLUGIN_COMMIT:0:7}}):"
  core.system.plugins.console::preview "$plugin" "$PLUGIN_SOURCE"
  core.system.plugins.console::confirm "Add $plugin?" "$confirmed" "bash dot plugins:add $source" || exit 1
  core.system.plugins.console::install "$plugin" "$PLUGIN_SOURCE"
  core.system.plugins.console::sync
  framework.console.output::success "Added $plugin. Review the changes with git diff."
}
