#!/usr/bin/env bash
# description: Create a new feature from the feature template.

set -eu

. "$(dirname "$0")/lib/dot-paths.sh"
. "$(dirname "$0")/lib/dot-decisions.sh"

TEMPLATE="$FEATURE_TEMPLATE"

# --- colors (skipped when not a terminal) ---
if [ -t 1 ]; then
  BOLD=$(printf '\033[1m'); RED=$(printf '\033[31m'); GREEN=$(printf '\033[32m')
  CYAN=$(printf '\033[36m'); RESET=$(printf '\033[0m')
else
  BOLD=""; RED=""; GREEN=""; CYAN=""; RESET=""
fi

TMPDIR_=$(mktemp -d) || { echo "Failed to create a temp directory" >&2; exit 1; }
trap 'rm -rf "$TMPDIR_"' EXIT INT TERM HUP

slugify() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//'
}

header_to_key() {
  h=$(printf '%s' "$1" | sed -E 's/\([^)]*\)//g')
  slugify "$h"
}

[ -f "$TEMPLATE" ] || { printf '%s❌ Template not found:%s %s\n' "$RED$BOLD" "$RESET" "$TEMPLATE" >&2; exit 1; }

HEADERS_FILE="$TMPDIR_/headers.txt"
grep '^## ' "$TEMPLATE" > "$HEADERS_FILE" || true
[ -s "$HEADERS_FILE" ] || { printf '%s❌ No sections found in%s %s\n' "$RED$BOLD" "$RESET" "$TEMPLATE" >&2; exit 1; }

KEYS_FILE="$TMPDIR_/keys.txt"
: > "$KEYS_FILE"
while IFS= read -r hline; do
  key=$(header_to_key "${hline#\#\# }")
  printf '%s\n' "$key" >> "$KEYS_FILE"
done < "$HEADERS_FILE"

usage() {
  cat <<EOF
bash dot document:feature — create a new feature file in Features/ from the
bundled feature template, numbering and naming it automatically.

The template (.dot/.tooling/skills/dot-document-feature/feature-template.md) is the
single source of truth: this script reads it at run time and derives one
flag per section from its headings, so adding a section there makes the flag
appear here with nothing to keep in sync by hand. It also scans
Features/ for the highest existing number and takes the next one —
which is why the filename and number are never to be constructed by hand.

Usage:
  bash dot document:feature --name <text> --description <text> [section flags...]
  bash dot document:feature --help

All flags except --name and --description are optional; sections left unset
are written as "None", the convention for a section with nothing relevant in
it. This script only creates — to change an existing feature, edit its file
directly, preserving its frontmatter name and number.

Required:
  --name <text>          Feature name/title — becomes the file's slug and frontmatter name.
  --description <text>   One-line summary — used as the frontmatter description and the Description section.

Section flags (derived live from $(basename "$(dirname "$TEMPLATE")")/$(basename "$TEMPLATE")):
EOF
  while IFS= read -r hline; do
    header="${hline#\#\# }"
    key=$(header_to_key "$header")
    [ "$key" = "description" ] && continue
    printf '  --%-28s %s\n' "$key" "$header"
  done < "$HEADERS_FILE"
  cat <<EOF

Examples:
  bash dot document:feature \\
    --name "Password reset" \\
    --description "Lets a user reset a forgotten password via an emailed link." \\
    --specification "Given a registered user ... When ... Then ..." \\
    --related-features "7"
EOF
}

die() {
  printf '%s❌ %s%s\n\n' "$RED$BOLD" "$1" "$RESET" >&2
  usage >&2
  exit 1
}

if [ $# -eq 0 ]; then
  usage >&2
  exit 1
fi

NAME_VAL=""
have_name=0
have_description=0

while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    --name)
      [ $# -ge 2 ] || die "--name requires a value"
      NAME_VAL="$2"
      have_name=1
      shift 2
      ;;
    --*)
      key="${1#--}"
      # -F, because the flag name is data, not a pattern: without it "--.*"
      # matches every key line and slips past this check, and whatever it
      # contains then becomes part of a filename below.
      if ! grep -qxF -- "$key" "$KEYS_FILE"; then
        die "unknown flag --$key"
      fi
      [ $# -ge 2 ] || die "--$key requires a value"
      printf '%s' "$2" > "$TMPDIR_/sec_$key"
      [ "$key" = "description" ] && have_description=1
      shift 2
      ;;
    *)
      die "unexpected argument: $1 (flags must be given as --name value)"
      ;;
  esac
done

[ "$have_name" -eq 1 ] || die "missing required --name"
[ "$have_description" -eq 1 ] || die "missing required --description"

SLUG=$(slugify "$NAME_VAL")
[ -n "$SLUG" ] || die "--name must contain at least one letter or number"

mkdir -p "$FEATURES_DIR"

max=0
for f in "$FEATURES_DIR"/"$FEATURE_PREFIX"[0-9]*"$RECORD_SEP"*.md; do
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

TARGET="$FEATURES_DIR/$FEATURE_PREFIX$NUM$RECORD_SEP$SLUG.md"
[ -e "$TARGET" ] && die "target already exists: $TARGET (unexpected — try again)"

DESC_ONELINE=$(tr '\n' ' ' < "$TMPDIR_/sec_description" | sed -E 's/  +/ /g; s/^ +//; s/ +$//')

OUT="$TMPDIR_/out.md"
{
  printf -- '---\n'
  printf 'name: %s\n' "$SLUG"
  printf 'description: %s\n' "$DESC_ONELINE"
  printf -- '---\n\n'
  while IFS= read -r hline; do
    header="${hline#\#\# }"
    key=$(header_to_key "$header")
    printf '## %s\n\n' "$header"
    if [ -s "$TMPDIR_/sec_$key" ]; then
      cat "$TMPDIR_/sec_$key"
    else
      printf 'None'
    fi
    printf '\n\n'
  done < "$HEADERS_FILE"
} > "$OUT"

# normalize trailing blank lines to a single trailing newline
CONTENT=$(cat "$OUT")
printf '%s\n' "$CONTENT" > "$TMPDIR_/final.md"
mv "$TMPDIR_/final.md" "$TARGET"

REL_TARGET="Features/$FEATURE_PREFIX$NUM$RECORD_SEP$SLUG.md"
printf '\n%s✨ %sFeature %s documented%s\n' "$CYAN" "$BOLD" "$NUM" "$RESET"
printf '%s✅ %s%s%s\n\n' "$GREEN$BOLD" "$RESET$GREEN" "$REL_TARGET" "$RESET"
