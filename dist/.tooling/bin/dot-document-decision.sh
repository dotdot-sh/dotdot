#!/usr/bin/env bash
# description: Create a new decision from the decision template.

set -eu

. "$(dirname "$0")/lib/dot-paths.sh"
. "$(dirname "$0")/lib/dot-decisions.sh"

TEMPLATE="$DECISION_TEMPLATE"

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

# Collapses a value to a single line. The statement becomes both the H1 and the
# frontmatter description, and frontmatter is line-oriented — a newline in it
# would silently split the block in two.
oneline() {
  tr '\n' ' ' | sed -E 's/  +/ /g; s/^ +//; s/ +$//'
}

[ -f "$TEMPLATE" ] || { printf '%s❌ Template not found:%s %s\n' "$RED$BOLD" "$RESET" "$TEMPLATE" >&2; exit 1; }

# --- section flags, derived from the template's own "## " headings ---------
HEADERS_FILE="$TMPDIR_/headers.txt"
grep '^## ' "$TEMPLATE" > "$HEADERS_FILE" || true
[ -s "$HEADERS_FILE" ] || { printf '%s❌ No sections found in%s %s\n' "$RED$BOLD" "$RESET" "$TEMPLATE" >&2; exit 1; }

KEYS_FILE="$TMPDIR_/keys.txt"
: > "$KEYS_FILE"
while IFS= read -r hline; do
  # printf, not a bare redirect: slugify emits no trailing newline, so
  # appending its output directly would run every key onto one line and the
  # whole-line lookup below would never match any of them.
  printf '%s\n' "$(header_to_key "${hline#\#\# }")" >> "$KEYS_FILE"
done < "$HEADERS_FILE"

# What each section holds — decision references, feature references, or free
# text — read from the template's placeholders rather than its heading names.
# See decision_section_kinds() for why that distinction matters.
KINDS_FILE="$TMPDIR_/kinds.txt"
decision_section_kinds | while IFS="$(printf '\t')" read -r hdr kind; do
  printf '%s\t%s\n' "$(header_to_key "$hdr")" "$kind"
done > "$KINDS_FILE"

kind_of() {
  awk -F"$(printf '\t')" -v k="$1" '$1 == k { print $2; exit }' "$KINDS_FILE"
}

STATUSES_FILE="$TMPDIR_/statuses.txt"
decision_statuses > "$STATUSES_FILE" || true
[ -s "$STATUSES_FILE" ] || printf 'draft\n' > "$STATUSES_FILE"

usage() {
  cat <<EOF
bash dot document:decision — create a new decision in Decisions/ from the
bundled decision template, numbering and naming it automatically.

The template (.dot/.tooling/skills/dot-document-decision/decision-template.md) is the
single source of truth: this script reads it at run time and derives one flag
per section from its headings, plus the status vocabulary from its frontmatter,
so editing the template is all it takes. It also scans Decisions/ for
the highest existing number and takes the next one — which is why the filename
and number are never to be constructed by hand.

Usage:
  bash dot document:decision --name <text> --statement <text> --elaboration <text> [<status flag>] [<section flags>]...
  bash dot document:decision --help

This script only creates. To change a decision's status afterwards, use
bash dot decision:update; to change its prose, edit the file directly, keeping its
number and bumping the frontmatter "modified" stamp.

Required:
  --name <text>          Short name for the filename slug (e.g. "JWT in httpOnly cookie").
                         Not the rule itself — that is --statement.
  --statement <text>     The decision as a first-person rule. Becomes the H1 and,
                         verbatim, the frontmatter description — so write it to stand
                         alone: someone reading only that line must be able to obey it.
                         E.g. "We store the session JWT in an httpOnly cookie so that ..."
  --elaboration <text>   The single plain paragraph under the H1: what must happen,
                         to whom, and what outcomes and side effects exist.

Status flags (one per run; default draft):
EOF
  while IFS= read -r st; do
    printf '  --%-24s mark the decision %s\n' "$st" "$st"
  done < "$STATUSES_FILE"
  cat <<EOF
  --superseded <ref>        record it as already replaced by another decision.
                            The status string is built here and <ref> is checked
                            to exist, so the link cannot be typed wrong.

Section flags (derived live from $(basename "$(dirname "$TEMPLATE")")/$(basename "$TEMPLATE")):
EOF
  while IFS= read -r hline; do
    header="${hline#\#\# }"
    key=$(header_to_key "$header")
    case "$(kind_of "$key")" in
      decision)
        printf '  --%-24s %s\n' "$key" "$header"
        printf '  %-26s Repeatable, one decision reference each: "2", "002", or\n' ""
        printf '  %-26s "d002--no-soft-deletes.md". The link is built for you and the\n' ""
        printf '  %-26s reference is checked to exist.\n' ""
        ;;
      feature)
        printf '  --%-24s %s\n' "$key" "$header"
        printf '  %-26s Repeatable, one feature reference each: "7", "007", or\n' ""
        printf '  %-26s "f007--login.md". The link is built for you and the\n' ""
        printf '  %-26s reference is checked to exist.\n' ""
        ;;
      *)
        printf '  --%-24s %s — repeatable, one line per use.\n' "$key" "$header"
        ;;
    esac
  done < "$HEADERS_FILE"
  cat <<EOF

Examples:
  bash dot document:decision \\
    --name "JWT in httpOnly cookie" \\
    --statement "We store the session JWT in an httpOnly cookie so that a XSS foothold cannot read it." \\
    --elaboration "Every authenticated response sets the token as an httpOnly, Secure, SameSite=Lax cookie ..." \\
    --accepted \\
    --influenced-by 002 \\
    --impacts 7

Which sections take references and which take prose is read from the template's
placeholders, not their names — so renaming a heading changes only the flag
name, and the link checking follows it.
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

# Appends a value to a section file as its own line, so a flag given several
# times builds a list instead of the last use silently winning.
append_section() {
  _as_file="$TMPDIR_/sec_$1"
  if [ -s "$_as_file" ]; then
    printf '\n%s' "$2" >> "$_as_file"
  else
    printf '%s' "$2" > "$_as_file"
  fi
}

NAME_VAL=""
STATEMENT_VAL=""
STATUS_VAL="draft"
SUPERSEDER=""
STATUS_FLAG=""

# Sets the status once, so that "--accepted --deprecated" is refused rather
# than silently resolving to whichever came last.
set_status() {
  [ -z "$STATUS_FLAG" ] || die "only one status flag per run, got --$STATUS_FLAG and --$1"
  STATUS_FLAG="$1"
}

have_name=0
have_statement=0
have_elaboration=0

while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    --name)
      [ $# -ge 2 ] || die "--name requires a value"
      NAME_VAL="$2"; have_name=1; shift 2
      ;;
    --statement)
      [ $# -ge 2 ] || die "--statement requires a value"
      STATEMENT_VAL="$2"; have_statement=1; shift 2
      ;;
    --superseded)
      [ $# -ge 2 ] || die "--superseded requires the decision that replaces this one (e.g. --superseded 007)"
      set_status superseded
      SUPERSEDER="$2"; shift 2
      ;;
    --elaboration)
      [ $# -ge 2 ] || die "--elaboration requires a value"
      printf '%s' "$2" > "$TMPDIR_/body_elaboration"; have_elaboration=1; shift 2
      ;;
    --*)
      key="${1#--}"
      # Status words are checked before section names. Both lists come from the
      # template and neither currently collides with the other; if one ever
      # did, the status reading wins, which is the safer default because a
      # mis-set status is invisible while a missing section is not.
      if grep -qxF -- "$key" "$STATUSES_FILE"; then
        set_status "$key"
        STATUS_VAL="$key"
        shift
        continue
      fi
      # -F, because the flag name is data, not a pattern: without it "--.*"
      # matches every key line and slips past this check, and whatever it
      # contains then becomes part of a filename below.
      if ! grep -qxF -- "$key" "$KEYS_FILE"; then
        die "unknown flag --$key"
      fi
      [ $# -ge 2 ] || die "--$key requires a value"
      kind=$(kind_of "$key")
      case "$kind" in
        decision|feature)
          # These sections hold references to resolve, not prose to copy: the
          # entry has to be a link that actually opens something, and a
          # reference that resolves to nothing is a dead link written into a
          # file nobody will re-check.
          link=$(ref_link "$kind" "$2") \
            || die "--$key '$2' matches no $kind in dotdot"
          append_section "$key" "$link"
          ;;
        *)
          append_section "$key" "$2"
          ;;
      esac
      shift 2
      ;;
    *)
      die "unexpected argument: $1 (flags must be given as --name value)"
      ;;
  esac
done

[ "$have_name" -eq 1 ] || die "missing required --name"
[ "$have_statement" -eq 1 ] || die "missing required --statement"
[ "$have_elaboration" -eq 1 ] || die "missing required --elaboration"

# The only status carrying a link, so the lib builds it: the caller passes a
# reference and never assembles the string, which is what keeps the link form
# in one place rather than in every script that writes a status.
if [ "$STATUS_FLAG" = "superseded" ]; then
  STATUS_VAL=$(decision_superseded_status "$SUPERSEDER") \
    || die "--superseded '$SUPERSEDER' matches no decision in Decisions/"
fi

SLUG=$(slugify "$NAME_VAL")
[ -n "$SLUG" ] || die "--name must contain at least one letter or number"

mkdir -p "$DECISIONS_DIR"

# The next number is one past the highest already there — not the file count,
# which would collide the moment a decision is deleted or arrives out of order.
max=0
for f in "$DECISIONS_DIR"/"$DECISION_PREFIX"[0-9]*"$RECORD_SEP"*.md; do
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

TARGET="$DECISIONS_DIR/$DECISION_PREFIX$NUM$RECORD_SEP$SLUG.md"
[ -e "$TARGET" ] && die "target already exists: $TARGET (unexpected — try again)"

# The statement is the description: a rule stated well enough to obey is
# already the one line a survey needs, and keeping one source for both means
# they cannot drift into saying different things.
STATEMENT_ONELINE=$(printf '%s' "$STATEMENT_VAL" | oneline)
NOW=$(decision_now)

OUT="$TMPDIR_/out.md"
{
  # The frontmatter block is emitted in the template's key order rather than
  # derived, because these four keys are structural: their names and order are
  # what bash dot scan:frontmatter and every reader depend on.
  printf -- '---\n'
  printf 'status: %s\n' "$STATUS_VAL"
  printf 'description: %s\n' "$STATEMENT_ONELINE"
  printf 'created: %s\n' "$NOW"
  printf 'modified: %s\n' "$NOW"
  printf -- '---\n\n'
  printf '# %s\n\n' "$STATEMENT_ONELINE"
  cat "$TMPDIR_/body_elaboration"
  printf '\n\n'
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

REL_TARGET="Decisions/$DECISION_PREFIX$NUM$RECORD_SEP$SLUG.md"
printf '\n%s⚖️  %sDecision %s documented%s\n' "$CYAN" "$BOLD" "$NUM" "$RESET"
printf '%s✅ %s%s%s\n\n' "$GREEN$BOLD" "$RESET$GREEN" "$REL_TARGET" "$RESET"
