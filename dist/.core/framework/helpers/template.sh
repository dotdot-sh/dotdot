#!/usr/bin/env bash

dot::use framework.helpers.text

TEMPLATE_HEADING_PREFIX="## "
TEMPLATE_EMPTY_SECTION="None"

framework.helpers.template::headings() {
  grep "^$TEMPLATE_HEADING_PREFIX" "$1" | sed "s/^$TEMPLATE_HEADING_PREFIX//"
}

framework.helpers.template::key() {
  framework.helpers.text::slug "$(printf '%s' "$1" | sed -E 's/\([^)]*\)//g')"
}

framework.helpers.template::keys() {
  local heading
  while IFS= read -r heading; do
    printf '%s\n' "$(framework.helpers.template::key "$heading")"
  done < <(framework.helpers.template::headings "$1")
}

framework.helpers.template::has_key() {
  framework.helpers.template::keys "$1" | grep -xF -- "$2" >/dev/null
}

framework.helpers.template::heading() {
  local heading
  while IFS= read -r heading; do
    if [ "$(framework.helpers.template::key "$heading")" = "$2" ]; then
      printf '%s\n' "$heading"
      return 0
    fi
  done < <(framework.helpers.template::headings "$1")
  return 1
}

framework.helpers.template::options() {
  grep -m1 "^$2:" "$1" \
    | sed -n 's/.*{\(.*\)}.*/\1/p' \
    | tr '|' '\n' \
    | sed -E 's/^ +//; s/ +$//' \
    | grep -v '\[' \
    | grep -v '^$' || true
}

framework.helpers.template::section_kinds() {
  awk -v prefix="$TEMPLATE_HEADING_PREFIX" '
    index($0, prefix) == 1 { heading = substr($0, length(prefix) + 1); wanted = 1; next }
    wanted && NF {
      kind = "text"
      if ($0 ~ /fNNN--/) kind = "feature"
      else if ($0 ~ /dNNN--/) kind = "decision"
      print heading "\t" kind
      wanted = 0
    }
  ' "$1"
}

framework.helpers.template::compose() {
  local template="$1" sections_dir="$2" heading key
  while IFS= read -r heading; do
    key=$(framework.helpers.template::key "$heading")
    printf '%s%s\n\n' "$TEMPLATE_HEADING_PREFIX" "$heading"
    if [ -s "$sections_dir/$key" ]; then
      cat -- "$sections_dir/$key"
    else
      printf '%s' "$TEMPLATE_EMPTY_SECTION"
    fi
    printf '\n\n'
  done < <(framework.helpers.template::headings "$template")
}

framework.helpers.template::section() {
  awk -v heading="$TEMPLATE_HEADING_PREFIX$2" -v prefix="$TEMPLATE_HEADING_PREFIX" '
    $0 == heading { inside = 1; next }
    index($0, prefix) == 1 { inside = 0 }
    inside
  ' "$1"
}

framework.helpers.template::replace_section() {
  local file="$1" heading="$2" content="$3"
  awk -v heading="$TEMPLATE_HEADING_PREFIX$heading" -v prefix="$TEMPLATE_HEADING_PREFIX" -v source="$content" '
    function emit(  line) {
      print heading; print ""
      while ((getline line < source) > 0) print line
      close(source); print ""
    }
    $0 == heading { emit(); skip = 1; done = 1; next }
    skip && index($0, prefix) == 1 { skip = 0 }
    !skip { print }
    END { if (!done) { print ""; emit() } }
  ' "$file" > "$file.section-$$" && mv -f -- "$file.section-$$" "$file"
}

framework.helpers.template::trim_trailing_blank_lines() {
  local file="$1" content
  content=$(cat -- "$file")
  printf '%s\n' "$content" > "$file"
}
