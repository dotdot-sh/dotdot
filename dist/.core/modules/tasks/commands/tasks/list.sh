#!/usr/bin/env bash

DESCRIPTION="List the project's tasks, filtered by status and sorted by date."

dot::use framework.console.args framework.helpers.fs framework.console.output core.modules.tasks.console core.modules.tasks.service framework.helpers.text

usage() {
  core.modules.tasks.service::require_template
  cat <<USAGE
bash dot tasks:list — list the project's tasks, oldest first by default,
in pages of $TASK_PAGE_SIZE: --limit sets the page size (0 lists them all on one page),
--page picks the page (1 by default).

Usage:
  bash dot tasks:list [--status <status>[,<status>...]] [--sort created|updated] [--asc|--desc] [--limit <n>] [--page <n>]
  bash dot tasks:list --help

Statuses (from the template): $(core.modules.tasks.service::statuses | paste -sd ' ' -)

Examples:
  bash dot tasks:list --status todo,doing,paused
  bash dot tasks:list --sort updated --desc --limit 5 --page 2
USAGE
}

print_rows() {
  local rows="$1" first="$2" last="$3" id status created updated title
  framework.console.output::title "$(printf '%-8s %-10s %-19s  %-19s  %s' ID STATUS CREATED UPDATED TITLE)"
  sed -n "${first},${last}p" "$rows" | while IFS=$'\t' read -r id status created updated title; do
    printf '%-8s %-10s %-19s  %-19s  %s\n' "$id" "$status" "$created" "$updated" "$title"
  done
}

handle() {
  local work statuses="" sort=created order=asc limit page=1 status total size pages first last next=""
  core.modules.tasks.console::ensure_service
  limit=$TASK_PAGE_SIZE
  while [ $# -gt 0 ]; do
    case "$1" in
      --page)
        framework.console.args::require_value "$@"
        framework.console.args::is_number "$2" && [ "$((10#$2))" -ge 1 ] || framework.console.args::invalid "--page takes a number from 1."
        page=$((10#$2))
        shift 2
        ;;
      --status)
        framework.console.args::require_value "$@"
        statuses=""
        while IFS= read -r status; do
          core.modules.tasks.service::is_status "$status" || framework.console.args::invalid "Unknown status: $status"
          statuses="$statuses $status"
        done < <(framework.console.args::split "$2")
        [ -n "$statuses" ] || framework.console.args::invalid "--status requires a value."
        statuses="$statuses "
        shift 2
        ;;
      --sort)
        framework.console.args::require_value "$@"
        core.modules.tasks.service::is_sort_column "$2" || framework.console.args::invalid "--sort takes created or updated."
        sort="$2"
        shift 2
        ;;
      --limit)
        framework.console.args::require_value "$@"
        framework.console.args::is_number "$2" || framework.console.args::invalid "--limit takes a number (0 for all)."
        limit=$((10#$2))
        shift 2
        ;;
      --asc) order=asc; shift ;;
      --desc) order=desc; shift ;;
      *) framework.console.args::unexpected "$1" ;;
    esac
  done
  framework.helpers.fs::make_temp_dir work || framework.console.output::fail "Could not create a temp directory."
  core.modules.tasks.console::call list > "$work/list" || exit 1
  core.modules.tasks.service::sort_rows "$work/list" "$statuses" "$sort" "$order" > "$work/rows"
  if [ ! -s "$work/rows" ]; then
    statuses=$(framework.helpers.text::trim "$statuses")
    framework.console.output::line "No tasks${statuses:+ with status ${statuses// /, }}."
    return 0
  fi
  total=$(wc -l < "$work/rows" | tr -d ' ')
  size=$limit
  [ "$size" -gt 0 ] || size=$total
  pages=$(( (total + size - 1) / size ))
  if [ "$page" -gt "$pages" ]; then
    framework.console.output::warn "Nothing on page $page: $(framework.helpers.text::plural "$total" task) fit on $(framework.helpers.text::plural "$pages" page) of $size. The last page is --page $pages."
    return 0
  fi
  first=$(( (page - 1) * size + 1 ))
  last=$(( page * size < total ? page * size : total ))
  print_rows "$work/rows" "$first" "$last"
  [ "$pages" -gt 1 ] || return 0
  [ "$page" -ge "$pages" ] || next=" · next: --page $((page + 1))"
  framework.console.output::line "$(framework.console.output::paint cyan "Showing $first-$last of $total · Page $page/$pages")$next"
}
