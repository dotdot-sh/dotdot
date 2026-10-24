#!/usr/bin/env bash

dot::use framework.console.output

PROMPT_YES_PATTERN='^[Yy]([Ee][Ss])?$'

framework.console.prompt::can_ask() {
  [ -t 0 ]
}

framework.console.prompt::is_interactive() {
  [ -t 0 ] && [ -t 1 ]
}

framework.console.prompt::confirm() {
  local question="$1" default="${2:-n}" hint="[y/N]" reply=""
  [ "$default" != y ] || hint="[Y/n]"
  framework.console.prompt::can_ask || return 1
  read -r -p "$question $hint " reply || return 1
  [[ ${reply:-$default} =~ $PROMPT_YES_PATTERN ]]
}

framework.console.prompt::confirm_or_abort() {
  local question="$1" default="${2:-n}" command="${3:-the command}"
  framework.console.prompt::confirm "$question" "$default" && return 0
  if framework.console.prompt::can_ask; then
    framework.console.output::aborted
  else
    framework.console.output::aborted "Confirmation needs a terminal; run $command yourself."
  fi
  return 1
}

framework.console.prompt::confirm_or_exit() {
  framework.console.prompt::confirm_or_abort "$@" || exit 1
}

framework.console.prompt::ask() {
  local question="$1" default="${2-}" reply=""
  framework.console.prompt::can_ask || return 1
  read -r -p "$question${default:+ [$default]}: " reply || reply=""
  printf '%s\n' "${reply:-$default}"
}

framework.console.prompt::secret() {
  local question="$1" reply=""
  framework.console.prompt::can_ask || return 1
  read -r -s -p "$question: " reply || reply=""
  printf '\n' >&2
  printf '%s' "$reply"
}

framework.console.prompt::choice() {
  local question="$1" option
  shift
  framework.console.prompt::can_ask || return 1
  framework.console.output::title "$question" >&2
  PS3="Choose 1-$# (Ctrl-D to cancel): "
  select option in "$@"; do
    if [ -n "$option" ]; then
      printf '%s\n' "$REPLY"
      return 0
    fi
    framework.console.output::line "Pick a number from the list." >&2
  done
  return 1
}
