#!/usr/bin/env bash
# description: Create a new, empty note in Notes/ with the next number.

set -eu

. "$(dirname "$0")/lib/dot-paths.sh"
. "$(dirname "$0")/lib/dot-decisions.sh"

DEFAULT_SLUG="template"

# --- colors (skipped when not a terminal) ---
if [ -t 1 ]; then
  BOLD=$(printf '\033[1m'); RED=$(printf '\033[31m'); GREEN=$(printf '\033[32m')
  CYAN=$(printf '\033[36m'); RESET=$(printf '\033[0m')
else
  BOLD=""; RED=""; GREEN=""; CYAN=""; RESET=""
fi

slugify() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//'
}

usage() {
  cat <<EOF
bash dot note — create a new, empty note file in Notes/, numbering
and naming it automatically.

It scans Notes/ for the highest existing number and takes the next one —
which is why the filename and number are never to be constructed by hand.
The file is created empty; write the note into it afterwards.

Usage:
  bash dot note [--slug <text>]
  bash dot note --help

Optional:
  --slug <text>   Short name for the file, turned into a slug ("Cache idea"
                  becomes "cache-idea"). Defaults to "$DEFAULT_SLUG".

Examples:
  bash dot note
    → Notes/${NOTE_PREFIX}004${RECORD_SEP}$DEFAULT_SLUG.md
  bash dot note --slug "Cache idea"
    → Notes/${NOTE_PREFIX}004${RECORD_SEP}cache-idea.md
EOF
}

die() {
  printf '%s❌ %s%s\n\n' "$RED$BOLD" "$1" "$RESET" >&2
  usage >&2
  exit 1
}

SLUG_VAL="$DEFAULT_SLUG"

while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    --slug)
      [ $# -ge 2 ] || die "--slug requires a value"
      SLUG_VAL="$2"
      shift 2
      ;;
    *)
      die "unexpected argument: $1"
      ;;
  esac
done

SLUG=$(slugify "$SLUG_VAL")
[ -n "$SLUG" ] || die "--slug must contain at least one letter or number"

mkdir -p "$NOTES_DIR"

max=0
for f in "$NOTES_DIR"/"$NOTE_PREFIX"[0-9]*"$RECORD_SEP"*.md; do
  [ -e "$f" ] || continue
  num=$(record_num "$(basename "$f")")
  case "$num" in
    ''|*[!0-9]*) continue ;;
  esac
  n=$(printf '%s' "$num" | sed 's/^0*//')
  [ -z "$n" ] && n=0
  [ "$n" -gt "$max" ] && max=$n
done
NUM=$(printf '%03d' $((max + 1)))

NAME="$NOTE_PREFIX$NUM$RECORD_SEP$SLUG.md"
TARGET="$NOTES_DIR/$NAME"
[ -e "$TARGET" ] && die "target already exists: $TARGET (unexpected — try again)"

: > "$TARGET"

printf '\n%s📝 %sNote %s created%s\n' "$CYAN" "$BOLD" "$NUM" "$RESET"
printf '%s✅ %s%s%s\n\n' "$GREEN$BOLD" "$RESET$GREEN" "Notes/$NAME" "$RESET"
