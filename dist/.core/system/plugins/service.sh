#!/usr/bin/env bash

dot::use core.system.plugins.context core.system.plugins.manifest framework.helpers.fs framework.helpers.kv \
  framework.integrations.github-api.service framework.integrations.github-cli.service

PLUGIN_STUB_DIR="$SYSTEM_DIR/plugins/stubs/plugin"
PLUGIN_STUB_OWNER="__OWNER__"
PLUGIN_STUB_NAME="__NAME__"
PLUGIN_STUB_API="__API__"
PLUGIN_STUB_SUFFIX=".stub"
PLUGIN_PATH_SOURCE="path:"
PLUGIN_GITHUB_SOURCE="github:"
PLUGIN_DEFAULT_REF="main"
PLUGIN_LOCAL_REF="-"
PLUGINS_WORKSPACE=""

core.system.plugins.service::prepare_workspace() {
  [ -n "${PLUGINS_WORKSPACE-}" ] || framework.helpers.fs::make_temp_dir PLUGINS_WORKSPACE || dot::abort "Could not create a temp directory."
  rm -rf -- "${PLUGINS_WORKSPACE:?}"/*
}

core.system.plugins.service::download() {
  local repository="$1" ref="$2" file="$3"
  if framework.integrations.github-cli.service::is_authenticated; then
    framework.integrations.github-cli.service::tarball "$repository" "$ref" "$file"
  else
    framework.integrations.github-api.service::tarball "$repository" "$ref" "$file"
  fi
}

core.system.plugins.service::plugin_root() {
  local repository_root="$1" plugin="$2"
  [ -d "$repository_root/$PLUGIN_ROOT" ] || { dot::raise "$plugin has no $PLUGIN_ROOT/ folder, so it is not a dotdot plugin."; return 1; }
  printf '%s\n' "$repository_root/$PLUGIN_ROOT"
}

core.system.plugins.service::fetch_github() {
  local plugin="$1" ref="$2" top
  framework.integrations.github-api.service::is_ref "$ref" || { dot::raise "Invalid ref: $ref"; return 1; }
  core.system.plugins.service::download "$plugin" "$ref" "$PLUGINS_WORKSPACE/plugin.tar.gz" \
    || { dot::raise "Could not download $plugin@$ref (private? log in with gh auth login or set GH_TOKEN in $(dot::relative "$ENV_FILE"))."; return 1; }
  mkdir -p -- "$PLUGINS_WORKSPACE/tree"
  tar -xzf "$PLUGINS_WORKSPACE/plugin.tar.gz" -C "$PLUGINS_WORKSPACE/tree" || { dot::raise "Could not unpack $plugin@$ref."; return 1; }
  top=$(find "$PLUGINS_WORKSPACE/tree" -mindepth 1 -maxdepth 1 -type d | head -n 1)
  [ -n "$top" ] || { dot::raise "$plugin@$ref is empty."; return 1; }
  PLUGIN_SOURCE=$(core.system.plugins.service::plugin_root "$top" "$plugin") || return 1
  PLUGIN_COMMIT=$(framework.integrations.github-api.service::tarball_commit "$PLUGINS_WORKSPACE/plugin.tar.gz")
  PLUGIN_ORIGIN="$PLUGIN_GITHUB_SOURCE$plugin"
  PLUGIN_REF="$ref"
}

core.system.plugins.service::fetch_path() {
  local plugin="$1" path="$2" root
  root=$(framework.helpers.fs::within "$path" "$BASE") || { dot::raise "A local plugin must be inside the project: $path"; return 1; }
  [ -d "$root" ] || { dot::raise "Not a directory: $path"; return 1; }
  PLUGIN_SOURCE=$(core.system.plugins.service::plugin_root "$root" "$plugin") || return 1
  PLUGIN_COMMIT="$PLUGIN_LOCAL_REF"
  PLUGIN_ORIGIN="$PLUGIN_PATH_SOURCE$(dot::relative "$root")"
  PLUGIN_REF="$PLUGIN_LOCAL_REF"
}

core.system.plugins.service::fetch() {
  local plugin="$1" ref="$2" path="${3-}"
  core.system.plugins.service::prepare_workspace
  if [ -n "$path" ]; then
    core.system.plugins.service::fetch_path "$plugin" "$path"
  else
    core.system.plugins.service::fetch_github "$plugin" "${ref:-$PLUGIN_DEFAULT_REF}"
  fi
}

core.system.plugins.service::files() {
  (cd -- "$1" && find . -type f | sed 's|^\./||' | sort)
}

core.system.plugins.service::changed_files() {
  local plugin="$1" source="$2" installed file
  installed=$(core.system.plugins.manifest::directory "$plugin")
  while IFS= read -r file; do
    if [ ! -e "$installed/$file" ]; then
      printf 'added\t%s\n' "$file"
    elif ! cmp -s -- "$source/$file" "$installed/$file"; then
      printf 'changed\t%s\n' "$file"
    fi
  done < <(core.system.plugins.service::files "$source")
  [ -d "$installed" ] || return 0
  while IFS= read -r file; do
    [ -e "$source/$file" ] || printf 'removed\t%s\n' "$file"
  done < <(core.system.plugins.service::files "$installed")
}

core.system.plugins.service::preview() {
  local plugin="$1" source="$2" file destination state entry key
  while IFS= read -r file; do
    destination=$(core.system.plugins.context::destination "$plugin" "$file") || return 1
    state="new file"
    if [ -e "$DOTDOT_ROOT/$destination" ]; then
      state=$(core.system.plugins.context::state "$DOTDOT_ROOT/$destination" "$plugin" "$file") || return 1
      [ "$state" = region ] && state="replace region" || state="append region"
    fi
    printf 'context\t%s/%s\t%s/%s\t%s\n' "$PLUGIN_CONTEXT_DIR" "$file" "$DOTDOT_NAME" "$destination" "$state"
  done < <(core.system.plugins.context::files "$source")
  while IFS=$'\t' read -r state entry; do
    printf 'file\t%s\t%s\n' "$entry" "$state"
  done < <(core.system.plugins.service::changed_files "$plugin" "$source")
  while IFS= read -r file; do
    printf 'stub\t%s\n' "$file"
  done < <(core.system.plugins.service::stubs "$source")
  for key in "$PLUGIN_HARNESS_SKILLS_KEY" "$PLUGIN_HARNESS_AGENTS_KEY"; do
    entry=$(core.system.plugins.manifest::value "$source" "$key")
    [ -z "$entry" ] || printf 'harness\t%s\t%s\n' "$key" "$entry"
  done
  while IFS= read -r entry; do
    printf 'link\t%s\t%s\n' "${entry%%"$PLUGIN_LIST_SEPARATOR"*}" "${entry#*"$PLUGIN_LIST_SEPARATOR"}"
  done < <(core.system.plugins.manifest::list "$source" "$PLUGIN_LINKS_KEY")
  while IFS= read -r entry; do
    printf 'missing\t%s\n' "$entry"
  done < <(core.system.plugins.manifest::missing_dependencies "$source")
}

core.system.plugins.service::install() {
  local plugin="$1" source="$2" destination directory
  destination=$(core.system.plugins.manifest::directory "$plugin")
  rm -rf -- "$destination"
  mkdir -p -- "$destination"
  (cd -- "$source" && tar -cf - .) | (cd -- "$destination" && tar -xf -) \
    || { dot::raise "Could not copy $plugin into $(dot::relative "$destination")."; return 1; }
  while IFS= read -r directory; do
    [ -d "$DOTDOT_ROOT/$directory" ] && continue
    mkdir -p -- "$DOTDOT_ROOT/$directory" && : > "$DOTDOT_ROOT/$directory/$KEEP_FILE"
  done < <(core.system.plugins.manifest::list "$destination" "$PLUGIN_DIRECTORIES_KEY")
}

core.system.plugins.service::stubs() {
  local source="$1/$PLUGIN_STUBS_DIR"
  [ -d "$source" ] || return 0
  (cd -- "$source" && find . -type f -name "*$PLUGIN_STUB_SUFFIX" | sed 's|^\./||' | sort)
}

core.system.plugins.service::stub_target() {
  local stub="$1"
  if [ "$stub" = "$PLUGIN_ENV_STUB" ]; then
    printf '%s\n' "$ENV_FILE"
  else
    printf '%s\n' "$BASE/${stub%"$PLUGIN_STUB_SUFFIX"}"
  fi
}

core.system.plugins.service::missing_settings() {
  local key
  while IFS= read -r key; do
    framework.helpers.kv::value "$ENV_FILE" "$key" >/dev/null 2>&1 || printf '%s\n' "$key"
  done < <(framework.helpers.kv::keys "$1")
}

core.system.plugins.service::seed_settings() {
  local stub="$1" missing
  missing=$(core.system.plugins.service::missing_settings "$stub")
  [ -n "$missing" ] || return 0
  (
    [ ! -s "$ENV_FILE" ] || [ -z "$(tail -c 1 -- "$ENV_FILE")" ] || printf '\n'
    if [ "$missing" = "$(framework.helpers.kv::keys "$stub")" ]; then
      cat -- "$stub"
    else
      awk -v wanted="$missing" '
        BEGIN { count = split(wanted, keys, "\n"); for (i = 1; i <= count; i++) missing[keys[i]] = 1 }
        {
          line = $0; sub(/^[ \t]*(export[ \t]+)?/, "", line)
          split_at = index(line, "="); key = substr(line, 1, split_at - 1); sub(/[ \t]+$/, "", key)
          if (split_at > 0 && (key in missing) && !seen[key]++) print
        }
      ' "$stub"
    fi
  ) >> "$ENV_FILE"
  chmod 600 "$ENV_FILE"
  printf 'appended\t%s\n' "$(dot::relative "$ENV_FILE")"
}

core.system.plugins.service::seed() {
  local source="$1" stub target
  while IFS= read -r stub; do
    target=$(core.system.plugins.service::stub_target "$stub")
    if [ "$target" = "$ENV_FILE" ]; then
      core.system.plugins.service::seed_settings "$source/$PLUGIN_STUBS_DIR/$stub"
    elif [ -e "$target" ] || [ -L "$target" ]; then
      printf 'kept\t%s\n' "$(dot::relative "$target")"
    else
      mkdir -p -- "$(dirname -- "$target")" && cp -- "$source/$PLUGIN_STUBS_DIR/$stub" "$target"
      printf 'created\t%s\n' "$(dot::relative "$target")"
    fi
  done < <(core.system.plugins.service::stubs "$source")
}

core.system.plugins.service::is_empty_directory() {
  [ -z "$(find "$1" -mindepth 1 ! -name "$KEEP_FILE" -print -quit)" ]
}

core.system.plugins.service::uninstall() {
  local plugin="$1" directory record stub target
  directory=$(core.system.plugins.manifest::directory "$plugin")
  while IFS= read -r record; do
    [ -d "$DOTDOT_ROOT/$record" ] || continue
    if core.system.plugins.service::is_empty_directory "$DOTDOT_ROOT/$record"; then
      rm -rf -- "${DOTDOT_ROOT:?}/$record"
      printf 'removed\t%s\n' "$(dot::relative "$DOTDOT_ROOT/$record")"
    else
      printf 'kept\t%s\n' "$(dot::relative "$DOTDOT_ROOT/$record")"
    fi
  done < <(core.system.plugins.manifest::list "$directory" "$PLUGIN_DIRECTORIES_KEY")
  while IFS= read -r stub; do
    target=$(core.system.plugins.service::stub_target "$stub")
    [ "$target" = "$ENV_FILE" ] || [ ! -e "$target" ] || printf 'left\t%s\n' "$(dot::relative "$target")"
  done < <(core.system.plugins.service::stubs "$directory")
  ! framework.helpers.kv::keys "$ENV_FILE" | grep "^$(dot::config_prefix "$plugin")" >/dev/null \
    || printf 'left\t%s\n' "$(dot::relative "$ENV_FILE") ($(dot::config_prefix "$plugin")* settings)"
  rm -rf -- "${directory:?}"
  rmdir -- "$(dirname -- "$directory")" 2>/dev/null || true
}

core.system.plugins.service::scaffold() {
  local plugin="$1" directory="$2" path file owner name
  owner=$(core.system.plugins.manifest::owner "$plugin")
  name="${plugin#*/}"
  mkdir -p -- "$directory" && cp -R -- "$PLUGIN_STUB_DIR" "$directory/$PLUGIN_ROOT" || return 1
  while IFS= read -r path; do
    mv -- "$path" "$(dirname -- "$path")/$(basename -- "$path" | sed "s/$PLUGIN_STUB_OWNER/$owner/g; s/$PLUGIN_STUB_NAME/$name/g")"
  done < <(find "$directory" -depth \( -name "*$PLUGIN_STUB_OWNER*" -o -name "*$PLUGIN_STUB_NAME*" \))
  while IFS= read -r file; do
    sed "s/$PLUGIN_STUB_OWNER/$owner/g; s/$PLUGIN_STUB_NAME/$name/g; s/$PLUGIN_STUB_API/$PLUGIN_API/g" "$file" | framework.helpers.fs::replace "$file"
  done < <(find "$directory" -type f)
}
