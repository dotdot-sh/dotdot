#!/usr/bin/env bash
# description: List the project's tasks, filtered by status and sorted by date.

set -euo pipefail

. "$(dirname "$0")/lib/dot-paths.sh"
. "$(dirname "$0")/lib/dot-kv.sh"
. "$(dirname "$0")/lib/dot-tasks.sh"

usage() {
  cat <<USAGE
bash dot task:list — list the project's tasks, oldest first by default,
in pages of 25: --limit sets the page size (0 lists them all on one page),
--page picks the page (1 by default).

Usage:
  bash dot task:list [--status <status>[,<status>...]] [--sort created|updated] [--asc|--desc] [--limit <n>] [--page <n>]
  bash dot task:list --help

Statuses (from the template): $(printf '%s\n' "$STATUSES" | paste -sd ' ')

Examples:
  bash dot task:list --status todo,doing,paused
  bash dot task:list --sort updated --desc --limit 5 --page 2
USAGE
}

case "${1-}" in -h | --help) usage; exit 0 ;; esac
ensure_service

statuses="" sort=created order=asc limit=25 page=1
while [ $# -gt 0 ]; do
  case "$1" in
    --page)
      [ $# -ge 2 ] || die "--page requires a value"
      [[ "$2" =~ ^[0-9]+$ ]] && [ "$((10#$2))" -ge 1 ] || die "--page takes a number from 1"
      page=$((10#$2)); shift 2 ;;
    --status)
      [ $# -ge 2 ] || die "--status requires a value"
      IFS=',' read -r -a wanted <<<"$2"
      for s in "${wanted[@]}"; do is_status "$s" || die "Unknown status: $s"; done
      statuses=" ${wanted[*]} "; shift 2 ;;
    --sort)
      [ $# -ge 2 ] || die "--sort requires a value"
      case "$2" in created | updated) sort=$2 ;; *) die "--sort takes created or updated" ;; esac
      shift 2 ;;
    --limit)
      [ $# -ge 2 ] || die "--limit requires a value"
      [[ "$2" =~ ^[0-9]+$ ]] || die "--limit takes a number (0 for all)"
      limit=$((10#$2)); shift 2 ;;
    --asc) order=asc; shift ;;
    --desc) order=desc; shift ;;
    *) die "Unexpected argument: $1" ;;
  esac
done

svc list > "$TMP/list" || exit 1
col=3
[ "$sort" = updated ] && col=4
rev=""
[ "$order" = desc ] && rev=r
awk -F '\t' -v want="$statuses" 'want == "" || index(want, " " $2 " ")' "$TMP/list" \
  | sort -t $'\t' -k "$col,$col$rev" -k "1,1V$rev" > "$TMP/rows"
if [ ! -s "$TMP/rows" ]; then
  statuses=${statuses# }; statuses=${statuses% }
  echo "No tasks${statuses:+ with status ${statuses// /, }}."
  exit 0
fi
total=$(wc -l < "$TMP/rows")
size=$limit
[ "$size" -gt 0 ] || size=$total
pages=$(( (total + size - 1) / size ))
if [ "$page" -gt "$pages" ]; then
  plural() { [ "$1" -eq 1 ] && printf '%s %s' "$1" "$2" || printf '%s %ss' "$1" "$2"; }
  printf '%sNothing on page %s:%s %s fit on %s of %s. The last page is --page %s.\n' \
    "$YELLOW" "$page" "$RESET" "$(plural "$total" task)" "$(plural "$pages" page)" "$size" "$pages"
  exit 0
fi
first=$(( (page - 1) * size + 1 ))
last=$(( page * size < total ? page * size : total ))
printf '%s%-8s %-10s %-19s  %-19s  %s%s\n' "$BOLD" ID STATUS CREATED UPDATED TITLE "$RESET"
sed -n "${first},${last}p" "$TMP/rows" | while IFS=$'\t' read -r id status created updated title; do
  printf '%-8s %-10s %-19s  %-19s  %s\n' "$id" "$status" "$created" "$updated" "$title"
done
if [ "$pages" -gt 1 ]; then
  printf '%sShowing %s-%s of %s · Page %s/%s%s' "$CYAN" "$first" "$last" "$total" "$page" "$pages" "$RESET"
  [ "$page" -ge "$pages" ] || printf ' · next: --page %s' $((page + 1))
  printf '\n'
fi
