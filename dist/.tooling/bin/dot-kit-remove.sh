#!/usr/bin/env bash
# description: Remove a kit: its context regions and files, its tools, its lock entry.

set -euo pipefail

. "$(dirname "$0")/lib/dot-paths.sh"
. "$(dirname "$0")/lib/dot-kv.sh"
. "$(dirname "$0")/lib/dot-github.sh"
. "$(dirname "$0")/lib/dot-kits.sh"
. "$(dirname "$0")/lib/dot-confirm.sh"

usage() {
  cat <<USAGE
bash dot kit:remove — remove a kit entirely: its regions in
dotdot's docs (markers included), the docs it created, $(dotdot_rel "$KITS_DIR")/<kit>/,
and its lock entry; then sync prunes its links. Needs a y on a terminal (piped
input is refused).

Usage:
  bash dot kit:remove <kit>
  bash dot kit:remove --help
USAGE
}

case "${1-}" in
  -h | --help) usage; exit 0 ;;
  "") echo "❌ A kit name is required." >&2; usage >&2; exit 1 ;;
esac
[ $# -eq 1 ] || { echo "❌ Unexpected argument: $2" >&2; exit 1; }
kit=$1
kit_lock_get "$kit" >/dev/null || { echo "❌ $kit is not installed." >&2; exit 1; }

confirm_or_abort "Remove $kit?"
kit_strip_regions "$kit"
rm -rf -- "${KITS_DIR:?}/$kit"
kit_lock_delete "$kit"
kit_sync
echo "✅ Removed $kit. Review the changes with git diff."
