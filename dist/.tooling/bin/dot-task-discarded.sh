#!/usr/bin/env bash
# description: Move a task to discarded.

set -euo pipefail

case "${1-}" in
  -h | --help)
    cat <<USAGE
bash dot task:discarded — move a task to discarded, in whichever service keeps the tasks.
The same as bash dot task:update <id> --discarded.

Usage:
  bash dot task:discarded <id>
  bash dot task:discarded --help

<id> is what bash dot task:list shows (t004, #12).
USAGE
    exit 0
    ;;
esac
[ $# -eq 1 ] || { echo "❌ task:discarded takes one task id (see bash dot task:list)." >&2; exit 1; }
exec bash "$(dirname -- "$0")/dot-task-update.sh" "$1" --discarded
