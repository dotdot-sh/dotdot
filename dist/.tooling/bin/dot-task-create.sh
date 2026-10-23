#!/usr/bin/env bash
# description: Create a task from the task template, in the selected task service.

set -euo pipefail

. "$(dirname "$0")/lib/dot-paths.sh"
. "$(dirname "$0")/lib/dot-kv.sh"
. "$(dirname "$0")/lib/dot-tasks.sh"

usage() {
  cat <<USAGE
bash dot task:create — create a task in the project's task service (plain
files in $DOTDOT_NAME/Tasks/, GitHub issues, ...), with its body built from the
task template.

Usage:
  bash dot task:create [--title <text>] [--status <status>] [content] [--editor|--no-editor]
  bash dot task:create --help

Content, any of:
  --body <markdown>          The whole body, as text.
  --body-file <path>|-       The whole body, from a file inside the project or stdin.
  section flags              One template section each; on top of --body or
                             --body-file when given. Sections left out read "None".
$(section_flags_help)

Statuses (from the template): $(printf '%s\n' "$STATUSES" | paste -sd ' '); new tasks are $DEFAULT_STATUS.

At a terminal, a missing title is asked for, and with no content given your
editor (\$VISUAL, \$EDITOR) opens on the template, guidance included.
--editor opens it on whatever was given too; --no-editor never opens it.
Without a terminal (an agent, a script) the editor never opens and --title
is required. On first use it runs task:initialize, which needs a terminal.

Examples:
  bash dot task:create --title "Throttle failed logins on the login route" \\
    --description "Brute-force attempts are not throttled." \\
    --done-when "- [ ] 5 failed attempts lock the route for a minute" \\
    --related-features "f012--auth-login.md"
  bash dot task:create --title "Rewrite the README" --body "## Description

Make it shorter."
USAGE
}

case "${1-}" in -h | --help) usage; exit 0 ;; esac
ensure_service

title="" have_title=false status=$DEFAULT_STATUS has_body=false editor=auto
while [ $# -gt 0 ]; do
  case "$1" in
    --title) [ $# -ge 2 ] || die "--title requires a value"; title=$2; have_title=true; shift 2 ;;
    --status) [ $# -ge 2 ] || die "--status requires a value"; status=$2; shift 2 ;;
    --body) [ $# -ge 2 ] || die "--body requires a value"; printf '%s\n' "$2" > "$TMP/body"; has_body=true; shift 2 ;;
    --body-file) [ $# -ge 2 ] || die "--body-file requires a value"; read_body_file "$2" "$TMP/body"; has_body=true; shift 2 ;;
    --editor) editor=yes; shift ;;
    --no-editor) editor=no; shift ;;
    --*)
      [ $# -ge 2 ] || die "$1 requires a value"
      set_section "${1#--}" "$2" || die "Unknown flag $1. Run bash dot task:create --help."
      shift 2 ;;
    *) die "Unexpected argument: $1" ;;
  esac
done
is_status "$status" || die "Unknown status: $status"

if ! $have_title; then
  interactive || die "Missing --title"
  read -r -p "Title: " title || title=""
fi
check_title "$title"

$has_body || compose_body > "$TMP/body"
apply_sections "$TMP/body"

if [ "$editor" = auto ]; then
  editor=no
  if interactive && ! $has_body && [ ${#SET_SECTIONS[@]} -eq 0 ]; then editor=yes; fi
fi
[ "$editor" = no ] || edit_body "$TMP/body"

id=$(svc create "$title" "$status" "$TMP/body") || exit 1
printf '%s✅ Task %s created%s (%s): %s\n' "$GREEN" "$id" "$RESET" "$status" "$title"
print_link "$id"
