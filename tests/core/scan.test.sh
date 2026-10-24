#!/usr/bin/env bash

test_scan_frontmatter_stays_inside_dotdot() {
  dot notes:create --slug scanned
  dot scan:frontmatter Notes
  assert_success
  assert_contains "$OUTPUT" "(no frontmatter)"
  dot scan:frontmatter ../..
  assert_failure
  ln -s / "$DOTDOT/escape"
  dot scan:frontmatter escape
  assert_failure
  assert_contains "$ERRORS" "outside the dotdot directory"
}
