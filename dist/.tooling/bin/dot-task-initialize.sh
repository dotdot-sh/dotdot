#!/usr/bin/env bash
# description: Pick the service that keeps the project's tasks (plain files, GitHub, ...).

set -euo pipefail

. "$(dirname "$0")/lib/dot-paths.sh"
. "$(dirname "$0")/lib/dot-kv.sh"

usage() {
  cat <<EOF
bash dot task:initialize — choose where this project's tasks are kept, then
set that service up. Any task:* command runs it on first use.

The choice is saved in $(dotdot_rel "$TASKS_CONF"), shared with the team through
git; every task:* command then goes to that service. Running it again
switches services. Existing tasks are not moved: the new service starts with
its own.

Services (one script each in $(dotdot_rel "$TASK_SERVICES_DIR")/):
EOF
  local f
  for f in "$TASK_SERVICES_DIR"/dot-task-*.sh; do
    [ -f "$f" ] || continue
    printf '  %-10s %s\n' "$(service_name "$f")" "$(sed -n 's/^# description: //p' "$f" | head -n 1)"
  done
  cat <<EOF

It asks on a terminal (piped input is refused), so only a person can choose.

Usage:
  bash dot task:initialize
  bash dot task:initialize --help
EOF
}

service_name() {
  local base
  base=$(basename -- "$1" .sh)
  printf '%s\n' "${base#dot-task-}"
}

case "${1-}" in
  -h | --help) usage; exit 0 ;;
  "") ;;
  *) echo "❌ Unknown argument: $1" >&2; usage >&2; exit 1 ;;
esac

if [ -t 1 ]; then
  BOLD=$'\033[1m'; RED=$'\033[31m'; GREEN=$'\033[32m'; RESET=$'\033[0m'
else
  BOLD=""; RED=""; GREEN=""; RESET=""
fi

die() {
  printf '%s❌ %s%s\n' "$RED" "$*" "$RESET" >&2
  exit 1
}

[ -t 0 ] || die "Choosing a task service needs a terminal; ask the user to run bash dot task:initialize."

names=() labels=()
for f in "$TASK_SERVICES_DIR"/dot-task-*.sh; do
  [ -f "$f" ] || continue
  names+=("$(service_name "$f")")
  labels+=("$(service_name "$f") — $(sed -n 's/^# description: //p' "$f" | head -n 1)")
done
[ ${#names[@]} -gt 0 ] || die "No task services installed in $(dotdot_rel "$TASK_SERVICES_DIR")/."

current=$(kv_get "$TASKS_CONF" service 2>/dev/null || true)
if [ -n "$current" ]; then
  printf 'Tasks are kept in: %s%s%s. Switching leaves existing tasks where they are.\n' "$BOLD" "$current" "$RESET"
fi

printf '\n%sWhere should this project keep its tasks?%s\n' "$BOLD" "$RESET"
PS3="Choose 1-${#labels[@]} (Ctrl-D to cancel): "
choice=""
select label in "${labels[@]}"; do
  [ -n "$label" ] && { choice=${names[$((REPLY - 1))]}; break; }
  echo "Pick a number from the list."
done
[ -n "$choice" ] || die "Cancelled — nothing changed."

# The service sets itself up first, so a failed setup leaves the old choice.
bash "$TASK_SERVICES_DIR/dot-task-$choice.sh" init || die "Setting up $choice failed — nothing changed."
kv_set "$TASKS_CONF" service "$choice" || die "Could not write $(dotdot_rel "$TASKS_CONF")."
printf '%s✅ Tasks are kept in %s%s. Commit %s to share it with the team.\n' \
  "$GREEN" "$choice" "$RESET" "$(dotdot_rel "$TASKS_CONF")"
