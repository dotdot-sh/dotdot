#!/usr/bin/env bash

DESCRIPTION="Create a new, empty note in Notes/ with the next number."

dot::use framework.console.args core.modules.notes.service framework.console.output framework.helpers.text

usage() {
  cat <<EOF
bash dot notes:create — create a new, empty note file in Notes/, numbering
and naming it automatically.

It scans Notes/ for the highest existing number and takes the next one —
which is why the filename and number are never to be constructed by hand.
The file is created empty; write the note into it afterwards.

Usage:
  bash dot notes:create [--slug <text>]
  bash dot notes:create --help

Optional:
  --slug <text>   Short name for the file, turned into a slug ("Cache idea"
                  becomes "cache-idea"). Defaults to "$NOTE_DEFAULT_SLUG".

Examples:
  bash dot notes:create
    → Notes/${NOTE_PREFIX}004${RECORD_SEPARATOR}$NOTE_DEFAULT_SLUG.md
  bash dot notes:create --slug "Cache idea"
    → Notes/${NOTE_PREFIX}004${RECORD_SEPARATOR}cache-idea.md
EOF
}

handle() {
  local name="$NOTE_DEFAULT_SLUG" slug path
  while [ $# -gt 0 ]; do
    case "$1" in
      --slug) framework.console.args::require_value "$@"; name="$2"; shift 2 ;;
      *) framework.console.args::unexpected "$1" ;;
    esac
  done
  slug=$(framework.helpers.text::slug "$name")
  [ -n "$slug" ] || framework.console.args::invalid "--slug must contain at least one letter or number."
  path=$(core.modules.notes.service::create "$slug") || framework.console.output::fail "Could not create the note; try again."
  framework.console.output::success "Note $(framework.helpers.record::number "$(basename -- "$path")") created"
  framework.console.output::detail "$(dot::relative "$path")"
}
