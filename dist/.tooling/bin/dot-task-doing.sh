#!/usr/bin/env bash
# description: Move a task to doing.

set -euo pipefail

case "${1-}" in
  -h | --help)
    cat <<USAGE
bash dot task:doing — move a task to doing, in whichever service keeps the tasks.
The same as bash dot task:update <id> --doing.

Usage:
  bash dot task:doing <id>
  bash dot task:doing --help

<id> is what bash dot task:list shows (t004, #12).
USAGE
    exit 0
    ;;
esac
[ $# -eq 1 ] || { echo "❌ task:doing takes one task id (see bash dot task:list)." >&2; exit 1; }
exec bash "$(dirname -- "$0")/dot-task-update.sh" "$1" --doing
