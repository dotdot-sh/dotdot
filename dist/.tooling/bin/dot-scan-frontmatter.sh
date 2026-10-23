#!/usr/bin/env bash
# description: Print only the frontmatter of dotdot Markdown docs.

set -eu

usage() {
  cat <<'EOF'
bash dot scan:frontmatter — print each *.md file's frontmatter block verbatim,
one file at a time, without the rest of the body.

Lets a skill or agent survey a directory of dotdot *.md-style files (e.g.
Features/, Decisions/) cheaply — enough to judge relevance or
spot duplicates without spending context on the full bodies. Read a file in
full only once its frontmatter says it's worth it.

Dumps whatever fields a file actually declares rather than picking out a
fixed set, so files with extra keys (ignore, status, tags, ...) survey
just as well as ones with only name/description.

Usage:
  bash dot scan:frontmatter <directory|file.md>
  bash dot scan:frontmatter --help

Arguments:
  <directory>   Scan every *.md directly inside it, separated by a rule.
  <file.md>     Scan just that one file.

Notes:
  - A relative path is dotdot-relative, so "Features" and
    ".dot/Features" mean the same thing from any working directory.
    A path that resolves outside dotdot is rejected, not scanned.
  - Output paths are printed dotdot-relative, ready to pass to another tool.
  - A file with no frontmatter is reported as "(no frontmatter)" rather than
    skipped, which is how you spot docs still missing one.
EOF
}

case "${1-}" in
  -h|--help) usage; exit 0 ;;
esac

. "$(dirname "$0")/lib/dot-paths.sh"

[ $# -eq 1 ] || { usage >&2; exit 1; }
REL=$1
# Trim trailing slashes so listed paths read Features/X.md, not //X.md.
while [ "${REL%/}" != "$REL" ] && [ "$REL" != "/" ]; do REL=${REL%/}; done
# A relative path is dotdot-relative, so "Features" means the same thing
# whatever the caller's working directory is — and confined to dotdot, so an
# absolute path or a "../.." cannot turn this into a reader for any .md on the
# machine.
if ! TARGET=$(resolve_within "$(dotdot_path "$REL")" "$DOTDOT_ROOT"); then
  echo "❌ Path resolves outside the dotdot directory: $REL" >&2
  exit 1
fi

# Rule spans the terminal when attached to one, else a plain 80 columns.
width=$(tput cols 2>/dev/null) || width=""
case "$width" in
  ''|*[!0-9]*) width=${COLUMNS:-80} ;;
esac
case "$width" in
  ''|*[!0-9]*) width=80 ;;
esac
RULE=$(awk -v n="$width" 'BEGIN { while (i++ < n) printf "-"; print "" }')

# Prints one file's path — dotdot-relative, the way a skill would refer to it —
# followed by its frontmatter block.
emit() {
  printf '%s\n' "$2"
  awk '
    NR == 1 && $0 == "---" { infm = 1; hasfm = 1; next }
    infm && $0 == "---" { exit }
    infm { print }
    END { if (!hasfm) print "(no frontmatter)" }
  ' "$1"
}

if [ -d "$TARGET" ]; then
  found=0
  for f in "$TARGET"/*.md; do
    [ -e "$f" ] || continue
    # The directory being inside dotdot says nothing about where its entries
    # point: a symlink dropped in here would otherwise be opened and have its
    # target's frontmatter printed. Each child is confined on its own.
    if ! resolve_within "$f" "$DOTDOT_ROOT" >/dev/null; then
      printf '❌ skipped, resolves outside dotdot: %s\n' "$REL/$(basename "$f")" >&2
      continue
    fi
    [ "$found" -eq 1 ] && printf '%s\n' "$RULE"
    found=1
    emit "$f" "$REL/$(basename "$f")"
  done
  [ "$found" -eq 1 ] || echo "(no .md files in $REL)"
elif [ -f "$TARGET" ]; then
  case "$REL" in
    *.md) ;;
    *) echo "❌ Not a Markdown file: $REL" >&2; exit 1 ;;
  esac
  emit "$TARGET" "$REL"
else
  echo "❌ Not a directory or Markdown file: $REL" >&2; exit 1
fi
