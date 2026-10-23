#!/usr/bin/env bash
# description: Plain Markdown files in dotdot's Tasks/ directory (t001--slug.md).
#
# A task service for the bash dot task:* commands; see bin/lib/dot-tasks.sh
# for the contract.
# Each task is one file: frontmatter (title, status, created, updated) and the
# body. The number is the id ("t004"); the slug comes from the title at
# creation and stays, so links to the file never break.

set -euo pipefail

. "$(dirname "$0")/../lib/dot-paths.sh"
. "$(dirname "$0")/../lib/dot-decisions.sh"

die() {
  echo "❌ $*" >&2
  exit 1
}

now() {
  date '+%Y-%m-%d %H:%M:%S'
}

slugify() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//' | cut -c 1-60 | sed 's/-$//'
}

# Prints the file of task $1 ("4", "004", "t004", a filename), or fails.
task_file() {
  local num matches=()
  num=$(record_ref_num "$1") || die "Invalid task id: $1"
  for f in "$TASKS_DIR/$TASK_PREFIX$num$RECORD_SEP"*.md; do
    [ -f "$f" ] && matches+=("$f")
  done
  [ ${#matches[@]} -gt 0 ] || die "No task $TASK_PREFIX$num in $(dotdot_rel "$TASKS_DIR")/."
  [ ${#matches[@]} -eq 1 ] || die "More than one file for task $TASK_PREFIX$num in $(dotdot_rel "$TASKS_DIR")/."
  printf '%s\n' "${matches[0]}"
}

# Prints frontmatter field $2 of file $1.
field() {
  awk -v k="$2" '
    NR == 1 && $0 == "---" { fm = 1; next }
    fm && $0 == "---" { exit }
    fm && index($0, k ":") == 1 { v = substr($0, length(k) + 2); sub(/^ /, "", v); print v; exit }
  ' "$1"
}

# Prints the body of file $1: everything after the frontmatter, minus the
# blank lines that separate them.
body() {
  awk '
    NR == 1 && $0 == "---" { fm = 1; next }
    fm == 1 && $0 == "---" { fm = 2; next }
    fm == 1 { next }
    !started && $0 == "" { next }
    { started = 1; print }
  ' "$1"
}

# Writes file $1 from its fields and a body file, through a temp file.
write_task() {
  local file=$1 title=$2 status=$3 created=$4 updated=$5 body_file=$6
  {
    printf -- '---\ntitle: %s\nstatus: %s\ncreated: %s\nupdated: %s\n---\n\n' "$title" "$status" "$created" "$updated"
    cat -- "$body_file"
  } > "$file.tmp-$$" && mv -f -- "$file.tmp-$$" "$file"
}

# Prints file $1 as the contract's TSV line.
tsv() {
  local num
  num=$(record_num "$(basename -- "$1")")
  printf '%s%s\t%s\t%s\t%s\t%s\n' "$TASK_PREFIX" "$num" "$(field "$1" status)" "$(field "$1" created)" "$(field "$1" updated)" "$(field "$1" title)"
}

verb=${1-}
shift || true
case "$verb" in
  init)
    mkdir -p -- "$TASKS_DIR" || die "Could not create $(dotdot_rel "$TASKS_DIR")/."
    echo "Tasks are files in $(dotdot_rel "$TASKS_DIR")/."
    ;;
  create)
    title=$1 status=$2 body_file=$3
    slug=$(slugify "$title")
    [ -n "$slug" ] || slug=task
    mkdir -p -- "$TASKS_DIR"
    max=0
    for f in "$TASKS_DIR/$TASK_PREFIX"[0-9]*"$RECORD_SEP"*.md; do
      [ -e "$f" ] || continue
      n=$(record_num "$(basename -- "$f")" | sed 's/^0*//')
      [ "${n:-0}" -gt "$max" ] && max=$n
    done
    num=$(printf '%03d' $((max + 1)))
    file="$TASKS_DIR/$TASK_PREFIX$num$RECORD_SEP$slug.md"
    [ ! -e "$file" ] || die "$(dotdot_rel "$file") already exists (unexpected — try again)."
    stamp=$(now)
    write_task "$file" "$title" "$status" "$stamp" "$stamp" "$body_file"
    printf '%s%s\n' "$TASK_PREFIX" "$num"
    ;;
  list)
    for f in "$TASKS_DIR/$TASK_PREFIX"[0-9]*"$RECORD_SEP"*.md; do
      [ -f "$f" ] && tsv "$f"
    done
    true
    ;;
  show)
    file=$(task_file "$1")
    tsv "$file"
    body "$file"
    ;;
  update)
    file=$(task_file "$1")
    title=${2:-$(field "$file" title)}
    if [ -n "$3" ]; then
      body_file=$3
    else
      body_file=$(mktemp) && trap 'rm -f -- "$body_file"' EXIT
      body "$file" > "$body_file"
    fi
    write_task "$file" "$title" "$(field "$file" status)" "$(field "$file" created)" "$(now)" "$body_file"
    ;;
  status)
    file=$(task_file "$1")
    body_file=$(mktemp) && trap 'rm -f -- "$body_file"' EXIT
    body "$file" > "$body_file"
    write_task "$file" "$(field "$file" title)" "$2" "$(field "$file" created)" "$(now)" "$body_file"
    ;;
  delete)
    file=$(task_file "$1")
    rm -f -- "$file"
    ;;
  link)
    dotdot_rel "$(task_file "$1")"
    ;;
  *) die "Unknown verb: $verb" ;;
esac
