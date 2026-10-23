#!/usr/bin/env bash
# dot-decisions.sh — shared vocabulary for the decision scripts.
#
# bash dot document:decision and bash dot decision:update both need to know the status
# words the template allows and how to turn "002" into a real link, and
# bash dot decision:impact needs to resolve the same references. Keeping that in one
# place is what stops the three from drifting apart — a status added to the
# template has to reach all of them at once, or a file gets written that the
# next script refuses to read.
#
# Source it after lib/dot-paths.sh, which provides $DOTDOT_ROOT:
#   . "$(dirname "$0")/lib/dot-paths.sh"
#   . "$(dirname "$0")/lib/dot-decisions.sh"


# Prints "<heading><TAB><kind>" for each "## " section in the decision
# template, where kind is one of: decision, feature, text.
#
# The kind is read from the section's own placeholder — "(dNNN--slug.md)" means
# it holds decision references, "(fNNN--slug.md)" means features — rather than
# from the heading text. Headings get renamed: "Related Decisions" became
# "Influencing Decisions" and a name-matched rule would have quietly stopped
# resolving links, accepting raw text and writing dead references. The
# placeholder states what the section holds, so it is the thing to key on.
decision_section_kinds() {
  awk '
    /^## / { hdr = substr($0, 4); want = 1; next }
    want && NF {
      kind = "text"
      if ($0 ~ /fNNN--/) kind = "feature"
      else if ($0 ~ /dNNN--/) kind = "decision"
      print hdr "\t" kind
      want = 0
    }
  ' "$DECISION_TEMPLATE"
}

# Prints the status words the template lists, one per line.
#
# The template states them inline as "{a | b | c}", so adding a status there is
# all it takes for every script to accept it. An entry containing "[" is the
# free-form "superseded by [dNNN](...)" form, which is matched by
# prefix rather than as a literal and so is dropped from the list.
decision_statuses() {
  grep -m1 '^status:' "$DECISION_TEMPLATE" \
    | sed -n 's/.*{\(.*\)}.*/\1/p' \
    | tr '|' '\n' \
    | sed -E 's/^ +//; s/ +$//' \
    | grep -v '\[' \
    | grep -v '^$'
}

# Records are named "<prefix>NNN--slug.md" — d007--no-soft-deletes.md,
# f012--login.md, n003--template.md. One prefix per kind and one separator,
# declared here so the scripts that create records and the ones that read them
# cannot disagree about the shape.
DECISION_PREFIX="d"
FEATURE_PREFIX="f"
NOTE_PREFIX="n"
TASK_PREFIX="t"
RECORD_SEP="--"

# Prints the zero-padded number of a record filename.
#
# Not "${file%%-*}": that cuts at the first "-" and keeps the prefix ("d007").
# Anything printing a number out of a filename goes through here.
record_num() {
  printf '%s' "$1" | sed -n 's/^[A-Za-z_]*\([0-9][0-9]*\).*/\1/p'
}

# Normalises any reference an agent might pass — "7", "007", "f007",
# "d007--no-soft-deletes.md", or a whole "[decision 007](...)" link — to a
# zero-padded three-digit number.
record_ref_num() {
  _rn=$(printf '%s' "$1" | sed -n 's/[^0-9]*\([0-9][0-9]*\).*/\1/p')
  [ -n "$_rn" ] || return 1
  # Leading zeros are stripped textually: $((008)) is an invalid octal constant.
  _rn=$(printf '%s' "$_rn" | sed 's/^0*//')
  [ -n "$_rn" ] || _rn=0
  printf '%03d' "$_rn"
}

# Turns a decision reference into its filename, or fails if no such decision
# exists.
#
# Resolving rather than trusting the input is the point: a link someone will
# click, built from a number that was never checked, produces a file that looks
# correct and points nowhere.
decision_resolve_ref() {
  _dr_num=$(record_ref_num "$1") || return 1
  for _dr_f in "$DECISIONS_DIR/$DECISION_PREFIX$_dr_num$RECORD_SEP"*.md; do
    [ -e "$_dr_f" ] || continue
    basename "$_dr_f"
    return 0
  done
  return 1
}

# Prints "[d007](d007--slug.md)" for a prefix and a resolved filename — the
# link form itself, with no bullet and no surrounding prose.
#
# Every link dotdot writes is built here. The label and the target both encode
# the naming scheme, so a scheme that is spelled out at each call site is one
# that drifts, e.g. section links and statuses disagreeing because one of them
# was assembled somewhere else.
record_link() {
  printf '[%s%s](%s)' "$1" "$(record_num "$2")" "$2"
}

# Prints the "- [dNNN](dNNN--slug.md)" line for a reference.
decision_link() {
  _dl_file=$(decision_resolve_ref "$1") || return 1
  printf -- '- %s\n' "$(record_link "$DECISION_PREFIX" "$_dl_file")"
}

# The same resolution for features, named fNNN--slug.md.
feature_resolve_ref() {
  _fr_num=$(record_ref_num "$1") || return 1
  for _fr_f in "$FEATURES_DIR/$FEATURE_PREFIX$_fr_num$RECORD_SEP"*.md; do
    [ -e "$_fr_f" ] || continue
    basename "$_fr_f"
    return 0
  done
  return 1
}

# Prints the "- [fNNN](fNNN--slug.md)" line for a reference.
feature_link() {
  _fl_file=$(feature_resolve_ref "$1") || return 1
  printf -- '- %s\n' "$(record_link "$FEATURE_PREFIX" "$_fl_file")"
}

# The wording that marks a decision as replaced. Both scripts build this status
# and three places match on it, so it is named once — a reworded literal that
# only some of them know about would leave a status nothing recognises.
DECISION_SUPERSEDED="superseded by "

# Builds the full "superseded by [dNNN](dNNN--slug.md)" status from a
# reference, or fails if it resolves to nothing.
#
# The caller never assembles this string: it is the one status that carries a
# link, so building it anywhere else is building a link somewhere else.
decision_superseded_status() {
  _ss_file=$(decision_resolve_ref "$1") || return 1
  printf '%s%s\n' "$DECISION_SUPERSEDED" "$(record_link "$DECISION_PREFIX" "$_ss_file")"
}

# Resolves a reference of either kind, so callers that already know the section
# kind do not each need their own branch.
ref_link() {
  case "$1" in
    decision) decision_link "$2" ;;
    feature)  feature_link "$2" ;;
    *) return 1 ;;
  esac
}

# The current timestamp in the format the template's created/modified use.
decision_now() {
  date '+%Y-%m-%d %H:%M:%S'
}
