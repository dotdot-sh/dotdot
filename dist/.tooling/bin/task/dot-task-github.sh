#!/usr/bin/env bash
# description: GitHub issues labelled "task", through the gh CLI.
#
# A task service for the bash dot task:* commands; see bin/lib/dot-tasks.sh
# for the contract.
# A task is an issue carrying the sticky "task" label, and only such issues
# are ever read or changed: an id naming any other issue is refused. The
# issue number is the id ("#12"). Every status is a "task:<status>" label,
# one per issue, and done and discarded also close it:
#   todo       open,                     "task:todo"       purple
#   doing      open,                     "task:doing"      blue
#   paused     open,                     "task:paused"     yellow
#   done       closed as completed,      "task:done"       green
#   discarded  closed as not planned,    "task:discarded"  gray
# A status the template gains later is an open issue with its own label;
# rerun task:initialize to create it. An issue without a status label reads
# as todo when open and done when closed.
#
# gh authenticates as it normally does (gh auth login). A GH_TOKEN in the
# dotdot's .env, when set, is used instead and passed to gh only. The repository
# is chosen at init and kept in conf/tasks.conf as github_repo.

set -euo pipefail

. "$(dirname "$0")/../lib/dot-paths.sh"
. "$(dirname "$0")/../lib/dot-kv.sh"
. "$(dirname "$0")/../lib/dot-tasks.sh"
. "$(dirname "$0")/../lib/dot-confirm.sh"

TASK_LABEL="task"
STATUS_LABEL_PREFIX="task:"
CLOSED_STATUSES=" done discarded "
REPO_PATTERN='^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$'

die() {
  echo "❌ $*" >&2
  exit 1
}

command -v gh >/dev/null || die "The GitHub CLI (gh) is required: https://cli.github.com"
export GH_PROMPT_DISABLED=1
if token=$(env_get GH_TOKEN 2>/dev/null) && [ -n "$token" ]; then
  export GH_TOKEN="$token"
fi
unset token

# The issue's status, from its state and labels, as a jq expression.
JQ_STATUS='([.labels[].name | select(startswith("'"$STATUS_LABEL_PREFIX"'")) | ltrimstr("'"$STATUS_LABEL_PREFIX"'")] | first)
  // (if .state == "CLOSED" then "done" else "todo" end)'
JQ_TSV='["#\(.number)", ('"$JQ_STATUS"'), .createdAt, .updatedAt, .title] | @tsv'

# Turns the contract's TSV lines on stdin from ISO times into local ones.
local_times() {
  local id status created updated title
  while IFS=$'\t' read -r id status created updated title; do
    printf '%s\t%s\t%s\t%s\t%s\n' "$id" "$status" \
      "$(date -d "$created" '+%Y-%m-%d %H:%M:%S')" "$(date -d "$updated" '+%Y-%m-%d %H:%M:%S')" "$title"
  done
}

# A status's label color: GitHub's purple, blue, yellow, green, and gray.
status_color() {
  case "$1" in
    todo) echo 8250DF ;;
    doing) echo 0969DA ;;
    paused) echo FBCA04 ;;
    done) echo 1A7F37 ;;
    discarded) echo 6E7781 ;;
    *) echo BFD4F2 ;;
  esac
}

repo() {
  local r
  r=$(kv_get "$TASKS_CONF" github_repo 2>/dev/null) || die "No github_repo in $(dotdot_rel "$TASKS_CONF"); run bash dot task:initialize."
  [[ "$r" =~ $REPO_PATTERN ]] || die "Invalid github_repo in $(dotdot_rel "$TASKS_CONF"): $r"
  printf '%s\n' "$r"
}

# Prints the issue number of id $1 ("12" or "#12"), or fails.
number() {
  local n=${1#\#}
  [[ "$n" =~ ^[0-9]+$ ]] || die "Invalid GitHub task id: $1 (use the issue number, e.g. #12)"
  printf '%s\n' "$n"
}

# Prints issue $1's labels, one per line, and fails unless it is a task.
task_labels() {
  local labels
  labels=$(gh issue view "$1" --repo "$REPO" --json labels --jq '.labels[].name') || die "Could not read issue #$1 in $REPO."
  printf '%s\n' "$labels" | grep -qxF "$TASK_LABEL" || die "Issue #$1 is not a task (no \"$TASK_LABEL\" label); it was left alone."
  printf '%s\n' "$labels"
}

# Moves issue $1 to status $2, given its current labels in $3.
set_status() {
  local n=$1 status=$2 labels=$3 l remove=() add=() state
  while IFS= read -r l; do
    case "$l" in
      "$STATUS_LABEL_PREFIX"*) [ "$l" = "$STATUS_LABEL_PREFIX$status" ] || remove+=(--remove-label "$l") ;;
    esac
  done <<<"$labels"
  printf '%s\n' "$labels" | grep -qxF "$STATUS_LABEL_PREFIX$status" || add+=(--add-label "$STATUS_LABEL_PREFIX$status")
  if [ ${#remove[@]} -gt 0 ] || [ ${#add[@]} -gt 0 ]; then
    gh issue edit "$n" --repo "$REPO" "${remove[@]+"${remove[@]}"}" "${add[@]+"${add[@]}"}" >/dev/null
  fi
  state=$(gh issue view "$n" --repo "$REPO" --json state --jq .state)
  case "$CLOSED_STATUSES" in
    *" $status "*)
      local reason=completed
      [ "$status" = discarded ] && reason="not planned"
      # done <-> discarded: reopen first, so the close reason follows.
      if [ "$state" = CLOSED ] && [ ${#remove[@]} -gt 0 ]; then
        gh issue reopen "$n" --repo "$REPO" >/dev/null
        state=OPEN
      fi
      if [ "$state" = OPEN ]; then
        gh issue close "$n" --repo "$REPO" --reason "$reason" >/dev/null
      fi
      ;;
    *) [ "$state" = OPEN ] || gh issue reopen "$n" --repo "$REPO" >/dev/null ;;
  esac
}

init() {
  [ -t 0 ] || die "Setting up GitHub tasks needs a terminal."
  gh auth status >/dev/null 2>&1 || [ -n "${GH_TOKEN-}" ] || die "gh is not logged in. Run gh auth login (or set GH_TOKEN in $(dotdot_rel "$ENV_FILE")), then try again."
  local detected r
  detected=$(cd -- "$BASE" && gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null || true)
  read -r -p "GitHub repository for tasks (owner/name)${detected:+ [$detected]}: " r || r=""
  r=${r:-$detected}
  [[ "$r" =~ $REPO_PATTERN ]] || die "Not an owner/name repository: ${r:-(empty)}"
  gh repo view "$r" --json nameWithOwner >/dev/null 2>&1 || die "Can't reach $r with the current gh login."
  local status names=$TASK_LABEL
  while IFS= read -r status; do names="$names, $STATUS_LABEL_PREFIX$status"; done <<<"$STATUSES"
  echo "This creates (or updates) these labels in $r: $names."
  confirm "Continue?" || die "Cancelled."
  gh label create "$TASK_LABEL" --repo "$r" --color EDEDED --description "Managed by dotdot tasks" --force >/dev/null
  while IFS= read -r status; do
    gh label create "$STATUS_LABEL_PREFIX$status" --repo "$r" --color "$(status_color "$status")" \
      --description "dot task: $status" --force >/dev/null
  done <<<"$STATUSES"
  kv_set "$TASKS_CONF" github_repo "$r" || die "Could not write $(dotdot_rel "$TASKS_CONF")."
  echo "Tasks are issues labelled \"$TASK_LABEL\" in $r."
}

verb=${1-}
shift || true
[ "$verb" = init ] && { init; exit; }
REPO=$(repo)
case "$verb" in
  create)
    title=$1 status=$2 body_file=$3
    url=$(gh issue create --repo "$REPO" --title "$title" --body-file "$body_file" --label "$TASK_LABEL") \
      || die "Could not create the issue in $REPO."
    n=${url##*/}
    [[ "$n" =~ ^[0-9]+$ ]] || die "Unexpected reply from gh: $url"
    set_status "$n" "$status" "$TASK_LABEL"
    printf '#%s\n' "$n"
    ;;
  list)
    gh issue list --repo "$REPO" --label "$TASK_LABEL" --state all --limit 1000 \
      --json number,title,state,labels,createdAt,updatedAt --jq ".[] | $JQ_TSV" | local_times
    ;;
  show)
    n=$(number "$1")
    task_labels "$n" >/dev/null
    gh issue view "$n" --repo "$REPO" --json number,title,state,labels,createdAt,updatedAt --jq "$JQ_TSV" | local_times
    gh issue view "$n" --repo "$REPO" --json body --jq .body
    ;;
  update)
    n=$(number "$1")
    task_labels "$n" >/dev/null
    args=()
    [ -z "$2" ] || args+=(--title "$2")
    [ -z "$3" ] || args+=(--body-file "$3")
    gh issue edit "$n" --repo "$REPO" "${args[@]}" >/dev/null
    ;;
  status)
    n=$(number "$1")
    labels=$(task_labels "$n")
    set_status "$n" "$2" "$labels"
    ;;
  link)
    n=$(number "$1")
    printf 'https://github.com/%s/issues/%s\n' "$REPO" "$n"
    ;;
  delete)
    n=$(number "$1")
    task_labels "$n" >/dev/null
    gh issue delete "$n" --repo "$REPO" --yes >/dev/null
    ;;
  *) die "Unknown verb: $verb" ;;
esac
