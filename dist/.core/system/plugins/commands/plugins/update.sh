#!/usr/bin/env bash

DESCRIPTION="Update installed plugins from where they were added, after a review."

dot::use framework.console.args framework.console.output core.system.plugins.console core.system.plugins.context core.system.plugins.manifest

usage() {
  cat <<USAGE
bash dot plugins:update — update a plugin, or every installed one, from the
repo and ref it was added from (or its local --from directory).

An update brings new code from the plugin's author, so it gets the same
warning and review as plugins:add: changed, added, and removed files are
listed, scripts flagged, and nothing changes until you confirm at a terminal.
-y / --yes skips the question but still needs a terminal.

Context regions are replaced where they stand, new context files placed,
dropped ones removed, and files replaced. Stubs never overwrite.

Usage:
  bash dot plugins:update [<owner>/<name>] [--yes]
  bash dot plugins:update --help
USAGE
}

update_plugin() {
  local plugin="$1" confirmed="$2" entry origin ref commit places=() place
  entry=$(core.system.plugins.manifest::lock_entry "$plugin") || framework.console.output::fail "$plugin is not installed."
  read -r origin ref commit <<< "$entry"
  case "$origin" in
    "$PLUGIN_PATH_SOURCE"*) core.system.plugins.console::fetch "$plugin" "" "${origin#"$PLUGIN_PATH_SOURCE"}" ;;
    *) core.system.plugins.console::fetch "$plugin" "$ref" ;;
  esac
  core.system.plugins.manifest::validate "$PLUGIN_SOURCE" "$plugin" || exit 1
  if [ "$PLUGIN_COMMIT" != "$PLUGIN_LOCAL_REF" ] && [ -n "$PLUGIN_COMMIT" ] && [ "$PLUGIN_COMMIT" = "$commit" ]; then
    framework.console.output::success "$plugin is up to date (${commit:0:7})."
    return 0
  fi
  core.system.plugins.console::warn "$plugin"
  framework.console.output::line "Plugin $plugin: ${commit:0:7} → ${PLUGIN_COMMIT:0:7}"
  core.system.plugins.console::preview "$plugin" "$PLUGIN_SOURCE"
  core.system.plugins.console::confirm "Update $plugin?" "$confirmed" "bash dot plugins:update $plugin" || return 0
  while IFS= read -r place; do
    places+=("$place")
  done < <(core.system.plugins.context::places "$plugin" "$PLUGIN_SOURCE")
  core.system.plugins.console::install "$plugin" "$PLUGIN_SOURCE"
  core.system.plugins.context::strip "$plugin" ${places[@]+"${places[@]}"} | core.system.plugins.console::removed
  framework.console.output::success "Updated $plugin."
  PLUGINS_UPDATED=true
  PLUGINS_REFRESH+=(--refresh "$plugin")
}

handle() {
  local plugin confirmed=false selected=()
  while [ $# -gt 0 ]; do
    case "$1" in
      -y | --yes) confirmed=true ;;
      -*) framework.console.args::unexpected "$1" ;;
      *) selected+=("$(core.system.plugins.console::plugin "$1")") ;;
    esac
    shift
  done
  [ ${#selected[@]} -le 1 ] || framework.console.args::unexpected "${selected[1]}"
  PLUGINS_UPDATED=false
  PLUGINS_REFRESH=()
  if [ ${#selected[@]} -eq 0 ]; then
    while IFS= read -r plugin; do
      selected+=("$plugin")
    done < <(core.system.plugins.manifest::installed)
  fi
  if [ ${#selected[@]} -eq 0 ]; then
    framework.console.output::line "No plugins installed."
    return 0
  fi
  for plugin in "${selected[@]}"; do
    update_plugin "$plugin" "$confirmed"
  done
  $PLUGINS_UPDATED || return 0
  core.system.plugins.console::sync "${PLUGINS_REFRESH[@]}"
  framework.console.output::line "Review the changes with git diff."
}
