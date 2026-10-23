#!/usr/bin/env bash
# description: List the installed kits and the ones the registry offers.

set -euo pipefail

. "$(dirname "$0")/lib/dot-paths.sh"
. "$(dirname "$0")/lib/dot-kv.sh"
. "$(dirname "$0")/lib/dot-github.sh"
. "$(dirname "$0")/lib/dot-kits.sh"

usage() {
  cat <<USAGE
bash dot kit:list — list the installed kits (name, ref, commit,
source) and the kits the registry ($KITS_REGISTRY) offers.

Usage:
  bash dot kit:list
  bash dot kit:list --help
USAGE
}

case "${1-}" in
  -h | --help) usage; exit 0 ;;
  "") ;;
  *) echo "❌ Unexpected argument: $1" >&2; exit 1 ;;
esac

echo "Installed:"
installed=$(kit_installed)
if [ -z "$installed" ]; then
  echo "  (none)"
fi
for kit in $installed; do
  read -r url ref commit <<<"$(kit_lock_get "$kit")"
  echo "  $kit  $ref@${commit:0:7}  $url"
done

echo "Available ($KITS_REGISTRY):"
kit_tmp
if github_file "$KITS_REGISTRY" "$KITS_REGISTRY_REF" "$KITS_REGISTRY_INDEX" "$KIT_TMP/registry" 2>/dev/null; then
  awk -F= '/^[a-z][a-z0-9]*=/ { printf "  %s  %s\n", $1, substr($0, length($1) + 2) }' "$KIT_TMP/registry"
else
  echo "  ⚠️  Could not read the registry."
fi
