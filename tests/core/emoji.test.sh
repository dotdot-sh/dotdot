#!/usr/bin/env bash

visible_width() {
  core "dot::use framework.helpers.text; framework.helpers.text::use_utf8_locale; framework.helpers.text::width \"\$(printf '%s' '$1' | sed 's/\x1b\[[0-9;]*m//g')\""
  printf '%s' "$OUTPUT"
}

HR=".dot/.plugins/dotdot-sh/claude-code/claude/hooks/claude-code-emoji-hr/hr.sh"

test_divider_fills_the_terminal_width() {
  local width=37 line
  copy_claude_code
  run env COLUMNS="$width" bash "$HR" '#'
  assert_success
  assert_equal "${#OUTPUT}" "$width"
  run env COLUMNS="$width" bash "$HR" -r rainbow --date
  assert_success
  line="$OUTPUT"
  assert_equal "$(visible_width "$line")" "$width"
}

test_divider_refuses_control_characters_and_bad_colors() {
  copy_claude_code
  run bash "$HR" $'\033[31m'
  assert_failure
  assert_contains "$ERRORS" "control characters"
  run bash "$HR" '#' blue
  assert_failure
  assert_contains "$ERRORS" "#RRGGBB"
}

test_stop_hook_wraps_the_divider_for_claude_code() {
  copy_claude_code
  run bash .dot/.plugins/dotdot-sh/claude-code/claude/hooks/claude-code-emoji-hr/Stop.sh
  assert_success
  assert_contains "$OUTPUT" '"systemMessage"'
}
