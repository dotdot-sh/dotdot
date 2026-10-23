#!/usr/bin/env bash
# description: Move a task to paused.

set -euo pipefail

case "${1-}" in
  -h | --help)
    cat <<USAGE
bash dot task:paused — move a task to paused, in whichever service keeps the tasks.
The same as bash dot task:update <id> --paused.

Usage:
  bash dot task:paused <id>
  bash dot task:paused --help

<id> is what bash dot task:list shows (t004, #12).
USAGE
    exit 0
    ;;
esac
[ $# -eq 1 ] || { echo "❌ task:paused takes one task id (see bash dot task:list)." >&2; exit 1; }
exec bash "$(dirname -- "$0")/dot-task-update.sh" "$1" --paused
