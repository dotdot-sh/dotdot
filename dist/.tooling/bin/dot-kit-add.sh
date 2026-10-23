#!/usr/bin/env bash
# description: Add a kit: its context into dotdot's docs, its tools into .tooling/kits/.

set -euo pipefail

. "$(dirname "$0")/lib/dot-paths.sh"
. "$(dirname "$0")/lib/dot-kv.sh"
. "$(dirname "$0")/lib/dot-github.sh"
. "$(dirname "$0")/lib/dot-kits.sh"
. "$(dirname "$0")/lib/dot-confirm.sh"

usage() {
  cat <<USAGE
bash dot kit:add — add a kit (e.g. laravel) from the registry
($KITS_REGISTRY) or straight from a GitHub repo.

The kit's context/*.md files go into dotdot's top-level docs: a file named
like an existing doc (RULES.md) becomes a region in it, any other becomes a
new <File>-<kit>.md; $(dotdot_rel "$KITS_MAP") ("<kit>/<File>.md:<Dest>.md"
lines) overrides that. Its skills, agents, scripts, and suggested Claude
Code settings go to $(dotdot_rel "$KITS_DIR")/<kit>/, and its commands run as
bash dot <kit>:<command>. The settings are never applied: copy what suits
you into .claude/settings.local.json.

Every file is previewed first, scripts flagged, and nothing changes until you
answer y on a terminal (piped input is refused). Private repos need gh logged
in or GH_TOKEN in $(dotdot_rel "$ENV_FILE").

Usage:
  bash dot kit:add <name>[@ref]
  bash dot kit:add <github-url | owner/repo>[@ref]
  bash dot kit:add --help

The ref (branch, tag, or commit) defaults to $KIT_DEFAULT_REF.

Examples:
  bash dot kit:add laravel
  bash dot kit:add https://github.com/acme/dotdot-kit-svelte@v1.0.0
USAGE
}

case "${1-}" in
  -h | --help) usage; exit 0 ;;
  "") echo "❌ A kit name or repo is required." >&2; usage >&2; exit 1 ;;
esac
[ $# -eq 1 ] || { echo "❌ Unexpected argument: $2" >&2; exit 1; }

kit_tmp
kit_fetch "$1"
kit=$(kit_validate "$KIT_SRC")
if kit_lock_get "$kit" >/dev/null; then
  echo "❌ $kit is already installed; use bash dot kit:update $kit." >&2
  exit 1
fi
[ ! -e "$KITS_DIR/$kit" ] || { echo "❌ $(dotdot_rel "$KITS_DIR/$kit") already exists." >&2; exit 1; }

echo "Kit $kit ($KIT_URL@$KIT_REF${KIT_COMMIT:+, ${KIT_COMMIT:0:7}}):"
kit_preview "$kit" "$KIT_SRC"
confirm_or_abort "Add $kit?"

kit_place_context "$kit" "$KIT_SRC"
kit_install_tools "$kit" "$KIT_SRC"
kit_lock_set "$kit" "$KIT_URL $KIT_REF ${KIT_COMMIT:-unknown}"
kit_sync
echo "✅ Added $kit. Review the changes with git diff."
kit_claude_notice "$kit"
