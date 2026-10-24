#!/usr/bin/env bash

DESCRIPTION="Show one task, frontmatter and body, in less or printed."

dot::use framework.console.args framework.helpers.fs framework.console.output core.modules.tasks.console core.modules.tasks.service framework.console.terminal

usage() {
  cat <<USAGE
bash dot tasks:show — show one task: a frontmatter built from its fields
(id, title, status, created, updated), then its body. The same shape whichever
service keeps the tasks.

At a terminal it opens in less; anywhere else (an agent, a script) it is
printed between two full-width rules. --print prints at a terminal too.

Usage:
  bash dot tasks:show <id> [--print]
  bash dot tasks:show --help

<id> is what bash dot tasks:list shows (t004, #12).
USAGE
}

handle() {
  local id print=false work task_id status created updated title
  core.modules.tasks.console::ensure_service
  core.modules.tasks.service::check_id "${1-}"
  id="$1"
  shift
  while [ $# -gt 0 ]; do
    case "$1" in
      --print) print=true; shift ;;
      *) framework.console.args::unexpected "$1" ;;
    esac
  done
  framework.helpers.fs::make_temp_dir work || framework.console.output::fail "Could not create a temp directory."
  core.modules.tasks.console::call show "$id" > "$work/show" || exit 1
  IFS=$'\t' read -r task_id status created updated title < "$work/show"
  case "$task_id" in
    "#"*) task_id="\"$task_id\"" ;;
  esac
  {
    printf -- '---\nid: %s\ntitle: %s\nstatus: %s\ncreated: %s\nupdated: %s\n---\n\n' "$task_id" "$title" "$status" "$created" "$updated"
    tail -n +2 "$work/show"
  } > "$work/task.md"
  framework.console.terminal::page "$work/task.md" "$print"
}
