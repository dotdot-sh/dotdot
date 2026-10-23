#!/usr/bin/env bash
# description: Show one task, frontmatter and body, in less or printed.

set -euo pipefail

. "$(dirname "$0")/lib/dot-paths.sh"
. "$(dirname "$0")/lib/dot-kv.sh"
. "$(dirname "$0")/lib/dot-tasks.sh"

usage() {
  cat <<USAGE
bash dot task:show — show one task: a frontmatter built from its fields
(id, title, status, created, updated), then its body. The same shape whichever
service keeps the tasks.

At a terminal it opens in less; anywhere else (an agent, a script) it is
printed between two full-width rules. --print prints at a terminal too.

Usage:
  bash dot task:show <id> [--print]
  bash dot task:show --help

<id> is what bash dot task:list shows (t004, #12).
USAGE
}

case "${1-}" in -h | --help) usage; exit 0 ;; esac
ensure_service
check_id "${1-}"
id=$1
shift
print=false
while [ $# -gt 0 ]; do
  case "$1" in
    --print) print=true; shift ;;
    *) die "Unexpected argument: $1" ;;
  esac
done

svc show "$id" > "$TMP/show" || exit 1
IFS=$'\t' read -r tid status created updated title < "$TMP/show"
# A leading "#" (GitHub ids) would start a YAML comment.
case "$tid" in "#"*) tid="\"$tid\"" ;; esac
{
  printf -- '---\nid: %s\ntitle: %s\nstatus: %s\ncreated: %s\nupdated: %s\n---\n\n' "$tid" "$title" "$status" "$created" "$updated"
  tail -n +2 "$TMP/show"
} > "$TMP/task.md"

if ! $print && [ -t 1 ] && command -v less >/dev/null; then
  less -R -- "$TMP/task.md"
  exit
fi
width=80
if [ -t 1 ]; then width=$(tput cols 2>/dev/null || echo 80); fi
rule=$(printf '%*s' "$width" '' | tr ' ' '-')
printf '%s\n' "$rule"
printf '%s\n' "$(cat -- "$TMP/task.md")"
printf '%s\n' "$rule"
