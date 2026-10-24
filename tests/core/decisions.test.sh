#!/usr/bin/env bash

create_decision() {
  dot decisions:create --name "$1" --statement "We $1." --elaboration "Because." "${@:2}"
  assert_success "create decision $1"
}

test_decision_links_are_resolved() {
  create_decision "keep it simple" --accepted
  create_decision "use bash" --influenced-by 1
  assert_contains "$(cat "$DOTDOT/Decisions/d002--use-bash.md")" "[d001](d001--keep-it-simple.md)"
  dot decisions:create --name dangling --statement x --elaboration y --influenced-by 42
  assert_failure
  assert_contains "$ERRORS" "matches no decision"
}

test_decision_refuses_two_statuses() {
  dot decisions:create --name a --statement b --elaboration c --accepted --rejected
  assert_failure
  assert_contains "$ERRORS" "Only one status flag"
}

test_decision_update_sets_status_and_timestamp() {
  local file="$DOTDOT/Decisions/d001--first.md"
  create_decision first
  create_decision second
  sed -i.bak 's/^modified: .*/modified: earlier/' "$file" && rm -f "$file.bak"
  dot decisions:update 1 --superseded 2
  assert_success
  assert_contains "$(cat "$file")" "status: superseded by [d002](d002--second.md)"
  assert_not_contains "$(cat "$file")" "modified: earlier"
  dot decisions:update 1 --superseded 1
  assert_failure
  assert_contains "$ERRORS" "cannot supersede itself"
}

test_decision_impact_reports_links_and_terms() {
  create_decision "first rule"
  create_decision "second rule" --influenced-by 1
  dot features:create --name login --description "Session cookies." --related-project-decisions "- [d001](../Decisions/d001--first-rule.md)"
  assert_success
  dot decisions:impact --check
  assert_success
  assert_contains "$OUTPUT" "all resolve"
  dot decisions:impact --inbound 1
  assert_contains "$OUTPUT" "d002--second-rule.md"
  dot decisions:impact --decisions 1
  assert_contains "$OUTPUT" "f001--login.md"
  dot decisions:impact --terms "cookies,nothing-like-this"
  assert_contains "$OUTPUT" "matched 1 of 2 terms"
  rm "$DOTDOT/Decisions/d001--first-rule.md"
  dot decisions:impact --check
  assert_failure
  assert_contains "$OUTPUT" "does not exist"
}

test_decision_impact_needs_something_to_do() {
  dot decisions:impact --terms=","
  assert_failure
  assert_contains "$ERRORS" "Nothing to do"
}
