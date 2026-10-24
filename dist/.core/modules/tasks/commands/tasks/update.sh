#!/usr/bin/env bash

DESCRIPTION="Change a task's title, content, or status."

dot::use framework.console.args framework.helpers.fs framework.console.output core.modules.tasks.console core.modules.tasks.service

usage() {
  core.modules.tasks.service::require_template
  cat <<USAGE
bash dot tasks:update — change an existing task: its title, its content,
and/or its status, in one step.

Usage:
  bash dot tasks:update <id> [--title <text>] [content] [--<status>] [--editor|--no-editor]
  bash dot tasks:update --help

<id> is what bash dot tasks:list shows (t004, #12).

Content, any of:
  --body <markdown>          Replaces the whole body.
  --body-file <path>|-       Replaces the whole body, from a file inside the project or stdin.
  section flags              Replace that section only, the rest stays as it is.
$(core.modules.tasks.console::section_flags_help)

Status flags (from the template), one at most:
$(core.modules.tasks.service::statuses | sed 's/^/  --/')

At a terminal, with nothing to change given, your editor (\$VISUAL, \$EDITOR)
opens on the task's current body. --editor opens it on top of the changes
given too; --no-editor never opens it. Without a terminal (an agent, a script)
the editor never opens.

Examples:
  bash dot tasks:update t004 --doing
  bash dot tasks:update t004 --done-when "- [x] lock after 5" --done
  bash dot tasks:update '#12' --title "Throttle failed logins"
USAGE
}

handle() {
  local id work body sections title="" status="" has_body=false editor=auto has_changes body_argument=""
  core.modules.tasks.console::ensure_service
  core.modules.tasks.service::check_id "${1-}"
  id="$1"
  shift
  framework.helpers.fs::make_temp_dir work || framework.console.output::fail "Could not create a temp directory."
  body="$work/body"
  sections="$work/sections"
  mkdir -p -- "$sections"
  while [ $# -gt 0 ]; do
    case "$1" in
      --title) framework.console.args::require_value "$@"; core.modules.tasks.service::check_title "$2"; title="$2"; shift 2 ;;
      --body) framework.console.args::require_value "$@"; printf '%s\n' "$2" > "$body"; has_body=true; shift 2 ;;
      --body-file) framework.console.args::require_value "$@"; core.modules.tasks.service::read_body_file "$2" "$body"; has_body=true; shift 2 ;;
      --editor) editor=yes; shift ;;
      --no-editor) editor=no; shift ;;
      --*)
        if core.modules.tasks.service::is_status "${1#--}"; then
          [ -z "$status" ] || framework.console.args::invalid "Give one status at most."
          status="${1#--}"
          shift
          continue
        fi
        framework.console.args::require_value "$@"
        core.modules.tasks.service::set_section "$sections" "${1#--}" "$2" || framework.console.args::invalid "Unknown flag $1."
        shift 2
        ;;
      *) framework.console.args::unexpected "$1" ;;
    esac
  done
  has_changes=$has_body
  [ -z "$title$status$(core.modules.tasks.service::given_sections "$sections")" ] || has_changes=true
  editor=$(core.modules.tasks.console::editor_mode "$editor" "$has_changes")
  [ "$editor" = yes ] || $has_changes || framework.console.args::invalid "Nothing to update: give --title, content, or a status flag."
  if $has_body || [ -n "$(core.modules.tasks.service::given_sections "$sections")" ] || [ "$editor" = yes ]; then
    if ! $has_body; then
      core.modules.tasks.console::call show "$id" > "$work/show" || exit 1
      tail -n +2 "$work/show" > "$body"
    fi
    core.modules.tasks.service::apply_sections "$body" "$sections"
    [ "$editor" = no ] || core.modules.tasks.console::edit_body "$body"
    body_argument="$body"
  fi
  if [ -n "$title" ] || [ -n "$body_argument" ]; then
    core.modules.tasks.console::call update "$id" "$title" "$body_argument" || exit 1
  fi
  [ -z "$status" ] || core.modules.tasks.console::call status "$id" "$status" || exit 1
  framework.console.output::success "Task $id updated${status:+ (now $status)}"
  core.modules.tasks.console::print_location "$id"
}
