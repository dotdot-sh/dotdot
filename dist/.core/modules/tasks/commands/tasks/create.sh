#!/usr/bin/env bash

DESCRIPTION="Create a task from the task template, in the selected task service."

dot::use framework.console.args framework.helpers.fs framework.console.output framework.console.prompt core.modules.tasks.console core.modules.tasks.service framework.helpers.text

usage() {
  core.modules.tasks.service::require_template
  cat <<USAGE
bash dot tasks:create — create a task in the project's task service (plain
files in $(dot::relative "$TASKS_DIR")/, GitHub issues, ...), with its body built from the
task template.

Usage:
  bash dot tasks:create [--title <text>] [--status <status>] [content] [--editor|--no-editor]
  bash dot tasks:create --help

Content, any of:
  --body <markdown>          The whole body, as text.
  --body-file <path>|-       The whole body, from a file inside the project or stdin.
  section flags              One template section each; on top of --body or
                             --body-file when given. Sections left out read "None".
$(core.modules.tasks.console::section_flags_help)

Statuses (from the template): $(core.modules.tasks.service::statuses | paste -sd ' ' -); new tasks are $(core.modules.tasks.service::default_status).

At a terminal, a missing title is asked for, and with no content given your
editor (\$VISUAL, \$EDITOR) opens on the template, guidance included.
--editor opens it on whatever was given too; --no-editor never opens it.
Without a terminal (an agent, a script) the editor never opens and --title
is required. On first use it runs tasks:initialize, which needs a terminal.

Examples:
  bash dot tasks:create --title "Throttle failed logins on the login route" \\
    --description "Brute-force attempts are not throttled." \\
    --done-when "- [ ] 5 failed attempts lock the route for a minute" \\
    --related-features "f012--auth-login.md"
  bash dot tasks:create --title "Rewrite the README" --body "## Description

Make it shorter."
USAGE
}

handle() {
  local work body sections title="" has_title=false status has_body=false editor=auto has_content id
  core.modules.tasks.console::ensure_service
  framework.helpers.fs::make_temp_dir work || framework.console.output::fail "Could not create a temp directory."
  body="$work/body"
  sections="$work/sections"
  mkdir -p -- "$sections"
  status=$(core.modules.tasks.service::default_status)
  while [ $# -gt 0 ]; do
    case "$1" in
      --title) framework.console.args::require_value "$@"; title="$2"; has_title=true; shift 2 ;;
      --status) framework.console.args::require_value "$@"; status="$2"; shift 2 ;;
      --body) framework.console.args::require_value "$@"; printf '%s\n' "$2" > "$body"; has_body=true; shift 2 ;;
      --body-file) framework.console.args::require_value "$@"; core.modules.tasks.service::read_body_file "$2" "$body"; has_body=true; shift 2 ;;
      --editor) editor=yes; shift ;;
      --no-editor) editor=no; shift ;;
      --*)
        framework.console.args::require_value "$@"
        core.modules.tasks.service::set_section "$sections" "${1#--}" "$2" || framework.console.args::invalid "Unknown flag $1."
        shift 2
        ;;
      *) framework.console.args::unexpected "$1" ;;
    esac
  done
  core.modules.tasks.service::is_status "$status" || framework.console.args::invalid "Unknown status: $status"
  if ! $has_title; then
    framework.console.prompt::is_interactive || framework.console.args::invalid "Missing --title."
    title=$(framework.console.prompt::ask "Title")
  fi
  core.modules.tasks.service::check_title "$title"
  $has_body || core.modules.tasks.service::compose_body "$sections" > "$body"
  core.modules.tasks.service::apply_sections "$body" "$sections"
  has_content=$has_body
  [ -z "$(core.modules.tasks.service::given_sections "$sections")" ] || has_content=true
  [ "$(core.modules.tasks.console::editor_mode "$editor" "$has_content")" = no ] || core.modules.tasks.console::edit_body "$body"
  id=$(core.modules.tasks.console::call create "$title" "$status" "$body") || exit 1
  framework.console.output::success "Task $id created ($status): $title"
  core.modules.tasks.console::print_location "$id"
}
