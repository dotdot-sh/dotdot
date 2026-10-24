#!/usr/bin/env bash

DOT_LOADED_MODULES=" "
DOT_PACKAGES=" framework core plugins "
DOT_PRIVATE_SEGMENT="internal"
DOT_MODULE_PATTERN='^[a-z][a-z0-9-]*(\.[a-z0-9][a-z0-9-]*)+$'
DOT_COMMAND_PATTERN='^[a-z0-9][a-z0-9-]*(:[a-z][a-z0-9-]*){0,2}$'
DOT_COMMAND_MAX_DEPTH=2
DOT_RESERVED_COMMANDS=(help list)
DOT_CONFIG_KEY_PATTERN='^[A-Z][A-Z0-9_]*$'
DOT_EXIT_TASKS=()
DOT_PLUGIN=""
DOT_COMMAND=""
DOT_MODULE_FILE=""
DOT_MODULE_HOME=""

SYSTEM_DIR=$(CDPATH='' cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
CORE_DIR=$(dirname -- "$SYSTEM_DIR")
FRAMEWORK_DIR="$CORE_DIR/framework"
MODULES_DIR="$CORE_DIR/modules"
DOTDOT_ROOT=$(dirname -- "$CORE_DIR")
BASE=$(CDPATH='' cd -P -- "$DOTDOT_ROOT/.." && pwd)
DOTDOT_NAME=$(basename -- "$DOTDOT_ROOT")

. "$SYSTEM_DIR/paths.sh"

# The file a module name loads, into DOT_MODULE_FILE.
dot::module_file() {
  local name="$1" path
  [[ "$name" =~ $DOT_MODULE_PATTERN ]] || return 1
  path="${name#*.}"
  path="${path//./\/}.sh"
  case "${name%%.*}" in
    framework) DOT_MODULE_FILE="$FRAMEWORK_DIR/$path" ;;
    core) DOT_MODULE_FILE="$CORE_DIR/$path" ;;
    plugins) DOT_MODULE_FILE="$PLUGINS_DIR/$path" ;;
    *) return 1 ;;
  esac
}

dot::plugin_of() {
  local file="$1" relative owner
  case "$file" in
    "$PLUGINS_DIR"/*/*/*)
      relative="${file#"$PLUGINS_DIR"/}"
      owner="${relative%%/*}"
      relative="${relative#*/}"
      printf '%s/%s\n' "$owner" "${relative%%/*}"
      ;;
  esac
}

# The directory a module's own code lives in, the only place that may load
# it, into DOT_MODULE_HOME: core.system.<part> and core.modules.<module>,
# plugins.<owner>.<name>, or, for a framework module with an internal/ part,
# the directory holding internal/; empty when anyone may load it.
dot::module_home() {
  local name="$1" path
  DOT_MODULE_HOME=""
  case "$name" in
    framework.*".$DOT_PRIVATE_SEGMENT."*)
      path="${name#framework.}"
      path="${path%%".$DOT_PRIVATE_SEGMENT."*}"
      DOT_MODULE_HOME="$FRAMEWORK_DIR/${path//./\/}"
      ;;
    core.* | plugins.*)
      path="${name#*.}"
      name="${path#*.}"
      case "$1" in
        core.*) DOT_MODULE_HOME="$CORE_DIR/${path%%.*}/${name%%.*}" ;;
        *) DOT_MODULE_HOME="$PLUGINS_DIR/${path%%.*}/${name%%.*}" ;;
      esac
      ;;
  esac
}

dot::is_allowed() {
  local name="$1" importer="$2" home
  case "$DOT_PACKAGES" in
    *" ${name%%.*} "*) ;;
    *) return 1 ;;
  esac
  [ -n "$importer" ] || return 0
  dot::module_home "$name"
  home="$DOT_MODULE_HOME"
  [ -z "$home" ] || [ "${importer#"$home"/}" != "$importer" ]
}

dot::use() {
  local importer name file
  dot::physical_to importer "${BASH_SOURCE[1]-}"
  for name in "$@"; do
    if ! dot::module_file "$name" || [ ! -f "$DOT_MODULE_FILE" ]; then
      printf '❌ Unknown dotdot module: %s\n' "$name" >&2
      exit 1
    fi
    if ! dot::is_allowed "$name" "$importer"; then
      printf '❌ %s may not use the dotdot module %s.\n' "$(dot::relative "${importer:-this script}")" "$name" >&2
      exit 1
    fi
    case "$DOT_LOADED_MODULES" in
      *" $name "*) continue ;;
    esac
    DOT_LOADED_MODULES="$DOT_LOADED_MODULES$name "
    file="$DOT_MODULE_FILE"
    . "$file"
  done
}

dot::relative() {
  case "$1" in
    "$BASE"/*) printf '%s\n' "${1#"$BASE"/}" ;;
    *) printf '%s\n' "$1" ;;
  esac
}

dot::path() {
  case "$1" in
    project) printf '%s\n' "$BASE" ;;
    dotdot) printf '%s\n' "$DOTDOT_ROOT" ;;
    plugin)
      [ -n "$DOT_PLUGIN" ] || return 1
      printf '%s\n' "$PLUGINS_DIR/$DOT_PLUGIN"
      ;;
    *) return 1 ;;
  esac
}

# A file's path with its directory's links resolved, into the variable named
# $1; dotdot's own files, already loaded by their real path, are taken as
# they are.
dot::physical_to() {
  local dot_physical_path="$2"
  if [ -n "$dot_physical_path" ]; then
    case "$dot_physical_path" in
      *"/./"* | *"/../"*) dot_physical_path="$(CDPATH='' cd -P -- "$(dirname -- "$dot_physical_path")" 2>/dev/null && pwd)/${dot_physical_path##*/}" ;;
      "$CORE_DIR"/* | "$PLUGINS_DIR"/*) ;;
      *) dot_physical_path="$(CDPATH='' cd -P -- "$(dirname -- "$dot_physical_path")" 2>/dev/null && pwd)/${dot_physical_path##*/}" ;;
    esac
  fi
  printf -v "$1" '%s' "$dot_physical_path"
}

# The prefix a plugin's settings carry in .env: ACME__WIDGETS__ for acme/widgets.
dot::config_prefix() {
  printf '%s__%s__' "${1%%/*}" "${1#*/}" | tr 'a-z-' 'A-Z_'
}

# A setting is named in capitals; one read or written from a plugin's code
# carries that plugin's prefix.
dot::check_config_key() {
  local key="$1" caller="$2" plugin prefix
  [[ "$key" =~ $DOT_CONFIG_KEY_PATTERN ]] || { dot::raise "Invalid setting name: $key"; return 1; }
  dot::physical_to caller "$caller"
  plugin=$(dot::plugin_of "$caller")
  [ -n "$plugin" ] || return 0
  prefix=$(dot::config_prefix "$plugin")
  [ "${key#"$prefix"}" != "$key" ] || { dot::raise "$plugin's settings must start with $prefix: $key"; return 1; }
}

dot::read_config() {
  local key="$1" value
  dot::check_config_key "$key" "$2" || return 2
  dot::use framework.helpers.kv
  value=$(framework.helpers.kv::value "$ENV_FILE" "$key" 2>/dev/null) && [ -n "$value" ] || return 1
  printf '%s\n' "$value"
}

# A setting's value from .dot/.env; unset or empty stops with how to set it.
dot::config() {
  local status=0
  dot::read_config "$1" "${BASH_SOURCE[1]-}" || status=$?
  [ "$status" -ne 1 ] || dot::raise "$1 is not set: set it in $(dot::relative "$ENV_FILE"), then try again."
  return "$status"
}

# A setting's value from .dot/.env, or nothing (status 1) when unset.
dot::optional_config() {
  dot::read_config "$1" "${BASH_SOURCE[1]-}"
}

dot::save_config() {
  dot::check_config_key "$1" "${BASH_SOURCE[1]-}" || return 1
  dot::use framework.helpers.kv
  (umask 077 && framework.helpers.kv::write "$ENV_FILE" "$1" "$2") && chmod 600 "$ENV_FILE" \
    || dot::raise "Could not save $1 in $(dot::relative "$ENV_FILE")."
}

dot::call() {
  DOT_PLUGIN="" bash "$DOT_BIN" "$@"
}

dot::on_exit() {
  DOT_EXIT_TASKS+=("$1")
}

dot::raise() {
  printf '%s\n' "$*" >> "$DOT_ERROR_FILE"
  return 1
}

dot::abort() {
  dot::raise "$@" || exit 1
}

dot::report_errors() {
  local message
  [ -s "$DOT_ERROR_FILE" ] || return 0
  dot::use framework.console.output
  while IFS= read -r message; do
    framework.console.output::error "$message"
  done < "$DOT_ERROR_FILE"
}

dot::finish() {
  local status=$? task
  [ "$status" -eq 0 ] || dot::report_errors
  rm -f -- "$DOT_ERROR_FILE"
  for task in ${DOT_EXIT_TASKS[@]+"${DOT_EXIT_TASKS[@]}"}; do
    eval "$task" || true
  done
  return "$status"
}

# Applies the timezone in USER.md's frontmatter, read without spawning a
# process since every command runs it.
dot::use_user_timezone() {
  local line zone="" first=true
  [ -f "$USER_FILE" ] || return 0
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"
    if $first; then
      [ "$line" = "---" ] || return 0
      first=false
      continue
    fi
    [ "$line" != "---" ] || break
    case "$line" in
      timezone:*) zone="${line#timezone:}"; break ;;
    esac
  done < "$USER_FILE"
  zone="${zone%%#*}"
  zone="${zone//[\"\' $'\t']/}"
  [ -n "$zone" ] || return 0
  dot::use framework.helpers.date
  framework.helpers.date::use_timezone "$zone" || printf '⚠️  Ignoring unknown timezone in %s: %s\n' "$(basename -- "$USER_FILE")" "$zone" >&2
}

DOT_ERROR_FILE=$(mktemp)
trap 'dot::finish' EXIT
trap 'exit 130' INT TERM HUP

dot::use_user_timezone

. "$SYSTEM_DIR/kernel.sh"
