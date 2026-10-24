#!/usr/bin/env bash

use_plain_tasks() {
  printf 'TASKS_SERVICE=plain\n' > "$DOTDOT/.env"
}

test_tasks_need_initialization_at_a_terminal() {
  dot tasks:list
  assert_failure
  assert_contains "$ERRORS" "tasks:initialize"
}

test_github_tasks_need_their_repository_setting() {
  printf 'TASKS_SERVICE=github\n' > "$DOTDOT/.env"
  mkdir -p "$SANDBOX/bin"
  printf '#!/bin/sh\nexit 0\n' > "$SANDBOX/bin/gh"
  chmod +x "$SANDBOX/bin/gh"
  run env PATH="$SANDBOX/bin:$PATH" bash ./dot tasks:list
  assert_failure
  assert_contains "$ERRORS" "TASKS_GITHUB_REPO is not set: set it in .dot/.env"
}

test_task_lifecycle_with_plain_files() {
  local file
  use_plain_tasks
  dot tasks:create --title "Write tests" --description "Cover the kernel."
  assert_success
  assert_contains "$OUTPUT" "Task t001 created (todo): Write tests"
  file="$DOTDOT/Tasks/t001--write-tests.md"
  assert_file "$file"
  assert_contains "$(cat "$file")" "Cover the kernel."
  dot tasks:doing t001
  assert_success
  assert_contains "$(cat "$file")" "status: doing"
  dot tasks:update 1 --title "Write more tests" --done-when "- [x] kernel"
  assert_success
  assert_contains "$(cat "$file")" "title: Write more tests"
  assert_contains "$(cat "$file")" "- [x] kernel"
  assert_contains "$(cat "$file")" "Cover the kernel."
  dot tasks:show t001 --print
  assert_success
  assert_contains "$OUTPUT" "id: t001"
  dot tasks:list --status doing
  assert_success
  assert_contains "$OUTPUT" "Write more tests"
  dot tasks:list --status "done"
  assert_contains "$OUTPUT" "No tasks with status done."
}

test_task_list_pages() {
  local index
  use_plain_tasks
  for index in 1 2 3; do
    dot tasks:create --title "Task $index" --no-editor
  done
  dot tasks:list --limit 2 --page 2
  assert_success
  assert_contains "$OUTPUT" "Task 3"
  assert_not_contains "$OUTPUT" "Task 1"
  assert_contains "$OUTPUT" "Page 2/2"
  dot tasks:list --limit 2 --page 9
  assert_contains "$ERRORS" "The last page is --page 2"
}

test_task_input_is_validated() {
  use_plain_tasks
  dot tasks:create
  assert_failure
  assert_contains "$ERRORS" "--title"
  dot tasks:create --title "x" --status nonsense
  assert_failure
  assert_contains "$ERRORS" "Unknown status: nonsense"
  dot tasks:update t001
  assert_failure
  assert_contains "$ERRORS" "Nothing to update"
  dot tasks:list --status ""
  assert_failure
  assert_contains "$ERRORS" "--status requires a value"
  dot tasks:create --title "x" --body-file ../../etc/passwd
  assert_failure
  assert_contains "$ERRORS" "inside the project"
}

test_task_delete_needs_a_terminal() {
  use_plain_tasks
  dot tasks:create --title "Keep me"
  dot tasks:delete t001
  assert_failure
  assert_file "$DOTDOT/Tasks/t001--keep-me.md"
}

test_unknown_tasks_fail_without_side_effects() {
  use_plain_tasks
  dot tasks:doing t999
  assert_failure
  assert_contains "$ERRORS" "No task t999"
  dot tasks:show t999
  assert_failure
  assert_contains "$ERRORS" "No task t999"
}
