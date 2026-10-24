#!/usr/bin/env bash

dot::use framework.console.output framework.console.prompt core.system.plugins.context core.system.plugins.manifest core.system.plugins.service

core.system.plugins.console::plugin() {
  core.system.plugins.manifest::id "$1" || framework.console.output::fail "Give the plugin as <owner>/<name> (letters, digits, and -): $1"
}

core.system.plugins.console::fetch() {
  local plugin="$1" ref="$2" path="${3-}"
  framework.console.output::line "Fetching $plugin${path:+ from $path}${ref:+@$ref}…"
  core.system.plugins.service::fetch "$plugin" "$ref" "$path" || exit 1
}

core.system.plugins.console::warn() {
  framework.console.output::warn "A plugin is code and instructions from $1's author, not from dotdot. It can run anything on this machine and steer your agents."
  framework.console.output::detail "dotdot never runs plugin code while adding it, but its commands, hooks, and skills will run later."
  framework.console.output::detail "Read everything below, and only continue if you trust the source."
}

core.system.plugins.console::preview() {
  local plugin="$1" source="$2" rows kind first second third
  rows=$(core.system.plugins.service::preview "$plugin" "$source") || exit 1
  framework.console.output::line "Context:"
  while IFS=$'\t' read -r kind first second third; do
    [ "$kind" = context ] && framework.console.output::item "$first → $second" "$third"
  done <<< "$rows"
  framework.console.output::line "Files → $(dot::relative "$(core.system.plugins.manifest::directory "$plugin")")/:"
  while IFS=$'\t' read -r kind first second third; do
    [ "$kind" = file ] || continue
    case "$first" in
      *.sh) framework.console.output::item "$OUTPUT_WARNING_ICON $first" "$second; script: runs on your machine" yellow ;;
      *) framework.console.output::item "$first" "$second" ;;
    esac
  done <<< "$rows"
  while IFS=$'\t' read -r kind first second third; do
    case "$kind" in
      stub)
        if [ "$first" = "$PLUGIN_ENV_STUB" ]; then
          framework.console.output::item "stubs/$first" "adds its settings missing from $(dot::relative "$ENV_FILE")"
        else
          framework.console.output::item "stubs/$first" "seeds the project unless the file exists"
        fi
        ;;
      harness) framework.console.output::item "$first → $second/" "every dotdot and plugin skill or agent is linked there" ;;
      link) framework.console.output::item "$first → $second" "link" ;;
      missing) framework.console.output::warn "$plugin depends on $first, which is not available here; install it yourself." ;;
    esac
  done <<< "$rows"
}

core.system.plugins.console::confirm() {
  local question="$1" confirmed="$2" command="$3"
  framework.console.prompt::can_ask || framework.console.output::fail "Plugins are added and updated only by a person at a terminal; ask the user to run $command."
  if $confirmed; then
    framework.console.output::line "$question yes (--yes)"
    return 0
  fi
  framework.console.prompt::confirm "$question" || { framework.console.output::aborted; return 1; }
}

core.system.plugins.console::report() {
  local verb path
  while IFS=$'\t' read -r verb path; do
    case "$verb" in
      left | kept) framework.console.output::item "$path" "$verb; review and remove it yourself if unused" yellow ;;
      *) framework.console.output::item "$path" "$verb" green ;;
    esac
  done
}

core.system.plugins.console::placed() {
  local file path state
  while IFS=$'\t' read -r file path state; do
    framework.console.output::item "$file → $path" "$state" green
  done
}

core.system.plugins.console::removed() {
  local path
  while IFS= read -r path; do
    framework.console.output::item "removed $path"
  done
}

core.system.plugins.console::install() {
  local plugin="$1" source="$2"
  core.system.plugins.context::place_all "$plugin" "$source" "$PLUGINS_WORKSPACE" | core.system.plugins.console::placed
  core.system.plugins.service::install "$plugin" "$source"
  core.system.plugins.service::seed "$(core.system.plugins.manifest::directory "$plugin")" | core.system.plugins.console::report
  core.system.plugins.manifest::lock "$plugin" "$PLUGIN_ORIGIN $PLUGIN_REF ${PLUGIN_COMMIT:-$PLUGIN_UNKNOWN_COMMIT}"
}

core.system.plugins.console::sync() {
  dot::call sync -y "$@"
}
