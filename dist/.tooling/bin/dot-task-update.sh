#!/usr/bin/env bash
# description: Change a task's title, content, or status.

set -euo pipefail

. "$(dirname "$0")/lib/dot-paths.sh"
. "$(dirname "$0")/lib/dot-kv.sh"
. "$(dirname "$0")/lib/dot-tasks.sh"

usage() {
  cat <<USAGE
bash dot task:update — change an existing task: its title, its content,
and/or its status, in one step.

Usage:
  bash dot task:update <id> [--title <text>] [content] [--<status>] [--editor|--no-editor]
  bash dot task:update --help

<id> is what bash dot task:list shows (t004, #12).

Content, any of:
  --body <markdown>          Replaces the whole body.
  --body-file <path>|-       Replaces the whole body, from a file inside the project or stdin.
  section flags              Replace that section only, the rest stays as it is.
$(section_flags_help)

Status flags (from the template), one at most:
$(printf '%s\n' "$STATUSES" | sed 's/^/  --/')

At a terminal, with nothing to change given, your editor (\$VISUAL, \$EDITOR)
opens on the task's current body. --editor opens it on top of the changes
given too; --no-editor never opens it. Without a terminal (an agent, a script)
the editor never opens.

Examples:
  bash dot task:update t004 --doing
  bash dot task:update t004 --done-when "- [x] lock after 5" --done
  bash dot task:update '#12' --title "Throttle failed logins"
USAGE
}

case "${1-}" in -h | --help) usage; exit 0 ;; esac
ensure_service

check_id "${1-}"
id=$1
shift
title="" has_body=false status="" editor=auto
while [ $# -gt 0 ]; do
  case "$1" in
    --title) [ $# -ge 2 ] || die "--title requires a value"; check_title "$2"; title=$2; shift 2 ;;
    --body) [ $# -ge 2 ] || die "--body requires a value"; printf '%s\n' "$2" > "$TMP/body"; has_body=true; shift 2 ;;
    --body-file) [ $# -ge 2 ] || die "--body-file requires a value"; read_body_file "$2" "$TMP/body"; has_body=true; shift 2 ;;
    --editor) editor=yes; shift ;;
    --no-editor) editor=no; shift ;;
    --*)
      if is_status "${1#--}"; then
        [ -z "$status" ] || die "Give one status at most."
        status=${1#--}; shift
      else
        [ $# -ge 2 ] || die "$1 requires a value"
        set_section "${1#--}" "$2" || die "Unknown flag $1. Run bash dot task:update --help."
        shift 2
      fi
      ;;
    *) die "Unexpected argument: $1" ;;
  esac
done

if [ "$editor" = auto ]; then
  editor=no
  if interactive && [ -z "$title$status" ] && ! $has_body && [ ${#SET_SECTIONS[@]} -eq 0 ]; then editor=yes; fi
fi
if [ "$editor" = no ] && [ -z "$title$status" ] && ! $has_body && [ ${#SET_SECTIONS[@]} -eq 0 ]; then
  die "Nothing to update: give --title, content, or a status flag."
fi

body_arg=""
if $has_body || [ ${#SET_SECTIONS[@]} -gt 0 ] || [ "$editor" = yes ]; then
  if ! $has_body; then
    svc show "$id" > "$TMP/show" || exit 1
    tail -n +2 "$TMP/show" > "$TMP/body"
  fi
  apply_sections "$TMP/body"
  [ "$editor" = no ] || edit_body "$TMP/body"
  body_arg="$TMP/body"
fi

if [ -n "$title" ] || [ -n "$body_arg" ]; then
  svc update "$id" "$title" "$body_arg" || exit 1
fi
[ -z "$status" ] || svc status "$id" "$status" || exit 1
printf '%s✅ Task %s updated%s%s\n' "$GREEN" "$id" "$RESET" "${status:+ (now $status)}"
print_link "$id"
