#!/usr/bin/env bash

dot::use framework.helpers.fs

FRONTMATTER_FENCE="---"

framework.helpers.frontmatter::exists() {
  [ "$(head -n 1 -- "$1" 2>/dev/null)" = "$FRONTMATTER_FENCE" ]
}

framework.helpers.frontmatter::block() {
  awk -v fence="$FRONTMATTER_FENCE" '
    NR == 1 && $0 == fence { inside = 1; next }
    inside && $0 == fence { exit }
    inside { print }
  ' "$1"
}

framework.helpers.frontmatter::field() {
  awk -v fence="$FRONTMATTER_FENCE" -v key="$2" '
    NR == 1 && $0 == fence { inside = 1; next }
    inside && $0 == fence { exit }
    inside && index($0, key ":") == 1 {
      value = substr($0, length(key) + 2)
      sub(/^[ \t]+/, "", value)
      print value
      exit
    }
  ' "$1"
}

framework.helpers.frontmatter::end_line() {
  awk -v fence="$FRONTMATTER_FENCE" '
    NR == 1 && $0 != fence { exit }
    NR > 1 && $0 == fence { print NR; found = 1; exit }
    END { if (!found) print 0 }
  ' "$1"
}

framework.helpers.frontmatter::body() {
  awk -v fence="$FRONTMATTER_FENCE" '
    NR == 1 && $0 == fence { inside = 1; next }
    inside { if ($0 == fence) inside = 0; next }
    !started && /^[ \t]*$/ { next }
    { started = 1; print }
  ' "$1"
}

framework.helpers.frontmatter::update() {
  local file="$1" assignments=""
  shift
  while [ $# -ge 2 ]; do
    assignments="$assignments$1"$'\t'"$2"$'\n'
    shift 2
  done
  awk -v fence="$FRONTMATTER_FENCE" -v assignments="$assignments" '
    BEGIN {
      count = split(assignments, lines, "\n")
      for (i = 1; i <= count; i++) {
        if (lines[i] == "") continue
        tab = index(lines[i], "\t")
        values[substr(lines[i], 1, tab - 1)] = substr(lines[i], tab + 1)
        wanted++
      }
    }
    NR == 1 && $0 == fence { inside = 1; print; next }
    inside && $0 == fence { inside = 0; print; next }
    inside {
      colon = index($0, ":")
      key = substr($0, 1, colon - 1)
      if (colon > 0 && (key in values) && !(key in done)) {
        print key ": " values[key]
        done[key] = 1
        found++
        next
      }
    }
    { print }
    END { if (found != wanted) exit 3 }
  ' "$file" > "$file.frontmatter-$$" || { rm -f -- "$file.frontmatter-$$"; return 1; }
  framework.helpers.fs::replace "$file" < "$file.frontmatter-$$"
  rm -f -- "$file.frontmatter-$$"
}
