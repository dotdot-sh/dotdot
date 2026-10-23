#!/usr/bin/env bash
# dot-confirm.sh — the one way dotdot asks a person to confirm.
#
# Only a person at a terminal can answer: when stdin is not a terminal the
# answer is no, without asking, so no agent or script approves anything on
# anyone's behalf.
#
# Source it from a script in .dot/.tooling/bin:
#   . "$(dirname "$0")/lib/dot-confirm.sh"

# Asks question $1 at a terminal and succeeds on yes. $2 is what an empty
# reply means: "y" for [Y/n], or "n" for [y/N], the default.
confirm() {
  local default=${2:-n} hint="[y/N]" reply=""
  [ "$default" != y ] || hint="[Y/n]"
  [ -t 0 ] || return 1
  read -r -p "$1 $hint " reply || return 1
  [[ ${reply:-$default} =~ ^[Yy]([Ee][Ss])?$ ]]
}

# Asks question $1 as confirm() does, with default $2, and on no says that
# nothing changed and fails. $3 names the command for the message shown when
# there is no terminal to ask on.
confirm_or_abort() {
  confirm "$1" "${2:-n}" && return 0
  if [ -t 0 ]; then
    echo "Aborted — nothing changed." >&2
  else
    echo "Aborted — nothing changed. Confirmation needs a terminal; run ${3:-the command} yourself." >&2
  fi
  return 1
}

# As confirm_or_abort(), but exits on no.
confirm_or_exit() {
  confirm_or_abort "$@" || exit 1
}
