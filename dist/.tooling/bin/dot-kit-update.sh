#!/usr/bin/env bash
# description: Update installed kits to the latest commit of their ref.

set -euo pipefail

. "$(dirname "$0")/lib/dot-paths.sh"
. "$(dirname "$0")/lib/dot-kv.sh"
. "$(dirname "$0")/lib/dot-github.sh"
. "$(dirname "$0")/lib/dot-kits.sh"
. "$(dirname "$0")/lib/dot-confirm.sh"

usage() {
  cat <<USAGE
bash dot kit:update — update a kit, or every installed one, to the
latest commit of the ref it was added with.

Each kit's context regions are replaced where they stand, its new context
files placed, its dropped ones removed, and its tools replaced. Nothing else is
checked: review the result with git diff. Each kit is previewed and needs a y
on a terminal (piped input is refused).

Usage:
  bash dot kit:update [<kit>]
  bash dot kit:update --help
USAGE
}

case "${1-}" in
  -h | --help) usage; exit 0 ;;
esac
[ $# -le 1 ] || { echo "❌ Unexpected argument: $2" >&2; exit 1; }

if [ $# -eq 1 ]; then
  kits=("$1")
else
  mapfile -t kits < <(kit_installed)
fi
[ ${#kits[@]} -gt 0 ] || { echo "No kits installed."; exit 0; }

kit_tmp
for kit in "${kits[@]}"; do
  entry=$(kit_lock_get "$kit") || { echo "❌ $kit is not installed." >&2; exit 1; }
  read -r url ref commit <<<"$entry"
  rm -rf -- "${KIT_TMP:?}"/*
  kit_fetch "$url@$ref"
  name=$(kit_validate "$KIT_SRC")
  [ "$name" = "$kit" ] || { echo "❌ $url now names itself $name, not $kit." >&2; exit 1; }
  if [ -n "$KIT_COMMIT" ] && [ "$KIT_COMMIT" = "$commit" ]; then
    echo "✅ $kit is up to date (${commit:0:7})."
    continue
  fi
  echo "Kit $kit: ${commit:0:7} → ${KIT_COMMIT:0:7}"
  kit_preview "$kit" "$KIT_SRC"
  confirm_or_abort "Update $kit?" || continue
  mapfile -t places < <(kit_context_places "$kit" "$KIT_SRC")
  kit_place_context "$kit" "$KIT_SRC"
  kit_strip_regions "$kit" "${places[@]+"${places[@]}"}"
  kit_install_tools "$kit" "$KIT_SRC"
  kit_lock_set "$kit" "$url $ref ${KIT_COMMIT:-unknown}"
  echo "✅ Updated $kit."
  kit_claude_notice "$kit"
done
kit_sync
echo "Review the changes with git diff."
