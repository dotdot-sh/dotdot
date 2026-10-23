#!/usr/bin/env bash
# description: Delete a task for good, after a confirmation at a terminal.

set -euo pipefail

. "$(dirname "$0")/lib/dot-paths.sh"
. "$(dirname "$0")/lib/dot-kv.sh"
. "$(dirname "$0")/lib/dot-tasks.sh"
. "$(dirname "$0")/lib/dot-confirm.sh"

usage() {
  cat <<USAGE
bash dot task:delete — delete a task for good. It asks for confirmation at
a terminal (piped input is refused), so only a person can delete; moving a
task to done or discarded (bash dot task:update <id> --done) is the usual
way to end it.

Usage:
  bash dot task:delete <id>
  bash dot task:delete --help
USAGE
}

case "${1-}" in -h | --help) usage; exit 0 ;; esac
check_id "${1-}"
[ $# -eq 1 ] || die "task:delete takes one task id"
[ -t 0 ] || die "Deleting needs a confirmation at a terminal; ask the user to run bash dot task:delete $1."
ensure_service

svc show "$1" > "$TMP/show" || exit 1
title=$(head -n 1 "$TMP/show" | cut -f 5)
confirm "Delete task $1 \"$title\"? This can't be undone." || { echo "Aborted — nothing deleted."; exit 1; }
svc delete "$1" || exit 1
printf '%s✅ Task %s deleted%s\n' "$GREEN" "$1" "$RESET"
