#!/usr/bin/env bash
# dot-tasks.sh — what every task:* command shares: the selected service, the
# task template (statuses and body sections), the checks on what comes in,
# and the editor a person gets at a terminal.
#
# The task:* commands own the command line, every check and every line
# printed; the selected service script only stores and fetches. Services live
# in bin/task/dot-task-<service>.sh, out of the command list, and are picked
# once per project with task:initialize.
#
# Service contract — bash dot-task-<service>.sh <verb> [args], arguments
# already validated, errors on stderr with a non-zero exit, times as
# "YYYY-MM-DD HH:mm:ss" in local time:
#   init                          interactive setup on a terminal
#   create <title> <status> <body-file>   prints the new task's id
#   list                          every task, one TSV line each:
#                                 id, status, created, updated, title
#   show <id>                     that TSV line, then the body
#   update <id> <title> <body-file>       "" leaves either unchanged
#   status <id> <status>
#   delete <id>
#   link <id>                     where the task lives: a URL, or a file path
#                                 relative to the project root
#
# Source it after lib/dot-paths.sh and lib/dot-kv.sh.

if [ -t 1 ]; then
  BOLD=$'\033[1m'; RED=$'\033[31m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'; CYAN=$'\033[36m'; RESET=$'\033[0m'
else
  BOLD=""; RED=""; GREEN=""; YELLOW=""; CYAN=""; RESET=""
fi

TMP=$(mktemp -d) || { echo "❌ Could not create a temp directory" >&2; exit 1; }
trap 'rm -rf -- "$TMP"' EXIT INT TERM HUP

ID_PATTERN='^#?[A-Za-z0-9][A-Za-z0-9._-]*$'

die() {
  printf '%s❌ %s%s\n' "$RED" "$*" "$RESET" >&2
  exit 1
}

slugify() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//'
}

# A person at a terminal rather than an agent or a script: both ends are a
# terminal. An agent's shell has neither.
interactive() {
  [ -t 0 ] && [ -t 1 ]
}

# --- template --------------------------------------------------------------
[ -f "$TASK_TEMPLATE" ] || die "Template not found: $(dotdot_rel "$TASK_TEMPLATE")"

# The statuses the template lists as "{a | b | c}"; the first is a new task's.
STATUSES=$(grep -m1 '^status:' "$TASK_TEMPLATE" | sed -n 's/.*{\(.*\)}.*/\1/p' | tr '|' '\n' | sed -E 's/^ +//; s/ +$//' | grep -v '^$')
[ -n "$STATUSES" ] || die "No statuses in $(dotdot_rel "$TASK_TEMPLATE")"
DEFAULT_STATUS=$(printf '%s\n' "$STATUSES" | head -n 1)

# The body's sections, one "## " heading each; each takes a flag of its slug.
SECTIONS=$(grep '^## ' "$TASK_TEMPLATE" | sed 's/^## //')

section_key() {
  slugify "$1"
}

is_status() {
  printf '%s\n' "$STATUSES" | grep -qxF -- "$1"
}

# Prints the help lines for the section flags.
section_flags_help() {
  local section
  while IFS= read -r section; do
    printf '  --%-26s %s\n' "$(section_key "$section")" "$section"
  done <<<"$SECTIONS"
}

# --- service ---------------------------------------------------------------
SERVICE=""

# Loads the selected service into $SERVICE. Without one, a person at a
# terminal picks it now (task:initialize); anyone else is told to ask them.
ensure_service() {
  if ! kv_get "$TASKS_CONF" service >/dev/null 2>&1; then
    interactive || die "Tasks are not set up yet. Ask the user to run bash dot task:initialize in a terminal."
    printf '%sTasks are not set up yet.%s\n' "$YELLOW" "$RESET"
    bash "$BIN_DIR/dot-task-initialize.sh" || exit 1
  fi
  local service
  service=$(kv_get "$TASKS_CONF" service) || die "No task service selected."
  [[ "$service" =~ ^[a-z0-9][a-z0-9-]*$ ]] || die "Invalid service in $(dotdot_rel "$TASKS_CONF"): $service"
  SERVICE="$TASK_SERVICES_DIR/dot-task-$service.sh"
  [ -f "$SERVICE" ] || die "Task service \"$service\" is not installed (no bin/task/dot-task-$service.sh)."
}

# Runs the service with verb and arguments "$@". On a terminal, a call that
# takes longer than a blink (a network round trip) shows a fruit spinner on
# stderr meanwhile; the service's own messages follow once it is cleared.
SPINNER_FRAMES=(🍏 🍊 🍋 🍑 🥭 🥝 🍉 🍐 🍓)
svc() {
  if [ ! -t 2 ]; then
    bash "$SERVICE" "$@"
    return
  fi
  local err="$TMP/svc.err" pid rc=0 tick=0 drawn=false
  bash "$SERVICE" "$@" 2> "$err" &
  pid=$!
  while kill -0 "$pid" 2>/dev/null; do
    if [ "$tick" -ge 2 ]; then
      printf '\r%s ' "${SPINNER_FRAMES[$(( (tick - 2) % ${#SPINNER_FRAMES[@]} ))]}" >&2
      drawn=true
    fi
    tick=$((tick + 1))
    sleep 0.12
  done
  wait "$pid" || rc=$?
  $drawn && printf '\r\033[K' >&2
  cat -- "$err" >&2
  return "$rc"
}

# Prints where task $1 lives, indented, for the line after a ✅.
print_link() {
  local link
  link=$(svc link "$1") && [ -n "$link" ] && printf '   %s\n' "$link"
  return 0
}

# --- input -----------------------------------------------------------------
check_title() {
  [ -n "$1" ] || die "The title can't be empty"
  case "$1" in *$'\n'* | *$'\t'*) die "The title must be one line" ;; esac
}

check_id() {
  [ -n "${1-}" ] || die "Missing the task id. Run bash dot task:list to see them."
  [[ "$1" =~ $ID_PATTERN ]] || die "Invalid task id: $1"
}

# Records the content given for section flag --$1 in $TMP/sec_<key>.
SET_SECTIONS=()
set_section() {
  local key=$1 value=$2 section found=""
  while IFS= read -r section; do
    [ "$(section_key "$section")" = "$key" ] && found=$section
  done <<<"$SECTIONS"
  [ -n "$found" ] || return 1
  printf '%s' "$value" > "$TMP/sec_$key"
  SET_SECTIONS+=("$found")
}

# Reads a --body-file argument into file $2: "-" is stdin, anything else a
# file that has to sit inside the project.
read_body_file() {
  if [ "$1" = "-" ]; then
    cat > "$2"
    return
  fi
  local path
  path=$(resolve_within "$1" "$BASE") || die "--body-file must be inside the project: $1"
  [ -f "$path" ] || die "--body-file not found: $1"
  cat -- "$path" > "$2"
}

# --- body ------------------------------------------------------------------
# Prints a full body from the template: the sections given, "None" for the rest.
compose_body() {
  local section key
  while IFS= read -r section; do
    key=$(section_key "$section")
    printf '## %s\n\n' "$section"
    if [ -s "$TMP/sec_$key" ]; then cat "$TMP/sec_$key"; else printf 'None'; fi
    printf '\n\n'
  done <<<"$SECTIONS"
}

# Replaces section $2's content in body file $1 with file $3's, appending the
# section when the body lacks it.
replace_section() {
  awk -v h="## $2" -v f="$3" '
    function emit(  line) {
      print h; print ""
      while ((getline line < f) > 0) print line
      close(f); print ""
    }
    $0 == h { emit(); skip = 1; done = 1; next }
    skip && /^## / { skip = 0 }
    !skip { print }
    END { if (!done) { print ""; emit() } }
  ' "$1" > "$1.new" && mv -f -- "$1.new" "$1"
}

# Applies every section flag given to body file $1.
apply_sections() {
  local section
  for section in "${SET_SECTIONS[@]+"${SET_SECTIONS[@]}"}"; do
    replace_section "$1" "$section" "$TMP/sec_$(section_key "$section")"
  done
}

# --- editor ----------------------------------------------------------------
# Adds the template's guidance under each empty ("None") section of body file
# $1 as an HTML comment, so a person editing it sees what goes where.
# The guidance goes right under the heading, with two blank lines below it to
# write in.
add_guidance() {
  awk -v t="$TASK_TEMPLATE" '
    BEGIN {
      while ((getline line < t) > 0) {
        if (line ~ /^## /) { h = line; continue }
        if (h == "" || line == "") continue
        if (h in g) g[h] = g[h] " " line; else g[h] = line
      }
      h = ""
    }
    function flush() {
      sub(/\n+$/, "", body)
      if (h == "") { if (body != "") { print body; print "" } }
      else if (body == "None" && (h in g)) { print h; print "<!-- " g[h] " -->"; print ""; print "" }
      else { print h; print ""; print body; print "" }
      body = ""
    }
    /^## / { flush(); h = $0; next }
    { if ($0 == "" && body == "") next; body = (body == "" ? $0 : body "\n" $0) }
    END { flush() }
  ' "$1" > "$1.new" && mv -f -- "$1.new" "$1"
}

# Drops the guidance comments again, and writes "None" into any section left
# empty, so an untouched section reads the same as one never given.
strip_guidance() {
  awk '
    function flush() {
      sub(/\n+$/, "", body)
      if (h != "") { print h; print ""; print (body == "" ? "None" : body); print "" }
      else if (body != "") { print body; print "" }
      body = ""
    }
    /^<!-- .* -->$/ { next }
    /^## / { flush(); h = $0; next }
    {
      if ($0 == "" && body == "") next
      body = (body == "" ? $0 : body "\n" $0)
    }
    END { flush() }
  ' "$1" | awk 'NF || seen { print } { if (NF) seen = 1 }' > "$1.new"
  # Trailing blank lines from the last section are dropped too.
  printf '%s\n' "$(cat "$1.new")" > "$1" && rm -f -- "$1.new"
}

# Opens body file $1 in the person's editor ($VISUAL, $EDITOR, else nano or
# vi), template guidance included, and fails when they leave it empty or the
# editor fails.
edit_body() {
  interactive || die "--editor needs a terminal."
  local editor=${VISUAL:-${EDITOR:-}} edit="$TMP/task.md"
  if [ -z "$editor" ]; then
    if command -v nano >/dev/null; then editor=nano; elif command -v vi >/dev/null; then editor=vi; else
      die "No editor found; set \$EDITOR, or pass the content as flags."
    fi
  fi
  cp -- "$1" "$edit"
  add_guidance "$edit"
  # As git does: $EDITOR may carry its own arguments ("code --wait").
  sh -c "$editor \"\$1\"" sh "$edit" </dev/tty >/dev/tty || die "The editor exited with an error — nothing saved."
  grep -q '[^[:space:]]' "$edit" || die "The task was left empty — nothing saved."
  strip_guidance "$edit"
  cp -- "$edit" "$1"
}
