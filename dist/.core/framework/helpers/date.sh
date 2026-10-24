#!/usr/bin/env bash

DATE_TIMESTAMP_FORMAT='%Y-%m-%d %H:%M:%S'
DATE_STAMP_FORMAT='%Y%m%d-%H%M%S'
DATE_CLOCK_FORMAT='%H:%M:%S'
DATE_ISO_UTC_FORMAT='%Y-%m-%dT%H:%M:%SZ'
DATE_ZONEINFO_DIR="/usr/share/zoneinfo"
DATE_ZONE_PATTERN='^[A-Za-z][A-Za-z0-9_+-]*(/[A-Za-z0-9_+-]+)*$'

framework.helpers.date::now() {
  date "+$DATE_TIMESTAMP_FORMAT"
}

framework.helpers.date::stamp() {
  date "+$DATE_STAMP_FORMAT"
}

framework.helpers.date::clock() {
  date "+$DATE_CLOCK_FORMAT"
}

framework.helpers.date::from_epoch() {
  local epoch="$1" format="${2:-$DATE_TIMESTAMP_FORMAT}"
  LC_ALL=C date -d "@$epoch" "+$format" 2>/dev/null || LC_ALL=C date -r "$epoch" "+$format"
}

framework.helpers.date::from_iso() {
  local iso="$1" epoch
  date -d "$iso" "+$DATE_TIMESTAMP_FORMAT" 2>/dev/null && return 0
  epoch=$(date -j -u -f "$DATE_ISO_UTC_FORMAT" "$iso" '+%s') || return 1
  framework.helpers.date::from_epoch "$epoch"
}

framework.helpers.date::use_timezone() {
  local zone="$1"
  case "$zone" in
    UTC+[0-9] | UTC+1[0-4]) zone="Etc/GMT-${zone#UTC+}" ;;
    UTC-[0-9] | UTC-1[0-2]) zone="Etc/GMT+${zone#UTC-}" ;;
  esac
  [[ "$zone" =~ $DATE_ZONE_PATTERN ]] && [ -f "$DATE_ZONEINFO_DIR/$zone" ] || return 1
  export TZ="$zone"
}
