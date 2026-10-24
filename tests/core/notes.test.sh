#!/usr/bin/env bash

test_note_gets_the_next_number() {
  dot notes:create
  assert_success
  dot notes:create --slug "Cache idea"
  assert_success
  assert_file "$DOTDOT/Notes/n001--template.md"
  assert_file "$DOTDOT/Notes/n002--cache-idea.md"
  assert_contains "$OUTPUT" "Notes/n002--cache-idea.md"
}

test_note_refuses_an_empty_slug() {
  dot notes:create --slug "!!!"
  assert_failure
  assert_contains "$ERRORS" "--slug"
}
