#!/usr/bin/env bash

test_release_validates_its_arguments() {
  dot release:create
  assert_failure
  assert_contains "$ERRORS" "A version is required"
  dot release:create not-a-version
  assert_failure
  assert_contains "$ERRORS" "Not a semantic version"
  dot release:create 1.0.0 --cache-pat=soon
  assert_failure
  assert_contains "$ERRORS" "--cache-pat"
}

release_settings_stub() {
  printf '%s\n' "$DOTDOT/.core/modules/release/stubs/env.stub"
}

test_release_seeds_missing_settings_and_stops() {
  local key
  git -C "$SANDBOX" init -q
  dot release:create 1.0.0
  assert_failure
  assert_contains "$ERRORS" "were added to .dot/.env"
  while IFS= read -r key; do
    assert_contains "$(cat "$DOTDOT/.env")" "$key="
  done < <(sed -n 's/^\([A-Z_]*\)=.*/\1/p' "$(release_settings_stub)")
  assert_equal "$(ls -l "$DOTDOT/.env" | cut -c1-10)" "-rw-------"
  dot release:create 1.0.0
  assert_failure
  assert_contains "$ERRORS" "is not set: set it in .dot/.env"
}

test_release_seeds_only_the_missing_settings() {
  printf 'RELEASE_BRANCH=release\n' > "$DOTDOT/.env"
  dot release:push
  assert_failure
  assert_equal "$(grep -c '^RELEASE_BRANCH=' "$DOTDOT/.env")" "1"
  assert_contains "$(cat "$DOTDOT/.env")" "RELEASE_BRANCH=release"
}

test_release_remotes_must_be_set_and_https_without_credentials() {
  cp "$(release_settings_stub)" "$DOTDOT/.env"
  dot release:token github
  assert_failure
  assert_contains "$ERRORS" "Set RELEASE_REMOTE_GITHUB"
  sed -i.bak 's|^RELEASE_REMOTE_GITHUB=.*|RELEASE_REMOTE_GITHUB=https://user:secret@github.com/acme/repo.git|; /^RELEASE_REMOTE_HUGGINGFACE=/d' "$DOTDOT/.env"
  dot release:token github
  assert_failure
  assert_contains "$ERRORS" "without credentials"
}

release_repository() {
  git -C "$SANDBOX" init -q
  printf 'tracked\n' > "$SANDBOX/tracked.txt"
  printf '.dot/\nbuild/\n' > "$SANDBOX/.gitignore"
  git -C "$SANDBOX" add tracked.txt .gitignore
  git -C "$SANDBOX" -c user.name=t -c user.email=t@t -c commit.gpgsign=false commit -qm initial
}

test_release_exclusions_stay_inside_the_project_and_never_ship_the_env() {
  local entry reason
  release_repository
  mkdir -p "$SANDBOX/build"
  : > "$SANDBOX/build/out"
  : > "$DOTDOT/.env"
  while IFS='|' read -r entry reason; do
    printf '%s\n' "$entry" > "$SANDBOX/release.exclude"
    core "cd '$SANDBOX'; dot::use core.modules.release.service; core.modules.release.service::read_exclusions release.exclude"
    assert_failure "$entry"
    assert_contains "$ERRORS" "$reason"
  done <<'CASES'
../outside|outside the project
!.dot|holds dotdot's .env
!tracked.txt|must be a git-ignored path
CASES
  printf '!build\n' > "$SANDBOX/release.exclude"
  core "cd '$SANDBOX'; dot::use core.modules.release.service; core.modules.release.service::read_exclusions release.exclude; printf '%s\n' \"\${RELEASE_COPIED[@]}\""
  assert_success
  assert_equal "$OUTPUT" "build"
}

test_release_export_refuses_secrets() {
  local destination="$SANDBOX/export"
  mkdir -p "$destination"
  printf 'token=ghp_%s\n' "abcdefghijklmnopqrstuvwxyz0123456789" > "$destination/config.txt"
  core "dot::use core.modules.release.service; RELEASE_DESTINATION='$destination'; core.modules.release.service::scan_secrets"
  assert_failure
  assert_contains "$ERRORS" "Possible secrets in export"
  assert_contains "$ERRORS" "config.txt"
  printf 'nothing to see\n' > "$destination/config.txt"
  core "dot::use core.modules.release.service; RELEASE_DESTINATION='$destination'; core.modules.release.service::scan_secrets"
  assert_success
}
