#!/usr/bin/env bash

dot::use framework.console.output

KERNEL_COLUMN_WIDTH=26
KERNEL_FILE=""

kernel::commands_in() {
  local directory="$1" prefix="$2" file name
  [ -d "$directory" ] || return 0
  while IFS= read -r file; do
    name="${file#"$directory"/}"
    name="${name%.sh}"
    name="$prefix${name//\//:}"
    [[ "$name" =~ $DOT_COMMAND_PATTERN ]] || continue
    printf '%s|%s\n' "$name" "$file"
  done < <(find "$directory" -mindepth 1 -maxdepth "$DOT_COMMAND_MAX_DEPTH" -type f -name '*.sh' | sort)
}

# dotdot's own commands, found with a single find over every module.
kernel::core_commands() {
  local module directories=() file name
  while IFS= read -r module; do
    [ ! -d "$module/$MODULE_COMMANDS_DIR" ] || directories+=("$module/$MODULE_COMMANDS_DIR")
  done < <(paths::modules)
  while IFS= read -r file; do
    name="${file#"$CORE_DIR"/*/*/"$MODULE_COMMANDS_DIR"/}"
    name="${name%.sh}"
    name="${name//\//:}"
    [[ "$name" =~ $DOT_COMMAND_PATTERN ]] && printf '%s|%s\n' "$name" "$file"
  done < <(find "${directories[@]}" -mindepth 1 -maxdepth "$DOT_COMMAND_MAX_DEPTH" -type f -name '*.sh' | sort)
}

# Every command as "<name>|<file>": dotdot's own first, then each plugin's
# under its owner; a name already taken keeps its first owner.
kernel::commands() {
  local plugin
  {
    kernel::core_commands
    while IFS= read -r plugin; do
      kernel::commands_in "$plugin/$MODULE_COMMANDS_DIR" "$(basename -- "$(dirname -- "$plugin")"):"
    done < <(paths::plugins)
  } | awk -F'|' '!seen[$1]++'
}

# The first parts of dotdot's own command names, and the names bash dot
# itself answers to: no plugin owner may take one.
kernel::reserved_names() {
  kernel::core_commands | cut -d'|' -f1 | cut -d: -f1 | sort -u
  printf '%s\n' "${DOT_RESERVED_COMMANDS[@]}"
}

# The file a command runs, into KERNEL_FILE, looked up directly (dotdot's own
# first, then each plugin's under its owner) rather than by listing every
# command.
kernel::find() {
  local name="$1" path part owner plugin
  path="${name//://}.sh"
  for part in "${SYSTEM_PARTS[@]}"; do
    KERNEL_FILE="$SYSTEM_DIR/$part/$MODULE_COMMANDS_DIR/$path"
    [ ! -f "$KERNEL_FILE" ] || return 0
  done
  for part in "${CORE_MODULES[@]}"; do
    KERNEL_FILE="$MODULES_DIR/$part/$MODULE_COMMANDS_DIR/$path"
    [ ! -f "$KERNEL_FILE" ] || return 0
  done
  owner="${name%%:*}"
  [ "$owner" != "$name" ] || return 1
  path="${path#*/}"
  for plugin in "$PLUGINS_DIR/$owner"/*/; do
    KERNEL_FILE="${plugin%/}/$MODULE_COMMANDS_DIR/$path"
    [ ! -f "$KERNEL_FILE" ] || return 0
  done
  return 1
}

kernel::description() {
  sed -n 's/^DESCRIPTION="\(.*\)"$/\1/p' "$1" | head -n 1
}

kernel::list() {
  local name file namespace previous=""
  framework.console.output::line "$(framework.console.output::paint bold dotdot) commands. Every command answers --help."
  framework.console.output::newline
  framework.console.output::line "$(framework.console.output::paint yellow Usage:)"
  framework.console.output::line "  bash dot <command> [arguments]"
  framework.console.output::line "  bash dot help <command>"
  framework.console.output::newline
  framework.console.output::line "$(framework.console.output::paint yellow 'Available commands:')"
  while IFS='|' read -r name file; do
    namespace="${name%%:*}"
    if [ "$name" != "$namespace" ] && [ "$namespace" != "$previous" ]; then
      framework.console.output::line " $(framework.console.output::paint yellow "$namespace")"
    fi
    previous="$namespace"
    printf '  %s %s\n' "$(framework.console.output::paint green "$(printf "%-${KERNEL_COLUMN_WIDTH}s" "$name")")" "$(kernel::description "$file")"
  done < <(kernel::commands | awk -F'|' '{ print ($1 ~ /:/ ? 1 : 0) "|" $0 }' | sort | cut -d'|' -f2-)
}

kernel::run() {
  local name="${1-}" file
  [[ "$name" =~ $DOT_COMMAND_PATTERN ]] || framework.console.output::fail "Invalid command: $name. Run bash dot to list them."
  kernel::find "$name" || framework.console.output::fail "Unknown command: $name. Run bash dot to list them."
  file="$KERNEL_FILE"
  shift
  DOT_COMMAND="$name"
  DOT_PLUGIN=""
  case "$file" in
    "$PLUGINS_DIR"/*)
      DOT_PLUGIN="${file#"$PLUGINS_DIR"/}"
      DOT_PLUGIN="${DOT_PLUGIN%%/"$MODULE_COMMANDS_DIR"/*}"
      ;;
  esac
  . "$file"
  case "${1-}" in
    -h | --help)
      usage
      return 0
      ;;
  esac
  handle "$@"
}

kernel::handle() {
  case "${1-}" in
    '' | list | -h | --help) kernel::list ;;
    help)
      shift
      [ $# -gt 0 ] || { kernel::list; return 0; }
      kernel::run "$1" --help
      ;;
    *) kernel::run "$@" ;;
  esac
}
