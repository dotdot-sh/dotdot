#!/usr/bin/env bash

command_names() {
  local directory
  for directory in "$DOTDOT"/.core/system/*/commands "$DOTDOT"/.core/modules/*/commands; do
    (cd "$directory" && find . -name '*.sh' | sed 's|^\./||; s|\.sh$||; s|/|:|g')
  done | sort
}

test_every_command_is_listed_and_answers_help() {
  local name
  dot
  while IFS= read -r name; do
    assert_contains "$OUTPUT" "$name"
  done < <(command_names)
  core 'while IFS="|" read -r name file; do
      ( DOT_COMMAND="$name"; . "$file"; usage ) >/dev/null || { printf "%s --help failed\n" "$name" >&2; exit 1; }
    done < <(kernel::core_commands)'
  assert_success
  [ -z "$ERRORS" ] || fail "a command's --help wrote to stderr: $ERRORS"
}

test_help_command_matches_help_flag() {
  local expected
  dot sync --help
  expected="$OUTPUT"
  dot help sync
  assert_success
  assert_equal "$OUTPUT" "$expected"
}

test_unknown_command_fails_with_hint() {
  dot nothing:here
  assert_failure
  assert_contains "$ERRORS" "Unknown command: nothing:here"
}

test_invalid_command_name_is_refused() {
  dot '../escape'
  assert_failure
  assert_contains "$ERRORS" "Invalid command"
}

test_runs_through_a_symlinked_entry_point() {
  ln -s "$SANDBOX/dot" "$SANDBOX/second"
  run bash ./second scan:frontmatter AGENTS.md
  assert_success
  assert_contains "$OUTPUT" "AGENTS.md"
}

test_refuses_to_run_under_sh() {
  run sh ./dot
  assert_failure
  assert_contains "$ERRORS" "bash"
}

test_modules_load_by_dotted_path() {
  mkdir -p "$DOTDOT/.plugins/acme/tools"
  printf '#!/usr/bin/env bash\nplugins.acme.tools.greet::greet() { printf "hi %%s" "$1"; }\n' > "$DOTDOT/.plugins/acme/tools/greet.sh"
  core "dot::use framework.helpers.text plugins.acme.tools.greet; plugins.acme.tools.greet::greet \"\$(framework.helpers.text::slug 'Dotted Path')\""
  assert_success
  assert_equal "$OUTPUT" "hi dotted-path"
}

test_unknown_or_undotted_modules_fail() {
  local module
  for module in text tools.missing tools..fs acme.tools.greet core.nothing.here; do
    core "dot::use $module"
    assert_failure "$module"
    assert_contains "$ERRORS" "Unknown dotdot module: $module"
  done
}

test_record_folders_ship_with_dotdot() {
  local folder
  core 'for folder in "$FEATURES_DIR" "$DECISIONS_DIR" "$NOTES_DIR" "$TASKS_DIR"; do printf "%s\n" "${folder#"$DOTDOT_ROOT"/}"; done'
  assert_success
  while IFS= read -r folder; do
    assert_file "$DOTDOT/$folder/.gitkeep"
    ! git -C "$REPOSITORY_DIR" check-ignore -q "dist/$folder/.gitkeep" || fail "dist/$folder/.gitkeep is git-ignored, so installs would not get it"
  done <<< "$OUTPUT"
}
