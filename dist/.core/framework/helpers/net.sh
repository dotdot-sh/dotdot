#!/usr/bin/env bash

framework.helpers.net::download() {
  local url="$1" file="$2" header
  shift 2
  case "$url" in
    https://*) ;;
    *) return 1 ;;
  esac
  for header in "$@"; do
    case "$header" in
      *$'\n'* | *'"'*) return 1 ;;
    esac
    printf 'header = "%s"\n' "$header"
  done | curl --proto '=https' --tlsv1.2 -fsSL --config - -o "$file" "$url"
}
