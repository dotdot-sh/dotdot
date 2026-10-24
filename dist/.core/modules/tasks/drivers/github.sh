#!/usr/bin/env bash

DESCRIPTION="GitHub issues labelled \"task\", through the gh CLI."

dot::use framework.helpers.date framework.integrations.github-api.service framework.integrations.github-cli.service

TASK_LABEL="task"
TASK_LABEL_COLOR="EDEDED"
TASK_STATUS_LABEL_PREFIX="task:"
TASK_CLOSED_STATUSES=" done discarded "
TASK_DISCARDED_STATUS="discarded"
TASK_REPOSITORY_KEY="TASKS_GITHUB_REPO"
TASK_ISSUE_LIMIT=1000
TASK_JQ_STATUS='([.labels[].name | select(startswith("'"$TASK_STATUS_LABEL_PREFIX"'")) | ltrimstr("'"$TASK_STATUS_LABEL_PREFIX"'")] | first)
  // (if .state == "CLOSED" then "done" else "todo" end)'
TASK_JQ_ROW='["#\(.number)", ('"$TASK_JQ_STATUS"'), .createdAt, .updatedAt, .title] | @tsv'
TASK_ISSUE_FIELDS="number,title,state,labels,createdAt,updatedAt"

core.modules.tasks.drivers.github::require_cli() {
  framework.integrations.github-cli.service::is_installed || dot::abort "The GitHub CLI (gh) is required: https://cli.github.com"
}

core.modules.tasks.drivers.github::status_color() {
  case "$1" in
    todo) printf '8250DF\n' ;;
    doing) printf '0969DA\n' ;;
    paused) printf 'FBCA04\n' ;;
    done) printf '1A7F37\n' ;;
    discarded) printf '6E7781\n' ;;
    *) printf 'BFD4F2\n' ;;
  esac
}

core.modules.tasks.drivers.github::repository() {
  local repository
  repository=$(dot::config "$TASK_REPOSITORY_KEY") || return 1
  framework.integrations.github-api.service::is_repository "$repository" \
    || dot::abort "Invalid $TASK_REPOSITORY_KEY in $(dot::relative "$ENV_FILE"): $repository"
  printf '%s\n' "$repository"
}

core.modules.tasks.drivers.github::number() {
  local number="${1#\#}"
  [[ "$number" =~ ^[0-9]+$ ]] || dot::abort "Invalid GitHub task id: $1 (use the issue number, e.g. #12)"
  printf '%s\n' "$number"
}

core.modules.tasks.drivers.github::local_times() {
  local id status created updated title
  while IFS=$'\t' read -r id status created updated title; do
    printf '%s\t%s\t%s\t%s\t%s\n' "$id" "$status" "$(framework.helpers.date::from_iso "$created")" "$(framework.helpers.date::from_iso "$updated")" "$title"
  done
}

core.modules.tasks.drivers.github::labels() {
  local repository="$1" number="$2" labels
  labels=$(framework.integrations.github-cli.service::run issue view "$number" --repo "$repository" --json labels --jq '.labels[].name') \
    || dot::abort "Could not read issue #$number in $repository."
  printf '%s\n' "$labels" | grep -xF "$TASK_LABEL" >/dev/null \
    || dot::abort "Issue #$number is not a task (no \"$TASK_LABEL\" label); it was left alone."
  printf '%s\n' "$labels"
}

core.modules.tasks.drivers.github::is_closed_status() {
  case "$TASK_CLOSED_STATUSES" in
    *" $1 "*) return 0 ;;
  esac
  return 1
}

core.modules.tasks.drivers.github::apply_status() {
  local repository="$1" number="$2" status="$3" labels="$4" label state reason
  local removed=() added=()
  while IFS= read -r label; do
    case "$label" in
      "$TASK_STATUS_LABEL_PREFIX"*) [ "$label" = "$TASK_STATUS_LABEL_PREFIX$status" ] || removed+=(--remove-label "$label") ;;
    esac
  done <<< "$labels"
  printf '%s\n' "$labels" | grep -xF "$TASK_STATUS_LABEL_PREFIX$status" >/dev/null || added+=(--add-label "$TASK_STATUS_LABEL_PREFIX$status")
  if [ ${#removed[@]} -gt 0 ] || [ ${#added[@]} -gt 0 ]; then
    framework.integrations.github-cli.service::run issue edit "$number" --repo "$repository" ${removed[@]+"${removed[@]}"} ${added[@]+"${added[@]}"} >/dev/null
  fi
  state=$(framework.integrations.github-cli.service::run issue view "$number" --repo "$repository" --json state --jq .state)
  if ! core.modules.tasks.drivers.github::is_closed_status "$status"; then
    [ "$state" = OPEN ] || framework.integrations.github-cli.service::run issue reopen "$number" --repo "$repository" >/dev/null
    return 0
  fi
  reason=completed
  [ "$status" != "$TASK_DISCARDED_STATUS" ] || reason="not planned"
  if [ "$state" = CLOSED ] && [ ${#removed[@]} -gt 0 ]; then
    framework.integrations.github-cli.service::run issue reopen "$number" --repo "$repository" >/dev/null
    state=OPEN
  fi
  [ "$state" != OPEN ] || framework.integrations.github-cli.service::run issue close "$number" --repo "$repository" --reason "$reason" >/dev/null
}

core.modules.tasks.drivers.github::is_authenticated() {
  core.modules.tasks.drivers.github::require_cli
  framework.integrations.github-cli.service::is_authenticated
}

core.modules.tasks.drivers.github::detected_repository() {
  framework.integrations.github-cli.service::current_repository "$BASE"
}

core.modules.tasks.drivers.github::check_repository() {
  framework.integrations.github-api.service::is_repository "$1" || dot::abort "Not an owner/name repository: ${1:-(empty)}"
  framework.integrations.github-cli.service::has_repository "$1" || dot::abort "Can't reach $1 with the current gh login."
}

core.modules.tasks.drivers.github::managed_labels() {
  local status
  printf '%s\n' "$TASK_LABEL"
  while IFS= read -r status; do
    printf '%s%s\n' "$TASK_STATUS_LABEL_PREFIX" "$status"
  done < <(core.modules.tasks.service::statuses)
}

core.modules.tasks.drivers.github::configure() {
  local repository="$1" status
  framework.integrations.github-cli.service::run label create "$TASK_LABEL" --repo "$repository" --color "$TASK_LABEL_COLOR" --description "Managed by dotdot tasks" --force >/dev/null
  while IFS= read -r status; do
    framework.integrations.github-cli.service::run label create "$TASK_STATUS_LABEL_PREFIX$status" --repo "$repository" --color "$(core.modules.tasks.drivers.github::status_color "$status")" \
      --description "dot task: $status" --force >/dev/null
  done < <(core.modules.tasks.service::statuses)
  dot::save_config "$TASK_REPOSITORY_KEY" "$repository"
}

core.modules.tasks.drivers.github::create() {
  local title="$1" status="$2" body="$3" repository url number
  core.modules.tasks.drivers.github::require_cli
  repository=$(core.modules.tasks.drivers.github::repository) || return 1
  url=$(framework.integrations.github-cli.service::run issue create --repo "$repository" --title "$title" --body-file "$body" --label "$TASK_LABEL") \
    || dot::abort "Could not create the issue in $repository."
  number="${url##*/}"
  [[ "$number" =~ ^[0-9]+$ ]] || dot::abort "Unexpected reply from gh: $url"
  core.modules.tasks.drivers.github::apply_status "$repository" "$number" "$status" "$TASK_LABEL"
  printf '#%s\n' "$number"
}

core.modules.tasks.drivers.github::list() {
  local repository
  core.modules.tasks.drivers.github::require_cli
  repository=$(core.modules.tasks.drivers.github::repository) || return 1
  framework.integrations.github-cli.service::run issue list --repo "$repository" --label "$TASK_LABEL" --state all --limit "$TASK_ISSUE_LIMIT" \
    --json "$TASK_ISSUE_FIELDS" --jq ".[] | $TASK_JQ_ROW" | core.modules.tasks.drivers.github::local_times
}

core.modules.tasks.drivers.github::show() {
  local repository number
  core.modules.tasks.drivers.github::require_cli
  repository=$(core.modules.tasks.drivers.github::repository) || return 1
  number=$(core.modules.tasks.drivers.github::number "$1") || return 1
  core.modules.tasks.drivers.github::labels "$repository" "$number" >/dev/null
  framework.integrations.github-cli.service::run issue view "$number" --repo "$repository" --json "$TASK_ISSUE_FIELDS" --jq "$TASK_JQ_ROW" | core.modules.tasks.drivers.github::local_times
  framework.integrations.github-cli.service::run issue view "$number" --repo "$repository" --json body --jq .body
}

core.modules.tasks.drivers.github::update() {
  local repository number arguments=()
  core.modules.tasks.drivers.github::require_cli
  repository=$(core.modules.tasks.drivers.github::repository) || return 1
  number=$(core.modules.tasks.drivers.github::number "$1") || return 1
  core.modules.tasks.drivers.github::labels "$repository" "$number" >/dev/null
  [ -z "$2" ] || arguments+=(--title "$2")
  [ -z "$3" ] || arguments+=(--body-file "$3")
  framework.integrations.github-cli.service::run issue edit "$number" --repo "$repository" ${arguments[@]+"${arguments[@]}"} >/dev/null
}

core.modules.tasks.drivers.github::status() {
  local repository number labels
  core.modules.tasks.drivers.github::require_cli
  repository=$(core.modules.tasks.drivers.github::repository) || return 1
  number=$(core.modules.tasks.drivers.github::number "$1") || return 1
  labels=$(core.modules.tasks.drivers.github::labels "$repository" "$number") || return 1
  core.modules.tasks.drivers.github::apply_status "$repository" "$number" "$2" "$labels"
}

core.modules.tasks.drivers.github::delete() {
  local repository number
  core.modules.tasks.drivers.github::require_cli
  repository=$(core.modules.tasks.drivers.github::repository) || return 1
  number=$(core.modules.tasks.drivers.github::number "$1") || return 1
  core.modules.tasks.drivers.github::labels "$repository" "$number" >/dev/null
  framework.integrations.github-cli.service::run issue delete "$number" --repo "$repository" --yes >/dev/null
}

core.modules.tasks.drivers.github::link() {
  local repository number
  repository=$(core.modules.tasks.drivers.github::repository) || return 1
  number=$(core.modules.tasks.drivers.github::number "$1") || return 1
  printf '%s/issues/%s\n' "$(framework.integrations.github-api.service::url "$repository")" "$number"
}
