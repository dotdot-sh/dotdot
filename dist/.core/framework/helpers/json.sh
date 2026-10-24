#!/usr/bin/env bash

framework.helpers.json::field() {
  local document="$1" path="$2"
  printf '%s' "$document" | jq -r "$path // empty" 2>/dev/null | LC_ALL=C tr -d '[:cntrl:]'
}

