#!/usr/bin/env bash

dot::use framework.helpers.date framework.helpers.frontmatter framework.helpers.fs framework.helpers.record framework.helpers.template framework.helpers.text

DECISION_TEMPLATE="$MODULES_DIR/decisions/skills/dot-document-decision/decision-template.md"
FEATURE_DECISIONS_HEADING="Related Project Decisions"
DECISION_DEFAULT_STATUS="draft"
DECISION_SUPERSEDED="superseded by "
DECISION_SUPERSEDED_FLAG="superseded"
DECISION_LINK_TARGET_PATTERN='s/.*(\([^)]*\.md\)).*/\1/p'

core.modules.decisions.service::statuses() {
  local statuses
  statuses=$(framework.helpers.template::options "$DECISION_TEMPLATE" status)
  printf '%s\n' "${statuses:-$DECISION_DEFAULT_STATUS}"
}

core.modules.decisions.service::is_status() {
  core.modules.decisions.service::statuses | grep -xF -- "$1" >/dev/null
}

core.modules.decisions.service::link_sections() {
  framework.helpers.template::section_kinds "$DECISION_TEMPLATE" | awk -F'\t' '$2 != "text"'
}

core.modules.decisions.service::kind() {
  local key="$1" heading kind
  while IFS=$'\t' read -r heading kind; do
    if [ "$(framework.helpers.template::key "$heading")" = "$key" ]; then
      printf '%s\n' "$kind"
      return 0
    fi
  done < <(framework.helpers.template::section_kinds "$DECISION_TEMPLATE")
  printf 'text\n'
}

core.modules.decisions.service::find() {
  framework.helpers.record::find "$DECISIONS_DIR" "$DECISION_PREFIX" "$1"
}

core.modules.decisions.service::link() {
  local file
  file=$(core.modules.decisions.service::find "$1") || return 1
  printf -- '- %s\n' "$(framework.helpers.record::link "$DECISION_PREFIX" "$file")"
}

core.modules.decisions.service::reference_link() {
  case "$1" in
    decision) core.modules.decisions.service::link "$2" ;;
    feature) core.modules.decisions.service::feature_link "$2" ;;
    *) return 1 ;;
  esac
}

core.modules.decisions.service::feature_link() {
  local file
  file=$(framework.helpers.record::find "$FEATURES_DIR" "$FEATURE_PREFIX" "$1") || return 1
  printf -- '- %s\n' "$(framework.helpers.record::link "$FEATURE_PREFIX" "$file")"
}

core.modules.decisions.service::superseded_status() {
  local file
  file=$(core.modules.decisions.service::find "$1") || return 1
  printf '%s%s\n' "$DECISION_SUPERSEDED" "$(framework.helpers.record::link "$DECISION_PREFIX" "$file")"
}

core.modules.decisions.service::status_target() {
  sed -n "$DECISION_LINK_TARGET_PATTERN" <<< "$1"
}

core.modules.decisions.service::create() {
  local slug="$1" status="$2" statement="$3" sections_dir="$4" path now
  path=$(framework.helpers.record::next_path "$DECISIONS_DIR" "$DECISION_PREFIX" "$slug") || return 1
  statement=$(printf '%s' "$statement" | framework.helpers.text::oneline)
  now=$(framework.helpers.date::now)
  {
    printf -- '---\nstatus: %s\ndescription: %s\ncreated: %s\nmodified: %s\n---\n\n' "$status" "$statement" "$now" "$now"
    printf '# %s\n\n' "$statement"
    cat -- "$sections_dir/.elaboration"
    printf '\n\n'
    framework.helpers.template::compose "$DECISION_TEMPLATE" "$sections_dir"
  } > "$sections_dir/.document"
  framework.helpers.template::trim_trailing_blank_lines "$sections_dir/.document"
  framework.helpers.fs::write "$path" < "$sections_dir/.document" || return 1
  printf '%s\n' "$path"
}

core.modules.decisions.service::update_status() {
  local file="$1" status="$2"
  framework.helpers.frontmatter::update "$file" status "$status" modified "$(framework.helpers.date::now)"
}

core.modules.decisions.service::link_targets() {
  local body="$1" line target
  while IFS= read -r line; do
    target=$(core.modules.decisions.service::status_target "$line")
    [ -z "$target" ] || printf '%s\n' "$target"
  done <<< "$body"
}

core.modules.decisions.service::broken_links() {
  local file self heading kind body target status
  for file in "$DECISIONS_DIR"/*.md; do
    [ -e "$file" ] || continue
    self=$(basename -- "$file")
    while IFS=$'\t' read -r heading kind; do
      [ -n "$heading" ] || continue
      body=$(framework.helpers.template::section "$file" "$heading")
      [ -n "$body" ] || continue
      while IFS= read -r target; do
        [ -n "$target" ] || continue
        printf 'checked\t%s\t%s\t%s\n' "$self" "$target" "$heading"
        if [ "$kind" = feature ]; then
          [ -e "$FEATURES_DIR/$target" ] && continue
        else
          [ -e "$DECISIONS_DIR/$target" ] && continue
        fi
        printf 'missing\t%s\t%s\t%s\n' "$self" "$target" "$heading"
      done < <(core.modules.decisions.service::link_targets "$body")
      if grep -qF -- "$self" <<< "$body"; then
        printf 'self\t%s\t%s\t%s\n' "$self" "$self" "$heading"
      fi
    done < <(core.modules.decisions.service::link_sections)
    status=$(framework.helpers.frontmatter::field "$file" status)
    target=$(core.modules.decisions.service::status_target "$status")
    [ -n "$target" ] || continue
    printf 'checked\t%s\t%s\tstatus\n' "$self" "$target"
    if [ ! -e "$DECISIONS_DIR/$target" ]; then
      printf 'missing\t%s\t%s\tstatus\n' "$self" "$target"
    elif [ "$target" = "$self" ]; then
      printf 'self\t%s\t%s\tstatus\n' "$self" "$self"
    fi
  done
}

core.modules.decisions.service::cites() {
  local body="$1" file="$2" number="$3"
  grep -qF -- "$file" <<< "$body" || grep -qE "(^|[^0-9])${number}([^0-9]|$)" <<< "$body"
}

core.modules.decisions.service::inbound() {
  local target="$1" number file self status reasons heading kind body
  number=$(framework.helpers.record::number "$target")
  for file in "$DECISIONS_DIR"/*.md; do
    [ -e "$file" ] || continue
    self=$(basename -- "$file")
    [ "$self" != "$target" ] || continue
    reasons=""
    status=$(framework.helpers.frontmatter::field "$file" status)
    case "$status" in
      "$DECISION_SUPERSEDED"*)
        if grep -qF -- "$target" <<< "$status"; then
          reasons="superseded by it"
        fi
        ;;
    esac
    while IFS=$'\t' read -r heading kind; do
      [ "$kind" = decision ] || continue
      body=$(framework.helpers.template::section "$file" "$heading")
      [ -n "$body" ] || continue
      if core.modules.decisions.service::cites "$body" "$target" "$number"; then
        reasons="${reasons:+$reasons; }lists it under \"$heading\""
      fi
    done < <(core.modules.decisions.service::link_sections)
    [ -z "$reasons" ] || printf '%s\t%s\n' "$self" "$reasons"
  done
}

core.modules.decisions.service::citing_features() {
  local heading file section cited decision number
  heading="$FEATURE_DECISIONS_HEADING"
  for file in "$FEATURES_DIR"/*.md; do
    [ -e "$file" ] || continue
    section=$(framework.helpers.template::section "$file" "$heading")
    [ -n "$section" ] || continue
    cited=""
    for decision in "$@"; do
      number=$(framework.helpers.record::number "$decision")
      if core.modules.decisions.service::cites "$section" "$decision" "$number"; then
        cited="${cited:+$cited, }$number"
      fi
    done
    [ -z "$cited" ] || printf '%s\t%s\n' "$(basename -- "$file")" "$cited"
  done
}

core.modules.decisions.service::search_directories() {
  case "$1" in
    all) printf '%s\n%s\n' "$DECISIONS_DIR" "$FEATURES_DIR" ;;
    decisions) printf '%s\n' "$DECISIONS_DIR" ;;
    features) printf '%s\n' "$FEATURES_DIR" ;;
  esac
}

core.modules.decisions.service::term_matches() {
  local scope="$1" directory file matched total hits term count
  shift
  while IFS= read -r directory; do
    [ -d "$directory" ] || continue
    for file in "$directory"/*.md; do
      [ -e "$file" ] || continue
      matched=0
      total=0
      hits=""
      for term in "$@"; do
        count=$(grep -icF -- "$term" "$file" || true)
        [ "$count" -gt 0 ] || continue
        matched=$((matched + 1))
        total=$((total + count))
        hits="${hits:+$hits, }$term"
      done
      [ "$matched" -eq 0 ] || printf '%d\t%d\t%s\t%s\n' "$matched" "$total" "$(dot::relative "$file")" "$hits"
    done
  done < <(core.modules.decisions.service::search_directories "$scope")
}

core.modules.decisions.service::matching_lines() {
  local file="$1" limit="$2" start term
  shift 2
  start=$(framework.helpers.frontmatter::end_line "$file")
  for term in "$@"; do
    grep -inF -- "$term" "$file" || true
  done | sort -t: -k1,1n -u | awk -F: -v start="$start" '$1 + 0 > start' | head -n "$limit"
}

core.modules.decisions.service::append_section() {
  local file="$1" value="$2"
  if [ -s "$file" ]; then
    printf '\n%s' "$value" >> "$file"
  else
    printf '%s' "$value" > "$file"
  fi
}
