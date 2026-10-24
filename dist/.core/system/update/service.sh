#!/usr/bin/env bash

dot::use framework.helpers.fs framework.helpers.text

UPDATE_REPOSITORY_URL="https://github.com/dotdot-sh/dotdot.git"
UPDATE_BRANCH="main"
UPDATE_SOURCE="dist"
UPDATE_TREES=("$(basename -- "$CORE_DIR")")
UPDATE_LOCAL_FILES=("$VERSION_FILE" "$READY_FILE")
UPDATE_COMMIT_PATTERN='^[0-9a-f]{40}([0-9a-f]{24})?$'
UPDATE_NEW_REF="refs/dotdot/new"
UPDATE_OLD_REF="refs/dotdot/old"
UPDATE_DEFAULT_NAME=".dot"

UPDATE_ADDED=()
UPDATE_UPDATED=()
UPDATE_REMOVED=()
UPDATE_EDITED=()
UPDATE_UNKNOWN=()
UPDATE_UNCHANGED=0
UPDATE_FAILURES=()

core.system.update.service::git() {
  git -c core.fsmonitor=false -c core.hooksPath=/dev/null -c protocol.allow=never -c protocol.https.allow=always \
    -C "$UPDATE_REPOSITORY" "$@"
}

core.system.update.service::installed_commit() {
  local commit
  [ -f "$VERSION_FILE" ] || return 0
  commit=$(tr -d '[:space:]' < "$VERSION_FILE")
  [[ "$commit" =~ $UPDATE_COMMIT_PATTERN ]] || dot::abort "$(dot::relative "$VERSION_FILE") does not hold a commit hash."
  printf '%s\n' "$commit"
}

core.system.update.service::download() {
  local old="$1" repository="$UPDATE_REPOSITORY_URL" branch="$UPDATE_BRANCH"
  git init -q -- "$UPDATE_REPOSITORY"
  GIT_TERMINAL_PROMPT=0 core.system.update.service::git fetch -q --depth 1 --no-tags "$repository" "+refs/heads/$branch:$UPDATE_NEW_REF"
  [ -z "$old" ] || GIT_TERMINAL_PROMPT=0 core.system.update.service::git fetch -q --depth 1 --no-tags "$repository" "+$old:$UPDATE_OLD_REF" || true
}

core.system.update.service::has_commit() {
  core.system.update.service::git rev-parse -q --verify "$1^{commit}" >/dev/null
}

core.system.update.service::summary() {
  core.system.update.service::git log -1 --format='%h %s' "$1"
}

core.system.update.service::pathspecs() {
  local source="$1" tree
  for tree in "${UPDATE_TREES[@]}"; do
    printf ':(literal)%s/%s\n' "$source" "$tree"
  done
}

core.system.update.service::renamed() {
  if [ "$DOTDOT_NAME" = "$UPDATE_DEFAULT_NAME" ]; then
    cat
  else
    sed "s|\\$UPDATE_DEFAULT_NAME/|$(framework.helpers.text::escape_replacement "$DOTDOT_NAME/")|g"
  fi
}

core.system.update.service::extract() {
  local commit="$1" source="$2" destination="$3" file pathspecs=()
  while IFS= read -r file; do
    pathspecs+=("$file")
  done < <(core.system.update.service::pathspecs "$source")
  mkdir -p -- "$destination"
  core.system.update.service::git archive --format=tar "$commit" -- "${pathspecs[@]}" | tar -x -C "$destination" || return 1
  [ "$DOTDOT_NAME" != "$UPDATE_DEFAULT_NAME" ] || return 0
  grep -rl --null --binary-files=without-match -F "$UPDATE_DEFAULT_NAME/" "$destination" \
    | while IFS= read -r -d '' file; do
        core.system.update.service::renamed < "$file" > "$file.renamed" && cat "$file.renamed" > "$file" && rm -f -- "$file.renamed"
      done
}

core.system.update.service::is_local_file() {
  local file
  for file in "${UPDATE_LOCAL_FILES[@]}"; do
    [ "$DOTDOT_ROOT/$1" != "$file" ] || return 0
  done
  return 1
}

core.system.update.service::tree_files() {
  local root="$1" tree
  for tree in "${UPDATE_TREES[@]}"; do
    [ -d "$root/$tree" ] || continue
    (cd -- "$root" && find "$tree" \( -type f -o -type l \) -print0)
  done | sort -z
}

core.system.update.service::compare() {
  local tree="$1" relative
  while IFS= read -r -d '' relative; do
    if [ ! -e "$DOTDOT_ROOT/$relative" ] && [ ! -L "$DOTDOT_ROOT/$relative" ]; then
      UPDATE_ADDED+=("$relative")
    elif [ -L "$tree/$relative" ] || [ -L "$DOTDOT_ROOT/$relative" ] || ! cmp -s -- "$tree/$relative" "$DOTDOT_ROOT/$relative"; then
      UPDATE_UPDATED+=("$relative")
    else
      UPDATE_UNCHANGED=$((UPDATE_UNCHANGED + 1))
    fi
  done < <(core.system.update.service::tree_files "$tree")
}

core.system.update.service::find_removed() {
  local old="$1" new="$2" source="$3" path relative destination pathspecs=() spec
  while IFS= read -r spec; do
    pathspecs+=("$spec")
  done < <(core.system.update.service::pathspecs "$source")
  while IFS= read -r -d '' path; do
    relative="${path#"$source"/}"
    [ "$relative" != "$path" ] || continue
    ! core.system.update.service::is_local_file "$relative" || continue
    destination=$(framework.helpers.fs::within "$relative" "$DOTDOT_ROOT") || continue
    [ -e "$destination" ] || [ -L "$destination" ] || continue
    if [ ! -L "$destination" ] && core.system.update.service::git show "$old:$path" | core.system.update.service::renamed | cmp -s - "$destination"; then
      UPDATE_REMOVED+=("$relative")
    else
      UPDATE_EDITED+=("$relative")
    fi
  done < <(core.system.update.service::git diff -z --no-renames --diff-filter=D --name-only "$old" "$new" -- "${pathspecs[@]}")
}

core.system.update.service::find_unknown() {
  local tree="$1" relative
  while IFS= read -r -d '' relative; do
    ! core.system.update.service::is_local_file "$relative" || continue
    [ -e "$tree/$relative" ] || [ -L "$tree/$relative" ] || UPDATE_UNKNOWN+=("$relative")
  done < <(core.system.update.service::tree_files "$DOTDOT_ROOT")
}

core.system.update.service::copy() {
  local tree="$1" relative destination partial
  for relative in ${UPDATE_ADDED[@]+"${UPDATE_ADDED[@]}"} ${UPDATE_UPDATED[@]+"${UPDATE_UPDATED[@]}"}; do
    destination="$DOTDOT_ROOT/$relative"
    partial="$destination.dot-update-$$"
    if [ ! -d "$destination" ] || [ -L "$destination" ]; then
      if mkdir -p -- "$(dirname -- "$destination")" && cp -P -p -- "$tree/$relative" "$partial" && mv -f -- "$partial" "$destination"; then
        continue
      fi
    fi
    rm -f -- "$partial"
    UPDATE_FAILURES+=("Could not copy $relative.")
  done
  for relative in ${UPDATE_REMOVED[@]+"${UPDATE_REMOVED[@]}"}; do
    if rm -f -- "$DOTDOT_ROOT/$relative"; then
      framework.helpers.fs::prune_empty_parents "$DOTDOT_ROOT/$relative" "$DOTDOT_ROOT"
    else
      UPDATE_FAILURES+=("Could not remove $relative.")
    fi
  done
  [ ${#UPDATE_FAILURES[@]} -eq 0 ]
}

core.system.update.service::record_version() {
  mkdir -p -- "$(dirname -- "$VERSION_FILE")" && printf '%s\n' "$1" | framework.helpers.fs::write "$VERSION_FILE"
}
