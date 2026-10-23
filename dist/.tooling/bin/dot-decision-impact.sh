#!/usr/bin/env bash
# description: Find what a decision touches: citing features, related docs, inbound links, broken links.

set -u

usage() {
    cat <<'EOF'
bash dot decision:impact — find the documented features a proposed decision would
affect, and the existing decisions that bear on it.

A decision is only safe to write down once you know what it collides with, and
only stays trustworthy while its links still point at real files. This answers
both, four ways:

  --decisions   Which features cite these decisions in their "Related Project
                Decisions" section? That is a declared link rather than a
                guess, so run it first: once you know which existing decisions
                influence the new one, the features already built against them
                are the ones most likely to be contradicted.

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
  bash dot decision:impact --decisions "002,005"
  bash dot decision:impact --terms "session,jwt,cookie" [--scope all|features|decisions] [--lines N]
  bash dot decision:impact --inbound 004
  bash dot decision:impact --check
  bash dot decision:impact --decisions 002 --terms "session,jwt"
  bash dot decision:impact --help

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
                      the term search only — the citation search reads features,
                      since only features have a Related Project Decisions
                      section.
  --lines <N>         Matching lines to show per file (default: 3, 0 for none).

Notes:
  - A decision reference is resolved against Decisions/ and must exist,
    so a typo is reported rather than silently returning no citations.
  - Terms match as case-insensitive literal substrings, so "auth" also hits
    "authorize" and "OAuth". Prefer several precise terms over one broad one:
    files are ranked by how many distinct terms they match, so a file hitting
    three of your terms sorts above one hitting a single term many times.
  - A file matching nothing is not listed. No output at all means the decision
    touches nothing already documented — a real answer, and a useful one.
  - Searches Features/*.md and Decisions/*.md only. Both are
    surveyed whole, so it costs the same whether dotdot holds five docs or
    five hundred.
EOF
}

terms=()
refs=()
inbound=""
do_check=0
scope="all"
context_lines=3

while [[ $# -gt 0 ]]; do
    case "$1" in
        --terms=*) IFS=',' read -r -a _t <<< "${1#*=}"; terms+=("${_t[@]}"); shift ;;
        --terms)   [[ $# -ge 2 ]] || { echo "❌ --terms requires a value" >&2; exit 1; }
                   IFS=',' read -r -a _t <<< "$2"; terms+=("${_t[@]}"); shift 2 ;;
        --term=*)  terms+=("${1#*=}"); shift ;;
        --term)    [[ $# -ge 2 ]] || { echo "❌ --term requires a value" >&2; exit 1; }
                   terms+=("$2"); shift 2 ;;
        --decisions=*) IFS=',' read -r -a _d <<< "${1#*=}"; refs+=("${_d[@]}"); shift ;;
        --decisions)   [[ $# -ge 2 ]] || { echo "❌ --decisions requires a value" >&2; exit 1; }
                       IFS=',' read -r -a _d <<< "$2"; refs+=("${_d[@]}"); shift 2 ;;
        --decision=*)  refs+=("${1#*=}"); shift ;;
        --decision)    [[ $# -ge 2 ]] || { echo "❌ --decision requires a value" >&2; exit 1; }
                       refs+=("$2"); shift 2 ;;
        --inbound=*) inbound="${1#*=}"; shift ;;
        --inbound)   [[ $# -ge 2 ]] || { echo "❌ --inbound requires a value" >&2; exit 1; }
                     inbound="$2"; shift 2 ;;
        --check)   do_check=1; shift ;;
        --scope=*) scope="${1#*=}"; shift ;;
        --scope)   [[ $# -ge 2 ]] || { echo "❌ --scope requires a value" >&2; exit 1; }
                   scope="$2"; shift 2 ;;
        --lines=*) context_lines="${1#*=}"; shift ;;
        --lines)   [[ $# -ge 2 ]] || { echo "❌ --lines requires a value" >&2; exit 1; }
                   context_lines="$2"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "❌ Unknown argument: $1" >&2; usage >&2; exit 1 ;;
    esac
done

# Drop blanks left by a trailing comma or an empty list, so "a,b," does not
# search for the empty string and match every line in every file.
trim_list() {
    local out=() v
    for v in "$@"; do
        v="${v#"${v%%[![:space:]]*}"}"
        v="${v%"${v##*[![:space:]]}"}"
        [[ -n "$v" ]] && out+=("$v")
    done
    printf '%s\n' "${out[@]-}"
}
mapfile -t terms < <(trim_list "${terms[@]-}")
mapfile -t refs  < <(trim_list "${refs[@]-}")
[[ ${#terms[@]} -eq 1 && -z "${terms[0]}" ]] && terms=()
[[ ${#refs[@]}  -eq 1 && -z "${refs[0]}"  ]] && refs=()

if [[ ${#terms[@]} -eq 0 && ${#refs[@]} -eq 0 && -z "$inbound" && "$do_check" -eq 0 ]]; then
    echo "❌ Nothing to do — pass --decisions, --terms, --inbound, or --check" >&2
    usage >&2
    exit 1
fi

case "$scope" in
    all|features|decisions) ;;
    *) echo "❌ Unknown --scope: $scope (expected all|features|decisions)" >&2; exit 1 ;;
esac

case "$context_lines" in
    ''|*[!0-9]*) echo "❌ --lines must be a whole number, got: $context_lines" >&2; exit 1 ;;
esac

. "$(dirname "$0")/lib/dot-paths.sh"
. "$(dirname "$0")/lib/dot-decisions.sh"


# The heading is read from the feature template rather than hardcoded, so
# renaming that section in one place does not quietly stop this from finding
# anything — the failure mode of a hardcoded heading is an empty result that
# looks exactly like "nothing cites this".
REL_HEADING=$(grep -m1 -E '^## .*Related .*Decisions' "$FEATURE_TEMPLATE" 2>/dev/null || true)
[[ -n "$REL_HEADING" ]] || REL_HEADING="## Related Project Decisions"

# Prints the body of section "$2" from file "$1", stopping at the next heading.
section_body() {
    awk -v h="$2" '$0 == h { f = 1; next } /^## / { f = 0 } f' "$1"
}

# True when a section body references decision/feature file "$2" (numbered
# "$3") — by filename, or by the bare number as a standalone token so that
# "003" does not match inside "1003".
cites_ref() {
    grep -qF -- "$2" <<< "$1" || grep -qE "(^|[^0-9])${3}([^0-9]|$)" <<< "$1"
}

# The decision template's own link-shaped sections, as "heading<TAB>kind".
DECISION_SECTIONS=$(decision_section_kinds | awk -F'\t' '$2 != "text"')

# ---------------------------------------------------------------------------
# 0a. --check: every reference in every decision must resolve to a real file.
#
# This is the sync guard. Links are written once and read for years; a renamed
# or deleted file turns them into dead ends silently, and nothing else in
# dotdot would ever notice.
# ---------------------------------------------------------------------------
if [[ "$do_check" -eq 1 ]]; then
    echo "Checking decision links resolve:"
    broken=0
    checked=0
    if [[ -d "$DECISIONS_DIR" ]]; then
        for f in "$DECISIONS_DIR"/*.md; do
            [[ -e "$f" ]] || continue
            self=$(basename "$f")
            while IFS=$'\t' read -r hdr kind; do
                [[ -n "$hdr" ]] || continue
                body=$(section_body "$f" "## $hdr")
                [[ -n "$body" ]] || continue
                while IFS= read -r line; do
                    # Only "- [...](target.md)" entries are links; "None" and
                    # prose are not, and flagging them would be noise.
                    target=$(sed -n 's/.*(\([^)]*\.md\)).*/\1/p' <<< "$line")
                    [[ -n "$target" ]] || continue
                    checked=$((checked + 1))
                    if [[ "$kind" == "feature" ]]; then
                        [[ -e "$FEATURES_DIR/$target" ]] && continue
                    else
                        [[ -e "$DECISIONS_DIR/$target" ]] && continue
                    fi
                    printf '  ❌ %s → %s (%s) does not exist\n' "$self" "$target" "$hdr"
                    broken=$((broken + 1))
                done <<< "$body"

                # A decision listing itself reads as a live cross-reference and
                # is always a mistake, so it is worth naming separately.
                if grep -qF -- "$self" <<< "$body"; then
                    printf '  ❌ %s → %s (%s) references itself\n' "$self" "$self" "$hdr"
                    broken=$((broken + 1))
                fi
            done <<< "$DECISION_SECTIONS"

            # Supersession is a link too, and it lives in the frontmatter
            # rather than a section — the one place a dead reference matters
            # most, since it is what tells a reader this decision is no longer
            # in force and where the live one is.
            st=$(awk 'NR==1&&/^---$/{f=1;next} f&&/^---$/{exit} f&&/^status:/{print;exit}' "$f")
            target=$(sed -n 's/.*(\([^)]*\.md\)).*/\1/p' <<< "$st")
            if [[ -n "$target" ]]; then
                checked=$((checked + 1))
                if [[ ! -e "$DECISIONS_DIR/$target" ]]; then
                    printf '  ❌ %s → %s (status) does not exist\n' "$self" "$target"
                    broken=$((broken + 1))
                elif [[ "$target" == "$self" ]]; then
                    printf '  ❌ %s → %s (status) supersedes itself\n' "$self" "$self"
                    broken=$((broken + 1))
                fi
            fi
        done
    fi
    if [[ "$broken" -eq 0 ]]; then
        printf '  ✅ %d reference(s) checked, all resolve.\n\n' "$checked"
    else
        printf '\n  %d broken of %d checked.\n\n' "$broken" "$checked"
    fi
    [[ ${#terms[@]} -eq 0 && ${#refs[@]} -eq 0 && -z "$inbound" ]] && exit $(( broken > 0 ? 1 : 0 ))
fi

# ---------------------------------------------------------------------------
# 0b. --inbound: who points at this decision?
#
# Outbound edges are recorded on the decision doing the impacting, so the
# impacted decision's own file says nothing about it. Deriving the reverse on
# demand keeps one copy of the fact — writing it into both files would create
# two that can disagree.
# ---------------------------------------------------------------------------
if [[ -n "$inbound" ]]; then
    if ! target_file=$(decision_resolve_ref "$inbound"); then
        echo "❌ No decision matching '$inbound' in Decisions/" >&2
        exit 1
    fi
    target_num=$(record_num "$target_file")
    printf 'Decisions pointing at %s:\n' "$target_file"
    any_in=0
    for f in "$DECISIONS_DIR"/*.md; do
        [[ -e "$f" ]] || continue
        self=$(basename "$f")
        [[ "$self" == "$target_file" ]] && continue
        why=""
        st=$(awk 'NR==1&&/^---$/{f=1;next} f&&/^---$/{exit} f&&/^status:/{print;exit}' "$f")

        # Supersession first: "this decision is dead because of yours" outranks
        # "this decision was shaped by yours", and it is the one a reader most
        # needs to see. It lives in the status, not a section, so it needs its
        # own check rather than the section loop below.
        case "$st" in
            *"$DECISION_SUPERSEDED"*)
                if grep -qF -- "$target_file" <<< "$st"; then
                    why="superseded by it"
                fi
                ;;
        esac

        while IFS=$'\t' read -r hdr kind; do
            [[ "$kind" == "decision" ]] || continue
            body=$(section_body "$f" "## $hdr")
            [[ -n "$body" ]] || continue
            if cites_ref "$body" "$target_file" "$target_num"; then
                why="${why:+$why; }lists it under \"$hdr\""
            fi
        done <<< "$DECISION_SECTIONS"

        [[ -n "$why" ]] || continue
        any_in=1
        printf '\n  %s\n' "$self"
        printf '    %s\n' "$why"
        desc=$(awk 'NR==1&&/^---$/{f=1;next} f&&/^---$/{exit} f&&/^description:/{print;exit}' "$f")
        [[ -n "$desc" ]] && printf '    %s\n' "$desc"
        [[ -n "$st" ]] && printf '    %s\n' "$st"
    done
    [[ "$any_in" -eq 1 ]] || printf '  (none)\n'
    echo
    [[ ${#terms[@]} -eq 0 && ${#refs[@]} -eq 0 ]] && exit 0
fi

# ---------------------------------------------------------------------------
# 1. Citation search: features that declare a dependency on these decisions.
# ---------------------------------------------------------------------------
if [[ ${#refs[@]} -gt 0 ]]; then
    resolved=()
    for r in "${refs[@]}"; do
        if ! file=$(decision_resolve_ref "$r"); then
            echo "❌ No decision matching '$r' in Decisions/" >&2
            exit 1
        fi
        resolved+=("$file")
    done

    printf '%s\n' "Features citing these decisions under \"${REL_HEADING#\#\# }\":"
    any_cite=0
    if [[ -d "$FEATURES_DIR" ]]; then
        for f in "$FEATURES_DIR"/*.md; do
            [[ -e "$f" ]] || continue
            # Only the Related Project Decisions section counts. A decision
            # mentioned in prose elsewhere is a topical mention, which is what
            # the term search is for; conflating the two would turn a declared
            # dependency into a guess.
            section=$(section_body "$f" "$REL_HEADING")
            [[ -n "$section" ]] || continue
            cited=""
            for file in "${resolved[@]}"; do
                num=$(record_num "$file")
                if cites_ref "$section" "$file" "$num"; then
                    cited="${cited:+$cited, }$num"
                fi
            done
            [[ -n "$cited" ]] || continue
            any_cite=1
            printf '\n  %s/%s\n' "$(dotdot_inner "$FEATURES_DIR")" "$(basename "$f")"
            printf '    cites: %s\n' "$cited"
            desc=$(awk 'NR==1&&/^---$/{f=1;next} f&&/^---$/{exit} f&&/^description:/{print;exit}' "$f")
            [[ -n "$desc" ]] && printf '    %s\n' "$desc"
        done
    fi
    [[ "$any_cite" -eq 1 ]] || printf '  (none)\n'
    echo
fi

# ---------------------------------------------------------------------------
# 2. Term search: anything that talks about the decision's subject matter.
# ---------------------------------------------------------------------------
[[ ${#terms[@]} -gt 0 ]] || exit 0

# Both directories are fixed rather than caller-supplied: this tool answers one
# question about dotdot's own docs, so there is no path to confine and nothing
# a caller could point it at by mistake.
dirs=()
[[ "$scope" == "all" || "$scope" == "decisions" ]] && dirs+=("$(dotdot_inner "$DECISIONS_DIR")")
[[ "$scope" == "all" || "$scope" == "features" ]] && dirs+=("$(dotdot_inner "$FEATURES_DIR")")

# Rank by distinct terms matched, then by total matching lines: a doc that
# mentions three of the decision's terms is more likely to be genuinely
# entangled than one that repeats a single common word.
results=$(
  for d in "${dirs[@]}"; do
    abs="$DOTDOT_ROOT/$d"
    [[ -d "$abs" ]] || continue
    for f in "$abs"/*.md; do
      [[ -e "$f" ]] || continue
      matched=0
      total=0
      hit_terms=""
      for t in "${terms[@]}"; do
        n=$(grep -icF -- "$t" "$f" || true)
        if [[ "$n" -gt 0 ]]; then
          matched=$((matched + 1))
          total=$((total + n))
          hit_terms="${hit_terms:+$hit_terms, }$t"
        fi
      done
      [[ "$matched" -eq 0 ]] && continue
      printf '%d\t%d\t%s/%s\t%s\n' "$matched" "$total" "$d" "$(basename "$f")" "$hit_terms"
    done
  done | sort -t"$(printf '\t')" -k1,1nr -k2,2nr
)

printf '%s\n' "Files mentioning these terms:"
[[ -n "$results" ]] || { printf '  (none)\n\n'; exit 0; }

while IFS=$'\t' read -r matched total relpath hit_terms; do
    path="$DOTDOT_ROOT/$relpath"
    noun="lines"; [[ "$total" -eq 1 ]] && noun="line"
    printf '\n  %s\n' "$relpath"
    printf '    matched %d of %d terms (%d %s): %s\n' "$matched" "${#terms[@]}" "$total" "$noun" "$hit_terms"

    # Where the frontmatter ends. The description is printed on its own below,
    # so counting its line again among the samples would spend two of the three
    # lines a reader gets saying the same thing twice.
    fm_end=0
    if [[ "$(head -1 "$path")" == "---" ]]; then
        fm_end=$(awk 'NR>1 && /^---$/{print NR; exit}' "$path")
        [[ -z "$fm_end" ]] && fm_end=0
    fi

    # The frontmatter description is what makes a hit judgeable without opening
    # the file, so it is worth the line it costs to print.
    desc=$(head -n "$fm_end" "$path" 2>/dev/null | grep -m1 '^description:' || true)
    [[ -n "$desc" ]] && printf '    %s\n' "$desc"

    if [[ "$context_lines" -gt 0 ]]; then
        for t in "${terms[@]}"; do
            grep -inF -- "$t" "$path" || true
        done | sort -t: -k1,1n -u \
             | awk -F: -v m="$fm_end" '$1 + 0 > m' \
             | head -n "$context_lines" | sed 's/^/      /'
    fi
done <<< "$results"

echo
