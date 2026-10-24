#!/usr/bin/env bash

TESTS_DIR=$(CDPATH='' cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPOSITORY_DIR=$(dirname -- "$TESTS_DIR")
SOURCE_DIR="$REPOSITORY_DIR/dist"
DOTDOT_DIRECTORY=".dot"

sandbox::create() {
  SANDBOX=$(mktemp -d)
  SANDBOX=$(cd -P -- "$SANDBOX" && pwd)
  cp -a "$SOURCE_DIR" "$SANDBOX/$DOTDOT_DIRECTORY"
  ln -s "$DOTDOT_DIRECTORY/.core/system/bin/dot" "$SANDBOX/dot"
  DOTDOT="$SANDBOX/$DOTDOT_DIRECTORY"
}

sandbox::destroy() {
  [ -z "${SANDBOX-}" ] || rm -rf -- "$SANDBOX"
}

run() {
  local status=0
  OUTPUT=$(cd "$SANDBOX" && "$@" 2>"$SANDBOX/.stderr" </dev/null) || status=$?
  ERRORS=""
  IFS= read -r -d '' ERRORS < "$SANDBOX/.stderr" || true
  ERRORS="${ERRORS%$'\n'}"
  STATUS=$status
}

dot() {
  run bash ./dot "$@"
}

core() {
  local code="$1"
  run bash -c ". '$DOTDOT/.core/system/boot.sh'; set -euo pipefail; $code"
}

count_assertion() {
  [ -z "${ASSERTIONS_FILE-}" ] || printf '.' >> "$ASSERTIONS_FILE"
}

fail() {
  printf '%s\n' "$1" >&2
  printf '  stdout: %s\n  stderr: %s\n  status: %s\n' "${OUTPUT-}" "${ERRORS-}" "${STATUS-}" >&2
  exit 1
}

assert_success() {
  count_assertion
  [ "$STATUS" -eq 0 ] || fail "expected success${1:+: $1}"
}

assert_failure() {
  count_assertion
  [ "$STATUS" -ne 0 ] || fail "expected failure${1:+: $1}"
}

assert_equal() {
  count_assertion
  [ "$1" = "$2" ] || fail "expected [$2], got [$1]"
}

assert_contains() {
  count_assertion
  case "$1" in
    *"$2"*) ;;
    *) fail "expected to contain [$2]" ;;
  esac
}

assert_not_contains() {
  count_assertion
  case "$1" in
    *"$2"*) fail "expected not to contain [$2]" ;;
  esac
}

assert_file() {
  count_assertion
  [ -f "$1" ] || fail "expected file $1"
}

assert_no_file() {
  count_assertion
  [ ! -e "$1" ] && [ ! -L "$1" ] || fail "expected no file $1"
}

assert_link_to() {
  count_assertion
  [ -L "$1" ] || fail "expected a link at $1"
  [ "$(cd "$(dirname -- "$1")" && cd -P -- "$(dirname -- "$(readlink "$1")")" && pwd)/$(basename -- "$(readlink "$1")")" = "$2" ] \
    || fail "expected $1 to point at $2, got $(readlink "$1")"
}

CLAUDE_CODE_PLUGIN_DIR="$REPOSITORY_DIR/plugins/claude-code"

# The claude-code plugin's files in place, without adding it: enough to run
# its scripts.
copy_claude_code() {
  mkdir -p "$DOTDOT/.plugins/dotdot-sh"
  cp -R "$CLAUDE_CODE_PLUGIN_DIR/dotdot" "$DOTDOT/.plugins/dotdot-sh/claude-code"
}

add_claude_code() {
  cp -R "$CLAUDE_CODE_PLUGIN_DIR" "$SANDBOX/claude-code"
  add_plugin dotdot-sh/claude-code claude-code
  dot sync -y
}

add_plugin() {
  local plugin="$1" path="$2"
  core "dot::use core.system.plugins.console core.system.plugins.manifest core.system.plugins.service
    core.system.plugins.service::fetch $plugin '' $path
    core.system.plugins.manifest::validate \"\$PLUGIN_SOURCE\" $plugin
    core.system.plugins.console::install $plugin \"\$PLUGIN_SOURCE\""
  assert_success "add $plugin"
}
