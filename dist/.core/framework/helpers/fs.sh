#!/usr/bin/env bash

FS_MAX_LINK_HOPS=40

framework.helpers.fs::resolve() {
  local fs_resolved
  framework.helpers.fs::resolve_to fs_resolved "$1" || return 1
  printf '%s\n' "$fs_resolved"
}

# resolve, into the variable named $1 rather than printed: no subshell.
framework.helpers.fs::resolve_to() {
  local fs_target="$1" pending="$2" resolved="" part link hops=0
  case "$pending" in
    /*) ;;
    *) pending="$PWD/$pending" ;;
  esac
  while [ -n "$pending" ]; do
    part="${pending%%/*}"
    if [ "$part" = "$pending" ]; then
      pending=""
    else
      pending="${pending#*/}"
    fi
    case "$part" in
      "" | .) continue ;;
      ..) resolved="${resolved%/*}"; continue ;;
    esac
    if [ ! -L "$resolved/$part" ]; then
      resolved="$resolved/$part"
      continue
    fi
    hops=$((hops + 1))
    [ "$hops" -le "$FS_MAX_LINK_HOPS" ] || return 1
    link=$(readlink "$resolved/$part") || return 1
    case "$link" in
      /*) resolved="" ;;
    esac
    pending="$link/$pending"
  done
  printf -v "$fs_target" '%s' "${resolved:-/}"
}

framework.helpers.fs::relative() {
  local target from up="" rest="" path
  target=$(framework.helpers.fs::resolve "$1") || return 1
  from=$(framework.helpers.fs::resolve "$2") || return 1
  [ "$target" != / ] || target=""
  [ "$from" != / ] || from=""
  while [ "$target" != "$from" ] && [ "${target#"$from"/}" = "$target" ]; do
    from="${from%/*}"
    up="../$up"
  done
  [ "$target" = "$from" ] || rest="${target#"$from"/}"
  path="$up$rest"
  path="${path%/}"
  printf '%s\n' "${path:-.}"
}

framework.helpers.fs::is_inside() {
  [ "$1" = "$2" ] || [ "${1#"$2"/}" != "$1" ]
}

framework.helpers.fs::within() {
  local path="$1" anchor="$2" resolved
  case "$path" in
    /*) ;;
    *) path="$anchor/$path" ;;
  esac
  resolved=$(framework.helpers.fs::resolve "$path") || return 1
  framework.helpers.fs::is_inside "$resolved" "$anchor" || return 1
  printf '%s\n' "$resolved"
}

framework.helpers.fs::make_temp_dir() {
  local fs_temp_target="$1" fs_temp_path
  fs_temp_path=$(mktemp -d) || return 1
  dot::on_exit "rm -rf -- $(printf '%q' "$fs_temp_path")"
  printf -v "$fs_temp_target" '%s' "$fs_temp_path"
}

framework.helpers.fs::write() {
  local file="$1" partial
  partial="$file.dot-$$"
  if cat > "$partial" && mv -f -- "$partial" "$file"; then
    return 0
  fi
  rm -f -- "$partial"
  return 1
}

framework.helpers.fs::replace() {
  local file="$1" partial
  partial="$file.dot-$$"
  if cp -p -- "$file" "$partial" 2>/dev/null && cat > "$partial" && mv -f -- "$partial" "$file"; then
    return 0
  fi
  rm -f -- "$partial"
  return 1
}

framework.helpers.fs::link() {
  local target="$1" link="$2" directory
  directory=$(dirname -- "$link")
  mkdir -p -- "$directory" || return 1
  ln -s -- "$(framework.helpers.fs::relative "$target" "$directory")" "$link" || return 1
  [ -L "$link" ]
}

framework.helpers.fs::prune_empty_parents() {
  local directory stop="$2"
  directory=$(dirname -- "$1")
  while [ "$directory" != "$stop" ] && rmdir -- "$directory" 2>/dev/null; do
    directory=$(dirname -- "$directory")
  done
}
