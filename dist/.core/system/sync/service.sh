#!/usr/bin/env bash

dot::use framework.helpers.date framework.helpers.fs framework.helpers.kv

SYNC_SEPARATOR="::"
SYNC_TREE_SUFFIX="/*"
SYNC_LINKED_KINDS=(skills agents)
SYNC_LIST_SEPARATORS=", "
SYNC_MANAGED_DIRS=("$CORE_DIR" "$PLUGINS_DIR")

SYNC_ORIGINS=()
SYNC_DESTINATIONS=()
SYNC_LABELS=()
SYNC_ACTIONS=()
SYNC_TREE_DIRS=()
SYNC_FAILURES=0
SYNC_OVERRIDABLE=0
SYNC_CHANGES=0
SYNC_WARNINGS=()
SYNC_ERRORS=()
SYNC_LINKED=0
SYNC_UNCHANGED=0
SYNC_SKIPPED=0
SYNC_REMOVED=0
SYNC_SEED_USER=false
SYNC_MAP_NOTES=()
SYNC_REMOVALS=()
SYNC_ACTION=""
SYNC_PLANNED=""
SYNC_PLUGIN_NAME=""
SYNC_DOTTED=""
SYNC_SHORTCUT=""
SYNC_EFFECTIVE_MAP=""
SYNC_WORK=""

core.system.sync.service::manifest_list() {
  framework.helpers.kv::value "$1/$PLUGIN_MANIFEST" "$2" 2>/dev/null | tr "$SYNC_LIST_SEPARATORS" '\n\n' | sed '/^$/d' || true
}

core.system.sync.service::block_open() {
  printf '# <!-- %s -->\n' "$1"
}

core.system.sync.service::block_close() {
  printf '# <!-- /%s -->\n' "$1"
}

# A plugin's block for the sync map, from what its plugin.conf declares;
# nothing when it declares no link.
core.system.sync.service::plugin_block() {
  local plugin="$1" directory="$PLUGINS_DIR/$1" lines="" value link
  value=$(framework.helpers.kv::value "$directory/$PLUGIN_MANIFEST" "$PLUGIN_HARNESS_SKILLS_KEY" 2>/dev/null) && [ -n "$value" ] \
    && lines="$lines@dotdotSkills$SYNC_MAP_SEPARATOR${value%/}"$'\n'"@pluginsSkills$SYNC_MAP_SEPARATOR${value%/}"$'\n'
  value=$(framework.helpers.kv::value "$directory/$PLUGIN_MANIFEST" "$PLUGIN_HARNESS_AGENTS_KEY" 2>/dev/null) && [ -n "$value" ] \
    && lines="$lines@dotdotAgents$SYNC_MAP_SEPARATOR${value%/}"$'\n'"@pluginsAgents$SYNC_MAP_SEPARATOR${value%/}"$'\n'
  while IFS= read -r link; do
    lines="$lines$link"$'\n'
  done < <(core.system.sync.service::manifest_list "$directory" "$PLUGIN_LINKS_KEY")
  [ -n "$lines" ] || return 0
  core.system.sync.service::block_open "$plugin"
  printf '%s' "$lines"
  core.system.sync.service::block_close "$plugin"
}

core.system.sync.service::blocks_in() {
  sed -n 's|^# <!-- \([a-z0-9][a-z0-9-]*/[a-z0-9][a-z0-9-]*\) -->$|\1|p' "$1"
}

# Marks where a removed plugin's links lay, so their broken links get pruned.
core.system.sync.service::sweep_block() {
  local origin destination
  while IFS='|' read -r _ origin destination; do
    [ -n "$destination" ] && ! core.system.sync.service::has_parent_segment "$destination" || continue
    case "$origin" in
      @dotdotSkills | @pluginsSkills | @dotdotAgents | @pluginsAgents | *"$SYNC_TREE_SUFFIX") SYNC_TREE_DIRS+=("$BASE/${destination%/}") ;;
      '!') ;;
      *) destination="$BASE/${destination%/}"; SYNC_TREE_DIRS+=("${destination%/*}") ;;
    esac
  done < <(paths::sync_map_entries "$1" | awk -F'|' -v plugin="$2" '$1 == plugin')
}

core.system.sync.service::drop_block() {
  awk -v open="$(core.system.sync.service::block_open "$2")" -v closer="$(core.system.sync.service::block_close "$2")" '
    $0 == open { skip = 1; next }
    skip { if ($0 == closer) skip = 0; next }
    { print }
  ' "$1" | framework.helpers.fs::replace "$1"
}

# The sync map this run works from: the project's (or dotdot's default when
# it has none), less the blocks of plugins no longer installed and of those
# to refresh, plus a block for every installed plugin without one. It is
# written back only when the run is applied.
core.system.sync.service::prepare_map() {
  local refresh=" $1 " map plugin id
  framework.helpers.fs::make_temp_dir SYNC_WORK || { core.system.sync.service::fail "Could not create a temp directory."; return; }
  map="$SYNC_WORK/sync.map"
  if [ -f "$SYNC_MAP" ]; then
    cp -- "$SYNC_MAP" "$map"
  else
    cp -- "$SYNC_MAP_STUB" "$map"
    SYNC_MAP_NOTES+=("create $(dot::relative "$SYNC_MAP") from dotdot's default")
  fi
  while IFS= read -r id; do
    if [ ! -d "$PLUGINS_DIR/$id" ]; then
      core.system.sync.service::sweep_block "$map" "$id"
      core.system.sync.service::drop_block "$map" "$id"
      SYNC_MAP_NOTES+=("remove the block of $id, no longer installed")
    elif [[ "$refresh" == *" $id "* ]]; then
      core.system.sync.service::drop_block "$map" "$id"
    fi
  done < <(core.system.sync.service::blocks_in "$map")
  while IFS= read -r plugin; do
    id="${plugin#"$PLUGINS_DIR"/}"
    ! core.system.sync.service::blocks_in "$map" | grep -qxF -- "$id" || continue
    [ -n "$(core.system.sync.service::plugin_block "$id")" ] || continue
    { [ ! -s "$map" ] || [ -z "$(tail -n 1 -- "$map")" ] || printf '\n'; core.system.sync.service::plugin_block "$id"; } >> "$map"
    SYNC_MAP_NOTES+=("write the block of $id from its $PLUGIN_MANIFEST")
  done < <(paths::plugins)
  SYNC_EFFECTIVE_MAP="$map"
}

# A dotted path under <base>, one segment per directory level, into
# SYNC_DOTTED; a segment naming an existing entry with dots in it
# (plugin.conf) is taken whole.
core.system.sync.service::dotted_path() {
  local current="$1" rest="$2" segments=() count index end candidate found part
  IFS='.' read -r -a segments <<< "$rest"
  count=${#segments[@]}
  index=0
  while [ "$index" -lt "$count" ]; do
    found=false
    end=$count
    while [ "$end" -gt "$index" ]; do
      candidate="${segments[$index]}"
      for ((part = index + 1; part < end; part++)); do
        candidate="$candidate.${segments[$part]}"
      done
      if [ -e "$current/$candidate" ] || [ -L "$current/$candidate" ]; then
        current="$current/$candidate"
        index=$end
        found=true
        break
      fi
      end=$((end - 1))
    done
    if ! $found; then
      current="$current/${segments[$index]}"
      index=$((index + 1))
    fi
  done
  SYNC_DOTTED="$current"
}

# The dotdot-relative path a shortcut origin names, keeping a "/*" ending,
# into SYNC_SHORTCUT.
core.system.sync.service::shortcut_path() {
  local origin="$1" suffix="" rest name base owner
  case "$origin" in
    *"$SYNC_TREE_SUFFIX") suffix="$SYNC_TREE_SUFFIX"; origin="${origin%"$SYNC_TREE_SUFFIX"}" ;;
  esac
  case "$origin" in
    @module.*)
      rest="${origin#@module.}"
      name="${rest%%.*}"
      base="$MODULES_DIR/$name"
      [ -d "$base" ] || base="$SYSTEM_DIR/$name"
      [ "$rest" != "$name" ] || rest="$name."
      ;;
    @plugin.*)
      rest="${origin#@plugin.}"
      owner="${rest%%.*}"
      rest="${rest#*.}"
      name="${rest%%.*}"
      base="$PLUGINS_DIR/$owner/$name"
      [ "$rest" != "$name" ] || rest="$name."
      ;;
    *) return 1 ;;
  esac
  rest="${rest#*.}"
  if [ -n "$rest" ]; then
    core.system.sync.service::dotted_path "$base" "$rest"
    base="$SYNC_DOTTED"
  fi
  SYNC_SHORTCUT="${base#"$DOTDOT_ROOT"/}$suffix"
}

# The directories a set's skills or agents are found in: every system part
# and module for dotdot (discovered, not listed), every plugin for plugins.
core.system.sync.service::set_roots() {
  local root
  case "$1" in
    dotdot)
      for root in "$SYSTEM_DIR"/*/ "$MODULES_DIR"/*/; do
        [ ! -d "$root" ] || printf '%s\n' "${root%/}"
      done
      ;;
    plugins) paths::plugins ;;
  esac
}

# Each skill (skills/<name>/SKILL.md) or agent (agents/<name>.md) under a set's
# roots, as "<origin>::<destination>/<name>".
core.system.sync.service::set_links() {
  local set="$1" kind="$2" destination="${3%/}" root entry
  while IFS= read -r root; do
    case "$kind" in
      skills)
        for entry in "$root/skills"/*/SKILL.md; do
          [ -f "$entry" ] || continue
          entry="${entry%/SKILL.md}"
          printf '%s%s%s/%s\n' "${entry#"$DOTDOT_ROOT"/}" "$SYNC_SEPARATOR" "$destination" "${entry##*/}"
        done
        ;;
      agents)
        for entry in "$root/agents"/*.md; do
          [ -f "$entry" ] || continue
          printf '%s%s%s/%s\n' "${entry#"$DOTDOT_ROOT"/}" "$SYNC_SEPARATOR" "$destination" "${entry##*/}"
        done
        ;;
    esac
  done < <(core.system.sync.service::set_roots "$set")
}

core.system.sync.service::map_link() {
  local plugin="$1" origin="$2" destination="$3" root kind set path
  case "$origin" in
    '!') return 0 ;;
    @dotdotSkills | @pluginsSkills | @dotdotAgents | @pluginsAgents)
      case "$origin" in
        @dotdot*) set=dotdot ;;
        *) set=plugins ;;
      esac
      case "$origin" in
        *Skills) kind=skills ;;
        *) kind=agents ;;
      esac
      core.system.sync.service::set_links "$set" "$kind" "$destination"
      ;;
    @module.* | @plugin.*)
      core.system.sync.service::shortcut_path "$origin"
      printf '%s%s%s\n' "$SYNC_SHORTCUT" "$SYNC_SEPARATOR" "$destination"
      ;;
    @*.md) printf '%s%s%s\n' "${origin#@}" "$SYNC_SEPARATOR" "$destination" ;;
    @*) printf '%s%s%s\n' "$origin" "$SYNC_SEPARATOR" "$destination" ;;
    *)
      if [ -n "$plugin" ]; then
        printf '%s/%s%s%s\n' "${PLUGINS_DIR#"$DOTDOT_ROOT"/}/$plugin" "$origin" "$SYNC_SEPARATOR" "$destination"
      else
        printf '%s%s%s\n' "$origin" "$SYNC_SEPARATOR" "$destination"
      fi
      ;;
  esac
}

# Every "!<destination>" in the sync map, resolved: these are never linked,
# and a link already there is removed.
core.system.sync.service::plan_removals() {
  local plugin origin destination absolute
  while IFS='|' read -r plugin origin destination; do
    [ "$origin" = '!' ] || continue
    if core.system.sync.service::has_parent_segment "$destination" \
      || ! core.system.sync.service::resolve_under "$destination" "$BASE" absolute \
      || ! core.system.sync.service::is_linkable_destination "$absolute"; then
      core.system.sync.service::fail "Removal '!$destination' is not a project path outside dotdot and .git; ignored."
      continue
    fi
    SYNC_REMOVALS+=("$absolute")
    [ -L "$absolute" ] || continue
    core.system.sync.service::add "" "$absolute" "$destination" unlink
  done < <(paths::sync_map_entries "$SYNC_EFFECTIVE_MAP")
}

core.system.sync.service::is_removed() {
  local removal
  for removal in ${SYNC_REMOVALS[@]+"${SYNC_REMOVALS[@]}"}; do
    [ "$removal" != "$1" ] || return 0
  done
  return 1
}

# Every link the sync map names, in its order: a destination keeps its first
# origin.
core.system.sync.service::mappings() {
  local plugin origin destination
  while IFS='|' read -r plugin origin destination; do
    core.system.sync.service::map_link "$plugin" "$origin" "$destination"
  done < <(paths::sync_map_entries "$SYNC_EFFECTIVE_MAP")
}

core.system.sync.service::fail() {
  SYNC_ERRORS+=("$1")
  SYNC_FAILURES=$((SYNC_FAILURES + 1))
}

core.system.sync.service::is_managed() {
  local directory
  for directory in "${SYNC_MANAGED_DIRS[@]}"; do
    framework.helpers.fs::is_inside "$1" "$directory" && [ "$1" != "$directory" ] && return 0
  done
  return 1
}

# <relative> under <anchor>, its directory resolved but not its last part
# (a link stays a link), into the variable named $3; fails outside <anchor>.
core.system.sync.service::resolve_under() {
  local relative="${1%/}" anchor="$2" target="$3" parent name path
  path="$anchor/$relative"
  name="${path##*/}"
  case "$name" in
    '' | . | ..) return 1 ;;
  esac
  framework.helpers.fs::resolve_to parent "${path%/*}" || return 1
  [ "$parent" != / ] || parent=""
  [ "$parent/$name" != "$anchor" ] && framework.helpers.fs::is_inside "$parent/$name" "$anchor" || return 1
  printf -v "$target" '%s' "$parent/$name"
}

core.system.sync.service::add() {
  SYNC_ORIGINS+=("$1")
  SYNC_DESTINATIONS+=("$2")
  SYNC_LABELS+=("$3")
  SYNC_ACTIONS+=("$4")
}

# What to do with a destination, into SYNC_ACTION.
core.system.sync.service::classify() {
  local origin="$1" destination="$2" override="$3" target="" source=""
  if [ -L "$destination" ]; then
    framework.helpers.fs::resolve_to target "$destination" || target=""
    framework.helpers.fs::resolve_to source "$origin" || source=""
  fi
  if [ ! -e "$destination" ] && [ ! -L "$destination" ]; then
    SYNC_ACTION="link"
  elif [ -L "$destination" ] && [ "$target" = "$source" ]; then
    SYNC_ACTION="ok"
  elif [ -L "$destination" ] && core.system.sync.service::is_managed "$target"; then
    SYNC_ACTION="move"
  elif [ -d "$destination" ] && [ ! -L "$destination" ]; then
    SYNC_ACTION="skip"
  elif ! $override; then
    SYNC_ACTION="overridable"
  elif [ -L "$destination" ]; then
    SYNC_ACTION="relink"
  else
    SYNC_ACTION="backup"
  fi
}

# The name of the plugin a path is in, into SYNC_PLUGIN_NAME.
core.system.sync.service::plugin_name() {
  local relative
  case "$1" in
    "$PLUGINS_DIR"/*/*/*) ;;
    *) return 1 ;;
  esac
  relative="${1#"$PLUGINS_DIR"/*/}"
  SYNC_PLUGIN_NAME="${relative%%/*}"
}

core.system.sync.service::is_linked_kind() {
  local kind parent="${1%/*}"
  for kind in "${SYNC_LINKED_KINDS[@]}"; do
    [ "${parent##*/}" != "$kind" ] || return 0
  done
  return 1
}

core.system.sync.service::plan_link() {
  local action name planned
  ! core.system.sync.service::is_removed "$2" || return 0
  if core.system.sync.service::planned_origin "$2"; then
    [ "$SYNC_PLANNED" = "$1" ] \
      || core.system.sync.service::fail "$(dot::relative "$1") clashes with $3, already linked from $(dot::relative "$SYNC_PLANNED"); not linked."
    return
  fi
  if core.system.sync.service::plugin_name "$1" && core.system.sync.service::is_linked_kind "$1"; then
    name="$SYNC_PLUGIN_NAME"
    case "${1##*/}" in
      "$name"-?*) ;;
      *) core.system.sync.service::fail "$(dot::relative "$1") is not named $name-<name>, after its plugin; not linked."; return ;;
    esac
  fi
  core.system.sync.service::classify "$1" "$2" "$4"
  action="$SYNC_ACTION"
  if [ "$action" = overridable ]; then
    action=skip
    SYNC_OVERRIDABLE=$((SYNC_OVERRIDABLE + 1))
  fi
  core.system.sync.service::add "$1" "$2" "$3" "$action"
}

# The origin already planned for a destination, into SYNC_PLANNED.
core.system.sync.service::planned_origin() {
  local index
  for index in ${SYNC_DESTINATIONS[@]+"${!SYNC_DESTINATIONS[@]}"}; do
    if [ "${SYNC_DESTINATIONS[$index]}" = "$1" ]; then
      SYNC_PLANNED="${SYNC_ORIGINS[$index]}"
      return 0
    fi
  done
  return 1
}

core.system.sync.service::is_planned() {
  core.system.sync.service::planned_origin "$1"
}

core.system.sync.service::has_parent_segment() {
  case "/$1/" in
    */../*) return 0 ;;
  esac
  return 1
}

# An origin is one of dotdot's top-level docs, or a file of a module or a
# plugin; never .env or anything else of dotdot's.
core.system.sync.service::is_linkable_origin() {
  case "$1" in
    "$CORE_DIR"/* | "$PLUGINS_DIR"/*) return 0 ;;
    "$DOTDOT_ROOT"/*.md) [ "${1%/*}" = "$DOTDOT_ROOT" ] ;;
    *) return 1 ;;
  esac
}

# A destination is inside the project, outside dotdot, outside git's own
# files, and never the dot entry point.
core.system.sync.service::is_linkable_destination() {
  case "/${1#"$BASE"/}/" in
    */.git/*) return 1 ;;
  esac
  [ "$1" != "$ENTRY_LINK" ] && ! framework.helpers.fs::is_inside "$1" "$DOTDOT_ROOT"
}

core.system.sync.service::plan_mapping() {
  local entry="$1" override="$2" origin destination origin_path tree=false origin_absolute destination_absolute child name
  origin="${entry%%"$SYNC_SEPARATOR"*}"
  destination="${entry#*"$SYNC_SEPARATOR"}"
  case "$origin" in
    @*)
      core.system.sync.service::fail "Unknown shortcut $origin in $(dot::relative "$SYNC_MAP")."
      return
      ;;
  esac
  if [ -z "$origin" ] || [ -z "$destination" ] || [ "$origin" = "$entry" ]; then
    core.system.sync.service::fail "$(dot::relative "$SYNC_MAP") has a line that is not origin$SYNC_MAP_SEPARATOR""destination: $entry"
    return
  fi
  origin_path="$origin"
  if [[ "$origin" == *"$SYNC_TREE_SUFFIX" ]]; then
    tree=true
    origin_path="${origin%"$SYNC_TREE_SUFFIX"}"
  fi
  if core.system.sync.service::has_parent_segment "$origin_path" || core.system.sync.service::has_parent_segment "$destination"; then
    core.system.sync.service::fail "Link '$entry' climbs out with '..'; not linked."
    return
  fi
  core.system.sync.service::resolve_under "$origin_path" "$DOTDOT_ROOT" origin_absolute \
    || { core.system.sync.service::fail "Origin '$origin_path' resolves outside the dotdot directory."; return; }
  core.system.sync.service::resolve_under "$destination" "$BASE" destination_absolute \
    || { core.system.sync.service::fail "Destination '$destination' resolves outside the project directory."; return; }
  core.system.sync.service::is_linkable_origin "$origin_absolute" \
    || { core.system.sync.service::fail "Origin '$origin_path' is not a dotdot doc or a module's or plugin's file; not linked."; return; }
  core.system.sync.service::is_linkable_destination "$destination_absolute" \
    || { core.system.sync.service::fail "Destination '$destination' is inside dotdot or git, or is the dot entry point; not linked."; return; }
  if [ ! -e "$origin_absolute" ] && ! { $SYNC_SEED_USER && [ "$origin_absolute" = "$USER_FILE" ]; }; then
    core.system.sync.service::fail "Origin '$origin_path' does not exist."
    return
  fi
  if $tree && [ ! -d "$origin_absolute" ]; then
    core.system.sync.service::fail "Origin '$origin' uses the '$SYNC_TREE_SUFFIX' tree pattern but is not a directory."
    return
  fi
  if $tree && [ -L "$destination_absolute" ]; then
    core.system.sync.service::fail "Destination '$destination' is a symlink to a directory; remove it if you want dotdot linked there."
    return
  fi
  if ! $tree; then
    core.system.sync.service::plan_link "$origin_absolute" "$destination_absolute" "$destination" "$override"
    return
  fi
  SYNC_TREE_DIRS+=("$destination_absolute")
  while IFS= read -r -d '' child; do
    name="${child##*/}"
    [ "$name" != "$KEEP_FILE" ] || continue
    core.system.sync.service::plan_link "$child" "$destination_absolute/$name" "${destination%/}/$name" "$override"
  done < <(find "$origin_absolute" -mindepth 1 -maxdepth 1 -print0 | sort -z)
}

core.system.sync.service::swept_directories() {
  local destination directory
  {
    for destination in ${SYNC_DESTINATIONS[@]+"${SYNC_DESTINATIONS[@]}"}; do
      printf '%s\0' "${destination%/*}"
    done
    for directory in ${SYNC_TREE_DIRS[@]+"${SYNC_TREE_DIRS[@]}"}; do
      printf '%s\0' "$directory"
    done
  } | sort -zu
}

core.system.sync.service::plan_pruning() {
  local directory link target
  while IFS= read -r -d '' directory; do
    [ -d "$directory" ] && [ ! -L "$directory" ] || continue
    while IFS= read -r -d '' link; do
      [ "$link" != "$ENTRY_LINK" ] || continue
      [ ! -e "$link" ] || continue
      framework.helpers.fs::resolve_to target "$link" && core.system.sync.service::is_managed "$target" || continue
      ! core.system.sync.service::is_planned "$link" || continue
      core.system.sync.service::add "" "$link" "$(dot::relative "$link")" prune
    done < <(find "$directory" -mindepth 1 -maxdepth 1 -type l -print0 | sort -z)
  done < <(core.system.sync.service::swept_directories)
}

core.system.sync.service::plan() {
  local override="$1" refresh="${2-}" entry
  core.system.sync.service::prepare_map "$refresh"
  [ -n "$SYNC_EFFECTIVE_MAP" ] || return 0
  core.system.sync.service::plan_removals
  if [ ! -e "$USER_FILE" ] && [ ! -L "$USER_FILE" ] && [ -f "$USER_EXAMPLE_FILE" ]; then
    SYNC_SEED_USER=true
  fi
  while IFS= read -r entry; do
    core.system.sync.service::plan_mapping "$entry" "$override"
  done < <(core.system.sync.service::mappings)
  core.system.sync.service::plan_pruning
}

core.system.sync.service::is_change() {
  case "$1" in
    link | move | prune | unlink | relink | backup) return 0 ;;
  esac
  return 1
}

core.system.sync.service::count_changes() {
  local action
  SYNC_CHANGES=0
  ! $SYNC_SEED_USER || SYNC_CHANGES=$((SYNC_CHANGES + 1))
  SYNC_CHANGES=$((SYNC_CHANGES + ${#SYNC_MAP_NOTES[@]}))
  for action in ${SYNC_ACTIONS[@]+"${SYNC_ACTIONS[@]}"}; do
    ! core.system.sync.service::is_change "$action" || SYNC_CHANGES=$((SYNC_CHANGES + 1))
  done
}

core.system.sync.service::user_state() {
  if $SYNC_SEED_USER; then
    printf 'create\n'
  elif [ -e "$USER_FILE" ]; then
    printf 'existing\n'
  fi
}

core.system.sync.service::seed() {
  if [ ${#SYNC_MAP_NOTES[@]} -gt 0 ] || [ ! -f "$SYNC_MAP" ]; then
    framework.helpers.fs::write "$SYNC_MAP" < "$SYNC_EFFECTIVE_MAP" || core.system.sync.service::fail "Could not write $(dot::relative "$SYNC_MAP")."
  fi
  if $SYNC_SEED_USER; then
    sed '/^ignore: true$/d' "$USER_EXAMPLE_FILE" > "$USER_FILE" || core.system.sync.service::fail "Could not create $DOTDOT_NAME/USER.md."
  fi
}

core.system.sync.service::apply() {
  local index origin destination label stamp
  stamp=$(framework.helpers.date::stamp)
  core.system.sync.service::seed
  for index in ${SYNC_ACTIONS[@]+"${!SYNC_ACTIONS[@]}"}; do
    origin="${SYNC_ORIGINS[$index]}"
    destination="${SYNC_DESTINATIONS[$index]}"
    label="${SYNC_LABELS[$index]}"
    case "${SYNC_ACTIONS[$index]}" in
      ok) SYNC_UNCHANGED=$((SYNC_UNCHANGED + 1)); continue ;;
      skip) SYNC_SKIPPED=$((SYNC_SKIPPED + 1)); continue ;;
      prune | unlink)
        if rm -f -- "$destination"; then SYNC_REMOVED=$((SYNC_REMOVED + 1)); else core.system.sync.service::fail "Could not remove $label."; fi
        continue
        ;;
      move) rm -f -- "$destination" ;;
      relink)
        SYNC_WARNINGS+=("replaced symlink $label (was -> $(readlink -- "$destination"))")
        rm -f -- "$destination"
        ;;
      backup)
        mv -- "$destination" "$destination.bak-$stamp"
        SYNC_WARNINGS+=("backed up $label -> $label.bak-$stamp")
        ;;
    esac
    if framework.helpers.fs::link "$origin" "$destination"; then
      SYNC_LINKED=$((SYNC_LINKED + 1))
    else
      core.system.sync.service::fail "Could not link $label (symlinks may need Developer Mode on Windows)."
    fi
  done
}
