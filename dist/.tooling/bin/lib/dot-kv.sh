#!/usr/bin/env bash
# dot-kv.sh — reads and writes dotdot's plain "KEY=VALUE" files: the task
# service config (conf/tasks.conf) and the git-ignored secrets file (.env).
#
# Both are parsed as data, line by line, and never sourced: sourcing would run
# whatever a line holds ("$(…)", backticks, a command), so a tampered file would
# execute code the moment any script read a setting. Here a value is only text.
#
# Source it after lib/dot-paths.sh:
#   . "$(dirname "$0")/lib/dot-paths.sh"
#   . "$(dirname "$0")/lib/dot-kv.sh"

KV_KEY_PATTERN='^[A-Za-z_][A-Za-z0-9_]*$'

# Prints the value of key $2 in file $1, or fails when the file or key is
# missing. Blank lines and "#" comments are skipped, an "export " prefix and one
# pair of matching surrounding quotes are dropped, nothing is expanded. The last
# occurrence of a key wins.
kv_get() {
  [[ "$2" =~ $KV_KEY_PATTERN ]] || return 1
  [ -f "$1" ] || return 1
  awk -v k="$2" '
    { sub(/\r$/, "") }
    /^[ \t]*(#|$)/ { next }
    {
      line = $0
      sub(/^[ \t]*(export[ \t]+)?/, "", line)
      i = index(line, "=")
      if (i == 0) next
      key = substr(line, 1, i - 1)
      sub(/[ \t]+$/, "", key)
      if (key != k) next
      val = substr(line, i + 1)
      sub(/^[ \t]+/, "", val); sub(/[ \t]+$/, "", val)
      if (length(val) >= 2 && (val ~ /^".*"$/ || val ~ /^\047.*\047$/)) val = substr(val, 2, length(val) - 2)
      out = val; found = 1
    }
    END { if (!found) exit 1; print out }
  ' "$1"
}

# Sets key $2 to value $3 in file $1, replacing an existing line or appending
# one, and creates the file (and its directory) when missing. The value goes in
# as given; a newline in it is refused, since it would start a new line.
kv_set() {
  [[ "$2" =~ $KV_KEY_PATTERN ]] || return 1
  case "$3" in *$'\n'*) return 1 ;; esac
  mkdir -p -- "$(dirname -- "$1")" || return 1
  [ -f "$1" ] || : > "$1" || return 1
  local tmp="$1.tmp-$$"
  # The temp copy keeps the file's mode, so a private file stays private.
  cp -p -- "$1" "$tmp" || return 1
  awk -v k="$2" -v v="$3" '
    {
      line = $0; sub(/^[ \t]*(export[ \t]+)?/, "", line)
      i = index(line, "="); key = substr(line, 1, i - 1); sub(/[ \t]+$/, "", key)
      if (i > 0 && key == k) { if (!done) print k "=" v; done = 1; next }
      print
    }
    END { if (!done) print k "=" v }
  ' "$1" > "$tmp" && mv -f -- "$tmp" "$1"
}

# Removes key $2 from file $1, every line of it, keeping the file's mode;
# fails when the key is not there.
kv_unset() {
  [[ "$2" =~ $KV_KEY_PATTERN ]] || return 1
  kv_get "$1" "$2" >/dev/null || return 1
  local tmp="$1.tmp-$$"
  cp -p -- "$1" "$tmp" || return 1
  awk -v k="$2" '
    {
      line = $0; sub(/^[ \t]*(export[ \t]+)?/, "", line)
      i = index(line, "="); key = substr(line, 1, i - 1); sub(/[ \t]+$/, "", key)
      if (i > 0 && key == k) next
      print
    }
  ' "$1" > "$tmp" && mv -f -- "$tmp" "$1"
}

# Prints secret $1 from dotdot's .env, or fails when it is not set there.
# Callers pass it straight to the tool that needs it — never print or log it.
env_get() {
  kv_get "$ENV_FILE" "$1"
}
