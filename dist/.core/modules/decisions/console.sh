#!/usr/bin/env bash

dot::use framework.console.args

core.modules.decisions.console::choose_status() {
  local current="$1" requested="$2"
  [ -z "$current" ] || framework.console.args::invalid "Only one status flag per run, got --$current and --$requested."
  printf '%s\n' "$requested"
}
