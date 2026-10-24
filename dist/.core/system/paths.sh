#!/usr/bin/env bash

BIN_DIR="$SYSTEM_DIR/bin"
DOT_BIN="$BIN_DIR/dot"
SYSTEM_PARTS=(plugins sync update)
CORE_MODULES=(onboarding ready frontmatter housekeeping notes features decisions tasks release)
MODULE_COMMANDS_DIR="commands"
KEEP_FILE=".gitkeep"

SYNC_MAP="$DOTDOT_ROOT/sync.map"
SYNC_MAP_STUB="$SYSTEM_DIR/sync/stubs/sync.map"
SYNC_MAP_SEPARATOR="::"

PLUGIN_MANIFEST="plugin.conf"
PLUGIN_LINKS_KEY="LINKS"
PLUGIN_HARNESS_SKILLS_KEY="HARNESS_SKILLS"
PLUGIN_HARNESS_AGENTS_KEY="HARNESS_AGENTS"

ENV_FILE="$DOTDOT_ROOT/.env"
VERSION_FILE="$CORE_DIR/version"
READY_FILE="$CORE_DIR/dotdot_ready"

# The project's record folders, shipped with dotdot (each with a .gitkeep), and
# the prefix of their numbered files.
FEATURES_DIR="$DOTDOT_ROOT/Features"
FEATURE_PREFIX="f"
DECISIONS_DIR="$DOTDOT_ROOT/Decisions"
DECISION_PREFIX="d"
NOTES_DIR="$DOTDOT_ROOT/Notes"
NOTE_PREFIX="n"
TASKS_DIR="$DOTDOT_ROOT/Tasks"
TASK_PREFIX="t"
PLUGINS_DIR="$DOTDOT_ROOT/.plugins"
PLUGINS_LOCK="$PLUGINS_DIR/plugins.lock"
PLUGINS_MAP="$PLUGINS_DIR/pluginsmap.conf"

USER_FILE="$DOTDOT_ROOT/USER.md"
USER_EXAMPLE_FILE="$DOTDOT_ROOT/USER.example.md"
ENTRY_LINK="$BASE/dot"

paths::in_dotdot() {
  local path="$1"
  case "$path" in
    /*) printf '%s\n' "$path"; return ;;
    "$DOTDOT_NAME") path="." ;;
    "$DOTDOT_NAME"/*) path="${path#*/}" ;;
  esac
  printf '%s\n' "$DOTDOT_ROOT/$path"
}

# Every part of the system and every module: the directories commands and
# skills are found in, system first.
paths::modules() {
  local part
  for part in "${SYSTEM_PARTS[@]}"; do
    printf '%s\n' "$SYSTEM_DIR/$part"
  done
  for part in "${CORE_MODULES[@]}"; do
    printf '%s\n' "$MODULES_DIR/$part"
  done
}

# Every installed plugin's directory, in the order they were added (the lock's
# order), so the first one added keeps whatever a later one would clash with.
paths::plugins() {
  local directory plugin
  {
    [ ! -f "$PLUGINS_LOCK" ] || sed -n 's/^\([a-z0-9][a-z0-9-]*\/[a-z0-9][a-z0-9-]*\)=.*/\1/p' "$PLUGINS_LOCK"
    for directory in "$PLUGINS_DIR"/*/*/; do
      [ -d "$directory" ] || continue
      directory="${directory%/}"
      printf '%s\n' "${directory#"$PLUGINS_DIR"/}"
    done
  } | awk '!seen[$0]++' | while IFS= read -r plugin; do
    [ ! -d "$PLUGINS_DIR/$plugin" ] || printf '%s\n' "$PLUGINS_DIR/$plugin"
  done
}

# Every link in a sync map (the project's, or dotdot's default while it has
# none) as "<plugin>|<origin>|<destination>"; <plugin> is the owner/name
# of the block the line sits in, empty outside one, and a "!<destination>"
# removal has "!" as its origin.
paths::sync_map_entries() {
  local map="${1:-$SYNC_MAP}"
  [ -f "$map" ] || map="$SYNC_MAP_STUB"
  awk -v separator="$SYNC_MAP_SEPARATOR" '
    { sub(/\r$/, "") }
    /^# <!-- \/[a-z0-9][a-z0-9-]*\/[a-z0-9][a-z0-9-]* -->$/ { plugin = ""; next }
    /^# <!-- [a-z0-9][a-z0-9-]*\/[a-z0-9][a-z0-9-]* -->$/ { plugin = substr($0, 8, length($0) - 11); next }
    /^[ \t]*(#|$)/ { next }
    /^[ \t]*!/ { line = $0; sub(/^[ \t]*![ \t]*/, "", line); sub(/[ \t]+$/, "", line); print plugin "|!|" line; next }
    {
      split_at = index($0, separator)
      origin = split_at ? substr($0, 1, split_at - 1) : $0
      destination = split_at ? substr($0, split_at + length(separator)) : ""
      gsub(/^[ \t]+|[ \t]+$/, "", origin); gsub(/^[ \t]+|[ \t]+$/, "", destination)
      print plugin "|" origin "|" destination
    }
  ' "$map"
}
