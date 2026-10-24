#!/usr/bin/env bash

DESCRIPTION="Remove a plugin: its files, context regions, and lock entry; project records stay."

dot::use framework.console.args framework.console.output framework.console.prompt core.system.plugins.console core.system.plugins.context core.system.plugins.manifest core.system.plugins.service

usage() {
  cat <<USAGE
bash dot plugins:remove — remove a plugin: $(dot::relative "$PLUGINS_DIR")/<owner>/<name>/,
its regions in dotdot's docs (markers included), the docs it created, and its
lock entry; then sync prunes its links.

What the project owns stays: the directories the plugin created are removed
only when still empty, and the files its stubs seeded and its settings in
$(dot::relative "$ENV_FILE") are listed for you to review.

Needs a y on a terminal (piped input is refused).

Usage:
  bash dot plugins:remove <owner>/<name>
  bash dot plugins:remove --help
USAGE
}

handle() {
  local plugin
  [ $# -ge 1 ] || framework.console.args::invalid "A plugin is required, as <owner>/<name>."
  [ $# -eq 1 ] || framework.console.args::unexpected "$2"
  plugin=$(core.system.plugins.console::plugin "$1")
  core.system.plugins.manifest::lock_entry "$plugin" >/dev/null || framework.console.output::fail "$plugin is not installed."
  framework.console.prompt::confirm_or_exit "Remove $plugin?" n "bash dot plugins:remove $plugin"
  core.system.plugins.context::strip "$plugin" | core.system.plugins.console::removed
  core.system.plugins.service::uninstall "$plugin" | core.system.plugins.console::report
  core.system.plugins.manifest::unlock "$plugin"
  core.system.plugins.console::sync
  framework.console.output::success "Removed $plugin. Review the changes with git diff."
}
