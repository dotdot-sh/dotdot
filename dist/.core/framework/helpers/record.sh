#!/usr/bin/env bash

RECORD_SEPARATOR="--"
RECORD_DIGITS=3
RECORD_EXTENSION=".md"

framework.helpers.record::number() {
  printf '%s' "$1" | sed -n 's/^[A-Za-z_]*\([0-9][0-9]*\).*/\1/p'
}

framework.helpers.record::pad() {
  local number
  number=$(printf '%s' "$1" | sed 's/^0*//')
  printf "%0${RECORD_DIGITS}d" "${number:-0}"
}

framework.helpers.record::normalize() {
  local number
  number=$(printf '%s' "$1" | sed -n 's/[^0-9]*\([0-9][0-9]*\).*/\1/p')
  [ -n "$number" ] || return 1
  framework.helpers.record::pad "$number"
}

framework.helpers.record::files() {
  local directory="$1" prefix="$2" file
  for file in "$directory/$prefix"[0-9]*"$RECORD_SEPARATOR"*"$RECORD_EXTENSION"; do
    [ -f "$file" ] && printf '%s\n' "$file"
  done
  return 0
}

framework.helpers.record::next_number() {
  local directory="$1" prefix="$2" highest=0 file number
  while IFS= read -r file; do
    number=$(framework.helpers.record::number "$(basename -- "$file")" | sed 's/^0*//')
    [ "${number:-0}" -le "$highest" ] || highest=$number
  done < <(framework.helpers.record::files "$directory" "$prefix")
  framework.helpers.record::pad $((highest + 1))
}

framework.helpers.record::next_path() {
  local directory="$1" prefix="$2" slug="$3" path
  mkdir -p -- "$directory" || return 1
  path="$directory/$prefix$(framework.helpers.record::next_number "$directory" "$prefix")$RECORD_SEPARATOR$slug$RECORD_EXTENSION"
  [ ! -e "$path" ] || return 1
  printf '%s\n' "$path"
}

framework.helpers.record::find() {
  local directory="$1" prefix="$2" reference="$3" number file
  number=$(framework.helpers.record::normalize "$reference") || return 1
  for file in "$directory/$prefix$number$RECORD_SEPARATOR"*"$RECORD_EXTENSION"; do
    if [ -e "$file" ]; then
      basename -- "$file"
      return 0
    fi
  done
  return 1
}

framework.helpers.record::link() {
  local prefix="$1" file="$2"
  printf '[%s%s](%s)' "$prefix" "$(framework.helpers.record::number "$file")" "$file"
}

framework.helpers.record::id() {
  local prefix="$1" file="$2"
  printf '%s%s' "$prefix" "$(framework.helpers.record::number "$(basename -- "$file")")"
}
