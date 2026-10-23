#!/usr/bin/env bash
# description: Move a task to todo.

set -euo pipefail

case "${1-}" in
  -h | --help)
    cat <<USAGE
bash dot task:todo — move a task to todo, in whichever service keeps the tasks.
The same as bash dot task:update <id> --todo.

Usage:
  bash dot task:todo <id>
  bash dot task:todo --help

<id> is what bash dot task:list shows (t004, #12).
USAGE
    exit 0
    ;;
esac
[ $# -eq 1 ] || { echo "❌ task:todo takes one task id (see bash dot task:list)." >&2; exit 1; }
exec bash "$(dirname -- "$0")/dot-task-update.sh" "$1" --todo
