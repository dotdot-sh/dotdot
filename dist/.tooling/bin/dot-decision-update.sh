#!/usr/bin/env bash
# description: Change a decision's status and refresh its timestamp.

set -eu

. "$(dirname "$0")/lib/dot-paths.sh"
. "$(dirname "$0")/lib/dot-decisions.sh"

if [ -t 1 ]; then
  BOLD=$(printf '\033[1m'); RED=$(printf '\033[31m'); GREEN=$(printf '\033[32m')
  CYAN=$(printf '\033[36m'); RESET=$(printf '\033[0m')
else
  BOLD=""; RED=""; GREEN=""; CYAN=""; RESET=""
fi

TMPDIR_=$(mktemp -d) || { echo "Failed to create a temp directory" >&2; exit 1; }
trap 'rm -rf "$TMPDIR_"' EXIT INT TERM HUP

STATUSES_FILE="$TMPDIR_/statuses.txt"
decision_statuses > "$STATUSES_FILE" 2>/dev/null || true
[ -s "$STATUSES_FILE" ] || printf 'draft\n' > "$STATUSES_FILE"

usage() {
  cat <<EOF
bash dot decision:update — set an existing decision's status and refresh its
"modified" timestamp in one step.

The timestamp is not a flag: it is the whole reason this exists rather than
being left to a hand edit, so it is always set to now.

Usage:
  bash dot decision:update <NNN> <status flag>
  bash dot decision:update --help

Arguments:
  <NNN>              The decision to update. Accepts "2", "002", or
                     "d002--no-soft-deletes.md" — whichever you have to hand.

Status flags (one per run; derived from the template's vocabulary):
EOF
  while IFS= read -r st; do
    printf '  --%-16s mark the decision %s\n' "$st" "$st"
  done < "$STATUSES_FILE"
  cat <<EOF
  --superseded <ref>  mark it replaced by another decision, given in any of the
                      forms above. The status string — "superseded by
                      [dNNN](dNNN--slug.md)" — is built here, and <ref> is
                      checked to exist, so the link cannot be typed wrong.

The status is chosen by flag rather than typed as text: the vocabulary is fixed
by the template, and a free-text value is a typo waiting to become a status no
reader or tool recognises.

Examples:
  bash dot decision:update 002 --accepted
  bash dot decision:update 002 --superseded 007

Only the status and the timestamp change. To edit a decision's prose, edit the
file directly — and bump "modified" yourself if you do.
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

REF=""
STATUS_VAL=""
SUPERSEDER=""
STATUS_FLAG=""

# Sets the status once, so that "--accepted --deprecated" is refused rather
# than silently resolving to whichever came last.
set_status() {
  [ -z "$STATUS_FLAG" ] || die "only one status flag per run, got --$STATUS_FLAG and --$1"
  STATUS_FLAG="$1"
}

while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --superseded)
      [ $# -ge 2 ] || die "--superseded requires the decision that replaces this one (e.g. --superseded 007)"
      set_status superseded
      SUPERSEDER="$2"; shift 2
      ;;
    --*)
      cand="${1#--}"
      # The simple statuses are whatever the template lists, so a status added
      # there becomes a flag here with nothing to update by hand. -F because
      # the flag name is data: "--.*" must not match every line and pass.
      grep -qxF -- "$cand" "$STATUSES_FILE" \
        || die "unknown flag $1 (expected one of: $(tr '\n' ' ' < "$STATUSES_FILE" | sed -E 's/ +$//')or --superseded <ref>)"
      set_status "$cand"
      STATUS_VAL="$cand"
      shift
      ;;
    *)
      [ -z "$REF" ] || die "expected a single decision reference, got a second: $1"
      REF="$1"; shift
      ;;
  esac
done

[ -n "$REF" ] || die "missing the decision to update (e.g. 002)"
[ -n "$STATUS_FLAG" ] || die "missing a status flag (e.g. --accepted, or --superseded 007)"

FILE=$(decision_resolve_ref "$REF") \
  || die "no decision matching '$REF' in Decisions/"
TARGET="$DECISIONS_DIR/$FILE"

# The status string is constructed here rather than accepted from the caller,
# so the link inside it is always built from a reference that resolved.
if [ "$STATUS_FLAG" = "superseded" ]; then
  STATUS_VAL=$(decision_superseded_status "$SUPERSEDER") \
    || die "--superseded '$SUPERSEDER' matches no decision in Decisions/"
fi

# A decision superseded by itself is a loop that reads as a live rule.
case "$STATUS_VAL" in
  *"](${FILE})"*) die "a decision cannot supersede itself ($FILE)" ;;
esac

head -1 "$TARGET" | grep -qx -- '---' \
  || die "$FILE has no frontmatter block to update"

OLD_STATUS=$(awk 'NR==1&&/^---$/{f=1;next} f&&/^---$/{exit} f&&/^status:/{sub(/^status: */,"");print;exit}' "$TARGET")
NOW=$(decision_now)

# Rewritten with awk rather than sed so the edit is confined to the frontmatter
# block: a line starting "status:" or "modified:" in the body is prose, and
# rewriting it would corrupt the decision while appearing to succeed.
awk -v status="$STATUS_VAL" -v now="$NOW" '
  NR == 1 && $0 == "---" { infm = 1; print; next }
  infm && $0 == "---"    { infm = 0; print; next }
  infm && /^status:/     { print "status: " status; seen_status = 1; next }
  infm && /^modified:/   { print "modified: " now; seen_mod = 1; next }
  { print }
  END {
    if (!seen_status || !seen_mod) exit 3
  }
' "$TARGET" > "$TMPDIR_/updated.md" || die "$FILE is missing a status: or modified: key in its frontmatter"

# Written to a temp file first and moved into place, so a failure partway
# leaves the original decision intact rather than truncated.
cat "$TMPDIR_/updated.md" > "$TARGET"

printf '\n%s⚖️  %sDecision %s updated%s\n' "$CYAN" "$BOLD" "$(record_num "$FILE")" "$RESET"
printf '   status:   %s → %s%s%s\n' "${OLD_STATUS:-(unset)}" "$GREEN" "$STATUS_VAL" "$RESET"
printf '   modified: %s\n' "$NOW"
printf '%s✅ %s%sDecisions/%s%s\n\n' "$GREEN$BOLD" "$RESET" "$GREEN" "$FILE" "$RESET"
