#!/usr/bin/env bash

test_update_needs_a_terminal() {
  dot update -y
  assert_failure
  assert_contains "$ERRORS" "needs a terminal"
}

test_update_records_the_version() {
  rm -f "$DOTDOT/.core/version"
  core "dot::use core.system.update.service
    core.system.update.service::record_version 0123456789012345678901234567890123456789"
  assert_success
  assert_equal "$(cat "$DOTDOT/.core/version")" "0123456789012345678901234567890123456789"
}

commit_tree() {
  local repository="$1" message="$2"
  git -C "$repository" add -A
  git -C "$repository" -c user.name=t -c user.email=t@t -c commit.gpgsign=false commit -qm "$message"
  git -C "$repository" rev-parse HEAD
}

test_update_replaces_adds_and_removes_only_what_upstream_removed() {
  local upstream="$SANDBOX/upstream" core_dir="$DOTDOT/.core" old new
  mkdir -p "$upstream/dist/.core/demo"
  git init -q "$upstream"
  printf 'old\n' > "$upstream/dist/.core/demo/kept.sh"
  printf 'old\n' > "$upstream/dist/.core/demo/gone.sh"
  printf 'old\n' > "$upstream/dist/.core/demo/edited.sh"
  old=$(commit_tree "$upstream" old)
  printf 'new\n' > "$upstream/dist/.core/demo/kept.sh"
  printf 'new\n' > "$upstream/dist/.core/demo/added.sh"
  rm "$upstream/dist/.core/demo/gone.sh" "$upstream/dist/.core/demo/edited.sh"
  new=$(commit_tree "$upstream" new)
  git -C "$upstream" update-ref refs/dotdot/new "$new"
  git -C "$upstream" update-ref refs/dotdot/old "$old"
  mkdir -p "$core_dir/demo"
  printf 'old\n' > "$core_dir/demo/kept.sh"
  printf 'old\n' > "$core_dir/demo/gone.sh"
  printf 'mine\n' > "$core_dir/demo/edited.sh"
  printf '%s\n' "$old" > "$core_dir/version"
  : > "$core_dir/dotdot_ready"
  core "dot::use core.system.update.service
    UPDATE_REPOSITORY='$upstream'
    core.system.update.service::extract $new dist '$SANDBOX/tree'
    core.system.update.service::compare '$SANDBOX/tree/dist'
    core.system.update.service::find_removed $old $new dist
    core.system.update.service::find_unknown '$SANDBOX/tree/dist'
    core.system.update.service::copy '$SANDBOX/tree/dist'
    printf 'edited:%s\n' \"\${UPDATE_EDITED[*]}\"
    printf 'unknown:%s\n' \"\${UPDATE_UNKNOWN[*]}\""
  assert_success
  assert_equal "$(cat "$core_dir/demo/kept.sh")" "new"
  assert_equal "$(cat "$core_dir/demo/added.sh")" "new"
  assert_no_file "$core_dir/demo/gone.sh"
  assert_equal "$(cat "$core_dir/demo/edited.sh")" "mine"
  assert_contains "$OUTPUT" "edited:.core/demo/edited.sh"
  assert_file "$core_dir/system/boot.sh"
  assert_equal "$(cat "$core_dir/version")" "$old"
  assert_file "$core_dir/dotdot_ready"
  assert_not_contains "$OUTPUT" ".core/version"
  assert_not_contains "$OUTPUT" ".core/dotdot_ready"
}
