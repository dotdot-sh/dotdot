#!/usr/bin/env bash

dot::use framework.console.output framework.helpers.text

framework.console.args::require_value() {
  [ $# -ge 2 ] || framework.console.args::invalid "$1 requires a value."
}

framework.console.args::invalid() {
  framework.console.output::error "$1"
  framework.console.output::detail "Run bash dot ${DOT_COMMAND:-} --help for its usage." >&2
  exit 1
}

framework.console.args::unexpected() {
  framework.console.args::invalid "Unexpected argument: $1"
}

framework.console.args::is_number() {
  [[ "$1" =~ ^[0-9]+$ ]]
}

framework.console.args::split() {
  local value="$1" item
  local items=()
  IFS=',' read -r -a items <<< "$value"
  for item in ${items[@]+"${items[@]}"}; do
    item=$(framework.helpers.text::trim "$item")
    [ -z "$item" ] || printf '%s\n' "$item"
  done
}
