#!/usr/bin/env bash

physical() {
  (cd -P -- "$1" && pwd)
}

test_fs_resolve_follows_links_and_dot_segments() {
  local root
  root=$(physical "$SANDBOX")
  mkdir -p "$SANDBOX/a/b/c" "$SANDBOX/x/y"
  ln -s a/b "$SANDBOX/lb"
  ln -s ../x "$SANDBOX/a/b/c/up"
  ln -s lb "$SANDBOX/chain"
  core "cd '$SANDBOX'; dot::use framework.helpers.fs; framework.helpers.fs::resolve chain/./c//; framework.helpers.fs::resolve chain/c/up/../y; framework.helpers.fs::resolve missing/deep/../file"
  assert_success
  assert_equal "$OUTPUT" "$root/a/b/c
$root/a/b/y
$root/missing/file"
}

test_fs_resolve_detects_link_loops() {
  ln -s loop-a "$SANDBOX/loop-b"
  ln -s loop-b "$SANDBOX/loop-a"
  core "dot::use framework.helpers.fs; framework.helpers.fs::resolve '$SANDBOX/loop-a'"
  assert_failure
}

test_fs_relative_walks_up_and_down() {
  mkdir -p "$SANDBOX/a/b" "$SANDBOX/c"
  core "dot::use framework.helpers.fs; framework.helpers.fs::relative '$SANDBOX/c/file' '$SANDBOX/a/b'; framework.helpers.fs::relative '$SANDBOX/a' '$SANDBOX/a'; framework.helpers.fs::relative '$SANDBOX/a/b' '$SANDBOX'"
  assert_success
  assert_equal "$OUTPUT" "../../c/file
.
a/b"
}

test_fs_within_refuses_escapes() {
  ln -s / "$SANDBOX/root-link"
  core "dot::use framework.helpers.fs; framework.helpers.fs::within ../outside '$SANDBOX'"
  assert_failure
  core "dot::use framework.helpers.fs; framework.helpers.fs::within root-link/etc '$SANDBOX'"
  assert_failure
  core "dot::use framework.helpers.fs; framework.helpers.fs::within inside/file '$SANDBOX'"
  assert_success
  assert_equal "$OUTPUT" "$(physical "$SANDBOX")/inside/file"
}

test_text_slug_and_limit() {
  local limit=4
  core "dot::use framework.helpers.text; framework.helpers.text::slug '  Hello, World! '; printf '\n'; framework.helpers.text::slug 'abc def ghi' $limit"
  assert_success
  assert_equal "$OUTPUT" "hello-world
abc"
}

test_text_character_encodes_every_utf8_length() {
  local codepoint
  for codepoint in 65 233 8364 128512; do
    core "dot::use framework.helpers.text; framework.helpers.text::character $codepoint | od -An -tx1 | tr -d ' \n'"
    assert_success
    assert_equal "$OUTPUT" "$(LC_ALL=C.UTF-8 bash -c "printf '\\U%08x' $codepoint | xargs -0 printf '%b'" | od -An -tx1 | tr -d ' \n')"
  done
}

test_text_width_counts_wide_characters() {
  core "dot::use framework.helpers.text; framework.helpers.text::use_utf8_locale; framework.helpers.text::width \"\$(framework.helpers.text::character 128512)a\""
  assert_success
  assert_equal "$OUTPUT" "3"
}

test_kv_writes_reads_and_removes() {
  local file="$SANDBOX/settings.conf"
  printf '# comment\nexport FIRST="one"\nSECOND=two\n' > "$file"
  chmod 600 "$file"
  core "dot::use framework.helpers.kv; framework.helpers.kv::write '$file' SECOND changed; framework.helpers.kv::write '$file' THIRD three; framework.helpers.kv::remove '$file' FIRST; framework.helpers.kv::value '$file' SECOND; framework.helpers.kv::keys '$file'"
  assert_success
  assert_equal "$OUTPUT" "changed
SECOND
THIRD"
  assert_contains "$(cat "$file")" "# comment"
  assert_equal "$(ls -l "$file" | cut -c1-10)" "-rw-------"
}

test_kv_never_executes_values() {
  local file="$SANDBOX/settings.conf"
  printf 'KEY=$(touch %s/pwned)\n' "$SANDBOX" > "$file"
  core "dot::use framework.helpers.kv; framework.helpers.kv::value '$file' KEY"
  assert_success
  assert_no_file "$SANDBOX/pwned"
}

test_config_reads_only_the_env_file() {
  printf 'SAMPLE_SETTING=from-env-file\nEMPTY_SETTING=\n' > "$DOTDOT/.env"
  printf 'SAMPLE_SETTING=from-example\nMISSING_SETTING=from-example\n' > "$DOTDOT/.core/.env.example"
  core "SAMPLE_SETTING=from-environment dot::config SAMPLE_SETTING"
  assert_success
  assert_equal "$OUTPUT" "from-env-file"
  core "MISSING_SETTING=from-environment dot::config MISSING_SETTING"
  assert_failure
  assert_contains "$ERRORS" "MISSING_SETTING is not set: set it in .dot/.env"
  core "dot::config EMPTY_SETTING"
  assert_failure
  assert_contains "$ERRORS" "EMPTY_SETTING is not set"
  core "dot::optional_config MISSING_SETTING || printf unset"
  assert_success
  assert_equal "$OUTPUT" "unset"
}

test_config_is_saved_privately() {
  core "dot::save_config SAMPLE_SETTING 'a value'; dot::config SAMPLE_SETTING"
  assert_success
  assert_equal "$OUTPUT" "a value"
  assert_equal "$(ls -l "$DOTDOT/.env" | cut -c1-10)" "-rw-------"
  core "dot::save_config 'bad key' x"
  assert_failure
  assert_contains "$ERRORS" "Invalid setting name"
}

test_frontmatter_update_touches_only_the_block() {
  local file="$SANDBOX/doc.md"
  printf -- '---\nstatus: draft\nmodified: then\n---\n\nstatus: prose stays\n' > "$file"
  core "dot::use framework.helpers.frontmatter; framework.helpers.frontmatter::update '$file' status accepted modified now; framework.helpers.frontmatter::field '$file' status; framework.helpers.frontmatter::body '$file'"
  assert_success
  assert_equal "$OUTPUT" "accepted
status: prose stays"
}

test_frontmatter_update_fails_on_missing_key() {
  local file="$SANDBOX/doc.md"
  printf -- '---\nstatus: draft\n---\n' > "$file"
  core "dot::use framework.helpers.frontmatter; framework.helpers.frontmatter::update '$file' modified now"
  assert_failure
  assert_equal "$(cat "$file")" "$(printf -- '---\nstatus: draft\n---')"
}

test_record_numbers_never_read_as_octal() {
  local directory="$SANDBOX/records"
  mkdir -p "$directory"
  : > "$directory/x008--a.md"
  : > "$directory/x009--b.md"
  core "dot::use framework.helpers.record; framework.helpers.record::next_number '$directory' x"
  assert_success
  assert_equal "$OUTPUT" "010"
}

test_gh_token_is_read_only_for_each_gh_call() {
  mkdir -p "$SANDBOX/bin"
  printf '#!/bin/sh\nprintf "%%s\\n" "${GH_TOKEN-none}"\n' > "$SANDBOX/bin/gh"
  chmod +x "$SANDBOX/bin/gh"
  printf 'GH_TOKEN=secret-token\n' > "$DOTDOT/.env"
  core "PATH='$SANDBOX/bin':\$PATH; dot::use framework.integrations.github-cli.service
    printf 'loaded:%s\n' \"\${GH_TOKEN-none}\"
    framework.integrations.github-cli.service::run
    printf 'after:%s\n' \"\${GH_TOKEN-none}\""
  assert_success
  assert_equal "$OUTPUT" "loaded:none
secret-token
after:none"
}

test_user_timezone_applies_and_unknown_ones_are_ignored() {
  printf -- '---\nname: me\ntimezone: "Europe/Madrid" # mine\n---\n\ntimezone: UTC\n' > "$DOTDOT/USER.md"
  core 'printf "%s" "${TZ-}"'
  assert_equal "$OUTPUT" "Europe/Madrid"
  printf -- '---\ntimezone: Nowhere/Land\n---\n' > "$DOTDOT/USER.md"
  core 'printf "%s" "${TZ-unset}"'
  assert_equal "$OUTPUT" "unset"
  assert_contains "$ERRORS" "Ignoring unknown timezone in USER.md: Nowhere/Land"
}
