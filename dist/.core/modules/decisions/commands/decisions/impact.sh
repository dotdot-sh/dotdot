#!/usr/bin/env bash

DESCRIPTION="Find what a decision touches: citing features, related docs, inbound links, broken links."

dot::use framework.console.args core.modules.decisions.service framework.helpers.frontmatter framework.helpers.fs framework.console.output framework.helpers.record framework.helpers.text

IMPACT_DEFAULT_LINES=3
IMPACT_SCOPES=" all features decisions "

usage() {
  cat <<EOF
bash dot decisions:impact — find the documented features a proposed decision would
affect, and the existing decisions that bear on it.

A decision is only safe to write down once you know what it collides with, and
only stays trustworthy while its links still point at real files. This answers
both, four ways:

  --decisions   Which features cite these decisions in their "$FEATURE_DECISIONS_HEADING"
                section? That is a declared link rather than a guess, so run it
                first: once you know which existing decisions influence the new
                one, the features already built against them are the ones most
                likely to be contradicted.

  --terms       Which features and decisions mention these things at all? The
                wider net for what declared links miss — nothing forces a
                feature to cite the decision it actually depends on.

  --inbound     Which decisions point at this one — because it superseded them,
                or because it shaped them? Every edge between decisions is
                stored once, on the decision that declares it, so the reverse
                direction is derived here rather than written into both files
                where the two copies could disagree.

  --check       Does every reference in every decision resolve to a file that
                exists, including the "superseded by" link in a status? Links
                are written once and read for years; a rename or a deletion
                turns them into dead ends that nothing else notices.

They combine in one invocation. The output is bounded either way: a raw grep
over Features/ and Decisions/ returns either everything or nothing useful, and
reading whole feature docs to find out costs far more context than the answer
is worth.

Usage:
  bash dot decisions:impact --decisions "002,005"
  bash dot decisions:impact --terms "session,jwt,cookie" [--scope all|features|decisions] [--lines N]
  bash dot decisions:impact --inbound 004
  bash dot decisions:impact --check
  bash dot decisions:impact --decisions 002 --terms "session,jwt"
  bash dot decisions:impact --help

Options:
  --decisions <list>  Comma-separated decision references. Repeatable, and
                      combinable with --decision. Accepts "2", "002", or
                      "d002--no-soft-deletes.md".
  --decision <ref>    A single decision reference. Repeatable.
  --inbound <ref>     Report the decisions listing this one in any of their
                      link sections, with the section that names it.
  --check             Verify every decision's links resolve. Exits non-zero if
                      any is broken, so it can gate a commit.
  --terms <list>      Comma-separated search terms. Repeatable, and combinable
                      with --term.
  --term <text>       A single search term; use it when a term itself contains
                      a comma. Repeatable.
  --scope <what>      features | decisions | all   (default: all). Applies to
                      the term search only.
  --lines <N>         Matching lines to show per file (default: $IMPACT_DEFAULT_LINES, 0 for none).

Notes:
  - A decision reference is resolved against Decisions/ and must exist,
    so a typo is reported rather than silently returning no citations.
  - Terms match as case-insensitive literal substrings, so "auth" also hits
    "authorize" and "OAuth". Prefer several precise terms over one broad one:
    files are ranked by how many distinct terms they match.
  - A file matching nothing is not listed. No output at all means the decision
    touches nothing already documented — a real answer, and a useful one.
EOF
}

add_items() {
  local list="$1" item
  shift
  while IFS= read -r item; do
    [ -z "$item" ] || printf '%s\n' "$item" >> "$list"
  done < <(printf '%s\n' "$@")
}

report_check() {
  local kind self target section checked=0 broken=0
  framework.console.output::line "Checking decision links resolve:"
  while IFS=$'\t' read -r kind self target section; do
    case "$kind" in
      checked) checked=$((checked + 1)) ;;
      missing) framework.console.output::detail "$OUTPUT_ERROR_ICON $self → $target ($section) does not exist"; broken=$((broken + 1)) ;;
      self) framework.console.output::detail "$OUTPUT_ERROR_ICON $self → $self ($section) references itself"; broken=$((broken + 1)) ;;
    esac
  done < <(core.modules.decisions.service::broken_links)
  if [ "$broken" -eq 0 ]; then
    framework.console.output::detail "$OUTPUT_SUCCESS_ICON $checked reference(s) checked, all resolve."
  else
    framework.console.output::detail "$broken broken of $checked checked."
  fi
  framework.console.output::newline
  [ "$broken" -eq 0 ]
}

report_inbound() {
  local reference="$1" target file reasons path found=false
  target=$(core.modules.decisions.service::find "$reference") || framework.console.output::fail "No decision matching '$reference' in Decisions/."
  framework.console.output::line "Decisions pointing at $target:"
  while IFS=$'\t' read -r file reasons; do
    found=true
    path="$DECISIONS_DIR/$file"
    framework.console.output::newline
    framework.console.output::line "  $file"
    framework.console.output::detail " $reasons"
    print_field "$path" description
    print_field "$path" status
  done < <(core.modules.decisions.service::inbound "$target")
  $found || framework.console.output::detail "(none)"
  framework.console.output::newline
}

print_field() {
  local value
  value=$(framework.helpers.frontmatter::field "$1" "$2")
  [ -z "$value" ] || framework.console.output::detail " $2: $value"
}

report_citations() {
  local references_file="$1" reference file decisions=() feature cited found=false
  while IFS= read -r reference; do
    file=$(core.modules.decisions.service::find "$reference") || framework.console.output::fail "No decision matching '$reference' in Decisions/."
    decisions+=("$file")
  done < "$references_file"
  framework.console.output::line "Features citing these decisions under \"$FEATURE_DECISIONS_HEADING\":"
  while IFS=$'\t' read -r feature cited; do
    found=true
    framework.console.output::newline
    framework.console.output::line "  $(dot::relative "$FEATURES_DIR")/$feature"
    framework.console.output::detail " cites: $cited"
    print_field "$FEATURES_DIR/$feature" description
  done < <(core.modules.decisions.service::citing_features "${decisions[@]}")
  $found || framework.console.output::detail "(none)"
  framework.console.output::newline
}

report_terms() {
  local terms_file="$1" scope="$2" lines="$3" terms=() term matched total relative hits results
  while IFS= read -r term; do
    terms+=("$term")
  done < "$terms_file"
  results=$(core.modules.decisions.service::term_matches "$scope" "${terms[@]}" | sort -t$'\t' -k1,1nr -k2,2nr)
  framework.console.output::line "Files mentioning these terms:"
  if [ -z "$results" ]; then
    framework.console.output::detail "(none)"
    framework.console.output::newline
    return
  fi
  while IFS=$'\t' read -r matched total relative hits; do
    framework.console.output::newline
    framework.console.output::line "  $relative"
    framework.console.output::detail " matched $matched of ${#terms[@]} terms ($(framework.helpers.text::plural "$total" line)): $hits"
    print_field "$BASE/$relative" description
    [ "$lines" -gt 0 ] || continue
    core.modules.decisions.service::matching_lines "$BASE/$relative" "$lines" "${terms[@]}" | sed 's/^/      /'
  done <<< "$results"
  framework.console.output::newline
}

handle() {
  local work terms references inbound="" check=false scope=all lines="$IMPACT_DEFAULT_LINES" healthy=true
  framework.helpers.fs::make_temp_dir work || framework.console.output::fail "Could not create a temp directory."
  terms="$work/terms"
  references="$work/references"
  : > "$terms"
  : > "$references"
  while [ $# -gt 0 ]; do
    case "$1" in
      --terms=*) add_items "$terms" "$(framework.console.args::split "${1#*=}")"; shift ;;
      --terms) framework.console.args::require_value "$@"; add_items "$terms" "$(framework.console.args::split "$2")"; shift 2 ;;
      --term=*) add_items "$terms" "$(framework.helpers.text::trim "${1#*=}")"; shift ;;
      --term) framework.console.args::require_value "$@"; add_items "$terms" "$(framework.helpers.text::trim "$2")"; shift 2 ;;
      --decisions=*) add_items "$references" "$(framework.console.args::split "${1#*=}")"; shift ;;
      --decisions) framework.console.args::require_value "$@"; add_items "$references" "$(framework.console.args::split "$2")"; shift 2 ;;
      --decision=*) add_items "$references" "$(framework.helpers.text::trim "${1#*=}")"; shift ;;
      --decision) framework.console.args::require_value "$@"; add_items "$references" "$(framework.helpers.text::trim "$2")"; shift 2 ;;
      --inbound=*) inbound="${1#*=}"; shift ;;
      --inbound) framework.console.args::require_value "$@"; inbound="$2"; shift 2 ;;
      --check) check=true; shift ;;
      --scope=*) scope="${1#*=}"; shift ;;
      --scope) framework.console.args::require_value "$@"; scope="$2"; shift 2 ;;
      --lines=*) lines="${1#*=}"; shift ;;
      --lines) framework.console.args::require_value "$@"; lines="$2"; shift 2 ;;
      *) framework.console.args::unexpected "$1" ;;
    esac
  done
  [ -s "$terms" ] || [ -s "$references" ] || [ -n "$inbound" ] || $check \
    || framework.console.args::invalid "Nothing to do — pass --decisions, --terms, --inbound, or --check."
  [[ "$IMPACT_SCOPES" == *" $scope "* ]] || framework.console.args::invalid "Unknown --scope: $scope (expected all|features|decisions)."
  framework.console.args::is_number "$lines" || framework.console.args::invalid "--lines must be a whole number, got: $lines"
  ! $check || report_check || healthy=false
  [ -z "$inbound" ] || report_inbound "$inbound"
  [ ! -s "$references" ] || report_citations "$references"
  [ ! -s "$terms" ] || report_terms "$terms" "$scope" "$lines"
  $healthy
}
