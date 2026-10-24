#!/usr/bin/env bash

test_feature_is_built_from_the_template() {
  local file
  dot features:create --name "Password reset" --description "Lets a user reset a password." --specification "Given a user"
  assert_success
  file="$DOTDOT/Features/f001--password-reset.md"
  assert_file "$file"
  assert_contains "$(cat "$file")" "description: Lets a user reset a password."
  assert_contains "$(cat "$file")" "Given a user"
}

test_feature_requires_name_and_description() {
  dot features:create --name "Only a name"
  assert_failure
  assert_contains "$ERRORS" "--description"
  dot features:create --name "Bad" --description "x" --not-a-section "y"
  assert_failure
  assert_contains "$ERRORS" "Unknown flag"
}
