#!/usr/bin/env bash

dot::use framework.helpers.record framework.helpers.text

NOTE_DEFAULT_SLUG="template"

core.modules.notes.service::create() {
  local slug="$1" path
  path=$(framework.helpers.record::next_path "$NOTES_DIR" "$NOTE_PREFIX" "$slug") || return 1
  : > "$path" || return 1
  printf '%s\n' "$path"
}
