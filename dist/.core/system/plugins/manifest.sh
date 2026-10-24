#!/usr/bin/env bash

dot::use framework.helpers.fs framework.helpers.kv framework.helpers.text

PLUGIN_API=1
PLUGIN_SEGMENT_PATTERN='^[a-z0-9][a-z0-9-]*$'
PLUGIN_ROOT="dotdot"
PLUGIN_REQUIRES_KEY="REQUIRES"
PLUGIN_DEPENDS_KEY="DEPENDS"
PLUGIN_DIRECTORIES_KEY="DIRECTORIES"
PLUGIN_LOCK_SEPARATOR="="
PLUGIN_LINKED_DIRS=(skills agents)
PLUGIN_LIST_SEPARATOR="::"
PLUGIN_DOC_ORIGIN="@"
PLUGIN_DOCUMENT_PATTERN='^[A-Za-z0-9][A-Za-z0-9._-]*\.md$'
PLUGIN_SCRIPT_PATTERN='^[a-z][a-z0-9-]*\.sh$'
PLUGIN_DIRECTORY_PATTERN='^[A-Z][A-Za-z0-9-]*$'
PLUGIN_CONTEXT_DIR="context"
PLUGIN_STUBS_DIR="stubs"
PLUGIN_ENV_STUB="env.stub"
PLUGIN_UNKNOWN_COMMIT="unknown"

core.system.plugins.manifest::id() {
  local id
  id=$(framework.helpers.text::lower "$1")
  id="${id%.git}"
  core.system.plugins.manifest::is_id "$id" || return 1
  printf '%s\n' "$id"
}

core.system.plugins.manifest::is_id() {
  local owner="${1%%/*}" name="${1#*/}"
  [ "$owner" != "$1" ] && [[ "$owner" =~ $PLUGIN_SEGMENT_PATTERN ]] && [[ "$name" =~ $PLUGIN_SEGMENT_PATTERN ]]
}

core.system.plugins.manifest::owner() {
  printf '%s\n' "${1%%/*}"
}

core.system.plugins.manifest::directory() {
  printf '%s\n' "$PLUGINS_DIR/$1"
}

core.system.plugins.manifest::value() {
  framework.helpers.kv::value "$1/$PLUGIN_MANIFEST" "$2" 2>/dev/null || true
}

core.system.plugins.manifest::list() {
  core.system.plugins.manifest::value "$1" "$2" | tr ', ' '\n\n' | sed '/^$/d'
}

core.system.plugins.manifest::installed() {
  [ -f "$PLUGINS_LOCK" ] || return 0
  awk -v separator="$PLUGIN_LOCK_SEPARATOR" '
    /^[ \t]*(#|$)/ { next }
    { split_at = index($0, separator); if (split_at > 1) print substr($0, 1, split_at - 1) }
  ' "$PLUGINS_LOCK"
}

core.system.plugins.manifest::lock_entry() {
  [ -f "$PLUGINS_LOCK" ] || return 1
  awk -v wanted="$1$PLUGIN_LOCK_SEPARATOR" '
    index($0, wanted) == 1 { print substr($0, length(wanted) + 1); found = 1; exit }
    END { exit !found }
  ' "$PLUGINS_LOCK"
}

core.system.plugins.manifest::lock() {
  core.system.plugins.manifest::is_id "$1" || return 1
  mkdir -p -- "$(dirname -- "$PLUGINS_LOCK")" && { [ -f "$PLUGINS_LOCK" ] || : > "$PLUGINS_LOCK"; } || return 1
  awk -v wanted="$1$PLUGIN_LOCK_SEPARATOR" -v entry="$1$PLUGIN_LOCK_SEPARATOR$2" '
    index($0, wanted) == 1 { if (!done) print entry; done = 1; next }
    { print }
    END { if (!done) print entry }
  ' "$PLUGINS_LOCK" | framework.helpers.fs::replace "$PLUGINS_LOCK"
}

core.system.plugins.manifest::unlock() {
  core.system.plugins.manifest::lock_entry "$1" >/dev/null || return 1
  awk -v wanted="$1$PLUGIN_LOCK_SEPARATOR" 'index($0, wanted) != 1' "$PLUGINS_LOCK" | framework.helpers.fs::replace "$PLUGINS_LOCK"
}

core.system.plugins.manifest::commands() {
  local source="$1" file name
  [ -d "$source/$MODULE_COMMANDS_DIR" ] || return 0
  while IFS= read -r file; do
    name="${file#"$source/$MODULE_COMMANDS_DIR"/}"
    name="${name%.sh}"
    printf '%s\n' "${name//\//:}"
  done < <(find "$source/$MODULE_COMMANDS_DIR" -mindepth 1 -maxdepth "$DOT_COMMAND_MAX_DEPTH" -type f -name '*.sh' | sort)
}

core.system.plugins.manifest::taken_commands() {
  local plugin="$1" source="$2"
  core.system.plugins.manifest::commands "$source" | sed "s|^|$(core.system.plugins.manifest::owner "$plugin"):|" \
    | grep -xF -f <(kernel::commands | cut -d'|' -f1) | grep -vxF -f <(core.system.plugins.manifest::own_commands "$plugin") || true
}

core.system.plugins.manifest::own_commands() {
  local directory
  directory=$(core.system.plugins.manifest::directory "$1")
  [ -d "$directory" ] || return 0
  core.system.plugins.manifest::commands "$directory" | sed "s|^|$(core.system.plugins.manifest::owner "$1"):|"
}

core.system.plugins.manifest::validate_commands() {
  local source="$1" entry relative depth
  [ -d "$source/$MODULE_COMMANDS_DIR" ] || return 0
  while IFS= read -r entry; do
    relative="${entry#"$source/$MODULE_COMMANDS_DIR"/}"
    depth=$(printf '%s' "$relative" | tr -cd '/' | wc -c | tr -d ' ')
    [ -d "$entry" ] && continue
    [[ "$(basename -- "$entry")" =~ $PLUGIN_SCRIPT_PATTERN ]] && [ "$depth" -lt "$DOT_COMMAND_MAX_DEPTH" ] \
      || { dot::raise "$MODULE_COMMANDS_DIR/$relative must be a <name>.sh command, at most $DOT_COMMAND_MAX_DEPTH levels deep."; return 1; }
  done < <(find "$source/$MODULE_COMMANDS_DIR" -mindepth 1 ! -name '.*')
}

core.system.plugins.manifest::validate_owner() {
  local owner
  owner=$(core.system.plugins.manifest::owner "$1")
  ! kernel::reserved_names | grep -xF -- "$owner" >/dev/null \
    || { dot::raise "$1 can't be added: $owner is one of dotdot's own command names."; return 1; }
}

core.system.plugins.manifest::linked_entries() {
  local root="$1" directory entry
  for directory in "${PLUGIN_LINKED_DIRS[@]}"; do
    [ -d "$root/$directory" ] || continue
    while IFS= read -r entry; do
      printf '%s/%s\n' "$directory" "$(basename -- "$entry")"
    done < <(find "$root/$directory" -mindepth 1 -maxdepth 1 ! -name "$KEEP_FILE" | sort)
  done
}

core.system.plugins.manifest::validate_links() {
  local source="$1" plugin="$2" name="${2#*/}" entry root
  while IFS= read -r entry; do
    case "$(basename -- "$entry")" in
      "$name"-?*) ;;
      *) dot::raise "$entry must be named $name-<name>, after the plugin, so it can't clash with dotdot's or another plugin's."; return 1 ;;
    esac
    while IFS= read -r root; do
      [ "$root" != "$PLUGINS_DIR/$plugin" ] || continue
      [ ! -e "$root/$entry" ] && [ ! -L "$root/$entry" ] \
        || { dot::raise "$entry is already taken by $(dot::relative "$root")."; return 1; }
    done < <({ paths::modules; paths::plugins; })
  done < <(core.system.plugins.manifest::linked_entries "$source")
}

# A project path a plugin may link into: relative, never climbing out, never
# inside dotdot or .git, never the dot entry point.
core.system.plugins.manifest::is_destination() {
  case "/$1/" in
    //* | */../* | */./* | */.git/* | "/$DOTDOT_NAME/"* | "/dot/") return 1 ;;
  esac
}

core.system.plugins.manifest::link_destinations() {
  local link
  while IFS= read -r link; do
    printf '%s\n' "${link#*"$PLUGIN_LIST_SEPARATOR"}"
  done < <(core.system.plugins.manifest::list "$1" "$PLUGIN_LINKS_KEY")
}

core.system.plugins.manifest::validate_declared_links() {
  local source="$1" plugin="$2" link origin destination key value root
  for key in "$PLUGIN_HARNESS_SKILLS_KEY" "$PLUGIN_HARNESS_AGENTS_KEY"; do
    value=$(core.system.plugins.manifest::value "$source" "$key")
    [ -z "$value" ] || core.system.plugins.manifest::is_destination "${value%/}" \
      || { dot::raise "$key=$value must be a project directory outside $DOTDOT_NAME/ and .git/."; return 1; }
  done
  while IFS= read -r link; do
    origin="${link%%"$PLUGIN_LIST_SEPARATOR"*}"
    destination="${link#*"$PLUGIN_LIST_SEPARATOR"}"
    [ "$origin" != "$link" ] && [ -n "$origin" ] && [ -n "$destination" ] \
      || { dot::raise "$PLUGIN_LINKS_KEY lists $link; give <origin>$PLUGIN_LIST_SEPARATOR<destination>."; return 1; }
    case "$origin" in
      "$PLUGIN_DOC_ORIGIN"*)
        [[ "${origin#"$PLUGIN_DOC_ORIGIN"}" =~ $PLUGIN_DOCUMENT_PATTERN ]] \
          || { dot::raise "$PLUGIN_LINKS_KEY origin $origin must name one of dotdot's top-level docs, like @RULES.md."; return 1; }
        ;;
      *)
        case "/$origin/" in
          //* | */../*) dot::raise "$PLUGIN_LINKS_KEY origin $origin must be a path inside the plugin."; return 1 ;;
        esac
        [ -e "$source/$origin" ] || { dot::raise "$PLUGIN_LINKS_KEY origin $origin is not in the plugin."; return 1; }
        ;;
    esac
    core.system.plugins.manifest::is_destination "${destination%/}" \
      || { dot::raise "$PLUGIN_LINKS_KEY destination $destination must be a project path outside $DOTDOT_NAME/ and .git/."; return 1; }
    ! paths::sync_map_entries | awk -F'|' -v plugin="$plugin" '$1 != plugin { print $3 }' | grep -xF -- "$destination" >/dev/null \
      || { dot::raise "$PLUGIN_LINKS_KEY destination $destination is already linked in $(dot::relative "$SYNC_MAP")."; return 1; }
    while IFS= read -r root; do
      [ "$root" != "$PLUGINS_DIR/$plugin" ] || continue
      ! core.system.plugins.manifest::link_destinations "$root" | grep -xF -- "$destination" >/dev/null \
        || { dot::raise "$PLUGIN_LINKS_KEY destination $destination is already linked by $(dot::relative "$root")."; return 1; }
    done < <(paths::plugins)
  done < <(core.system.plugins.manifest::list "$source" "$PLUGIN_LINKS_KEY")
}

# Everything a plugin keeps in .env carries its prefix, so its settings never
# read or overwrite dotdot's or another plugin's.
core.system.plugins.manifest::validate_settings() {
  local stub="$1/$PLUGIN_STUBS_DIR/$PLUGIN_ENV_STUB" prefix key
  [ -f "$stub" ] || return 0
  prefix=$(dot::config_prefix "$2")
  while IFS= read -r key; do
    [ "${key#"$prefix"}" != "$key" ] && [[ "$key" =~ $DOT_CONFIG_KEY_PATTERN ]] \
      || { dot::raise "$PLUGIN_STUBS_DIR/$PLUGIN_ENV_STUB: $2's settings must start with $prefix: $key"; return 1; }
  done < <(framework.helpers.kv::keys "$stub")
}

core.system.plugins.manifest::validate() {
  local source="$1" plugin="$2" requires entry directory taken
  [ -f "$source/$PLUGIN_MANIFEST" ] || { dot::raise "$plugin has no $PLUGIN_ROOT/$PLUGIN_MANIFEST."; return 1; }
  requires=$(core.system.plugins.manifest::value "$source" "$PLUGIN_REQUIRES_KEY")
  [ "$requires" = "$PLUGIN_API" ] \
    || { dot::raise "$plugin needs plugin API ${requires:-(none)}; this dotdot has $PLUGIN_API. Update the plugin or dotdot."; return 1; }
  [ -z "$(find "$source" -type l -print -quit)" ] || { dot::raise "$plugin holds symlinks."; return 1; }
  [ -z "$(find "$source/$PLUGIN_STUBS_DIR" -name .git -print -quit 2>/dev/null)" ] \
    || { dot::raise "$plugin has stubs under .git/; a plugin may not seed git's own files."; return 1; }
  core.system.plugins.manifest::validate_owner "$plugin" || return 1
  core.system.plugins.manifest::validate_settings "$source" "$plugin" || return 1
  core.system.plugins.manifest::validate_commands "$source" || return 1
  taken=$(core.system.plugins.manifest::taken_commands "$plugin" "$source")
  [ -z "$taken" ] || { dot::raise "$plugin's commands are already taken: $(printf '%s' "$taken" | paste -sd ' ' -)"; return 1; }
  core.system.plugins.manifest::validate_links "$source" "$plugin" || return 1
  core.system.plugins.manifest::validate_declared_links "$source" "$plugin" || return 1
  for entry in "$source/$PLUGIN_CONTEXT_DIR"/*; do
    [ -e "$entry" ] || continue
    [ -f "$entry" ] && [[ "$(basename -- "$entry")" =~ $PLUGIN_DOCUMENT_PATTERN ]] \
      || { dot::raise "$PLUGIN_CONTEXT_DIR/$(basename -- "$entry") must be a .md file."; return 1; }
  done
  while IFS= read -r directory; do
    [[ "$directory" =~ $PLUGIN_DIRECTORY_PATTERN ]] \
      || { dot::raise "$PLUGIN_DIRECTORIES_KEY lists $directory; give top-level dotdot directory names like Notes."; return 1; }
  done < <(core.system.plugins.manifest::list "$source" "$PLUGIN_DIRECTORIES_KEY")
}

core.system.plugins.manifest::missing_dependencies() {
  local dependency
  while IFS= read -r dependency; do
    case "$dependency" in
      framework.integrations.*) [ -d "$FRAMEWORK_DIR/integrations/${dependency#framework.integrations.}" ] || printf '%s\n' "$dependency" ;;
      *) command -v "$dependency" >/dev/null || printf '%s\n' "$dependency" ;;
    esac
  done < <(core.system.plugins.manifest::list "$1" "$PLUGIN_DEPENDS_KEY")
}
