#!/usr/bin/env bash

TEXT_UTF8_LOCALES=(C.UTF-8 en_US.UTF-8 UTF-8)
TEXT_ZERO_WIDTH_RANGES=(
  "768 879"
  "8205 8205"
  "65024 65039"
  "127995 127999"
)
TEXT_WIDE_RANGES=(
  "4352 4447"
  "9728 10175"
  "11904 42191"
  "44032 55203"
  "63744 64255"
  "65280 65376"
  "65504 65510"
  "127462 127487"
  "127744 129791"
  "131072 262141"
)

framework.helpers.text::lower() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
}

framework.helpers.text::upper() {
  printf '%s' "$1" | tr '[:lower:]' '[:upper:]'
}

framework.helpers.text::slug() {
  local slug limit="${2-}"
  slug=$(framework.helpers.text::lower "$1" | LC_ALL=C sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//')
  if [ -n "$limit" ]; then
    slug="${slug:0:limit}"
    slug="${slug%-}"
  fi
  printf '%s' "$slug"
}

framework.helpers.text::trim() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
}

framework.helpers.text::oneline() {
  tr '\n' ' ' | sed -E 's/  +/ /g; s/^ +//; s/ +$//'
}

framework.helpers.text::is_one_line() {
  case "$1" in
    *$'\n'* | *$'\t'*) return 1 ;;
  esac
}

framework.helpers.text::has_control_characters() {
  [[ "$1" == *$'\n'* ]] || printf '%s' "$1" | LC_ALL=C grep '[[:cntrl:]]' >/dev/null
}

framework.helpers.text::escape_replacement() {
  printf '%s' "$1" | sed 's/[|&\\]/\\&/g'
}

framework.helpers.text::plural() {
  local count="$1" noun="$2"
  if [ "$count" -eq 1 ]; then
    printf '%s %s' "$count" "$noun"
  else
    printf '%s %ss' "$count" "$noun"
  fi
}

framework.helpers.text::repeat() {
  local unit="$1" count="$2" result="" index
  for ((index = 0; index < count; index++)); do
    result="$result$unit"
  done
  printf '%s' "$result"
}

framework.helpers.text::utf8_escape() {
  local codepoint="$1" lead count index byte tail=""
  if [ "$codepoint" -lt 128 ]; then
    printf '\\x%02x' "$codepoint"
    return
  fi
  if [ "$codepoint" -lt 2048 ]; then
    count=1 lead=192
  elif [ "$codepoint" -lt 65536 ]; then
    count=2 lead=224
  else
    count=3 lead=240
  fi
  for ((index = 0; index < count; index++)); do
    printf -v byte '\\x%02x' $(( 128 | (codepoint & 63) ))
    tail="$byte$tail"
    codepoint=$(( codepoint >> 6 ))
  done
  printf '\\x%02x%s' $(( lead | codepoint )) "$tail"
}

framework.helpers.text::character() {
  local character
  printf -v character "$(framework.helpers.text::utf8_escape "$1")"
  printf '%s' "$character"
}

framework.helpers.text::use_utf8_locale() {
  local candidate probe
  for candidate in "${TEXT_UTF8_LOCALES[@]}"; do
    { export LC_ALL="$candidate"; } 2>/dev/null
    probe=$(framework.helpers.text::character 233)
    [ "${#probe}" -ne 1 ] || return 0
  done
  return 1
}

framework.helpers.text::in_ranges() {
  local codepoint="$1" range start end
  shift
  for range in "$@"; do
    read -r start end <<< "$range"
    if [ "$codepoint" -ge "$start" ] && [ "$codepoint" -le "$end" ]; then
      return 0
    fi
  done
  return 1
}

framework.helpers.text::codepoint_width() {
  if framework.helpers.text::in_ranges "$1" "${TEXT_ZERO_WIDTH_RANGES[@]}"; then
    printf '0'
  elif framework.helpers.text::in_ranges "$1" "${TEXT_WIDE_RANGES[@]}"; then
    printf '2'
  else
    printf '1'
  fi
}

framework.helpers.text::width() {
  local value="$1" length=${#1} index=0 codepoint total=0
  while [ "$index" -lt "$length" ]; do
    codepoint=$(printf '%d' "'${value:index:1}")
    total=$((total + $(framework.helpers.text::codepoint_width "$codepoint")))
    index=$((index + 1))
  done
  printf '%s' "$total"
}
