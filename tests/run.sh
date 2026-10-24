#!/usr/bin/env bash

set -uo pipefail

. "$(dirname -- "$0")/lib.sh"

USAGE="Usage: bash tests/run.sh [--file <name>] [--case <test>] [--jobs <n>] [--no-lint] [-v|-vv]

  --file <name>   only tests/core/<name>.test.sh (or a path to a test file)
  --case <test>   only the tests whose name contains <test>
  --jobs <n>      tests run in parallel, <n> at a time (default: the CPU count)
  --no-lint       skip shellcheck (always skipped when filtering)
  -v, -vv         a dot per test, or each test's name"
GNU_ONLY_COMMANDS=(realpath)
BASH4_ONLY_BUILTINS=(mapfile readarray)
LINT_EXCLUSIONS="SC1090,SC1091,SC2034,SC2154"

if [ "${1-}" != --run ]; then
  GREEN=""
  RED=""
  DIM=""
  RESET=""
  if [ -t 1 ] && [ -z "${NO_COLOR-}" ]; then
    GREEN=$'\033[32m'
    RED=$'\033[31m'
    DIM=$'\033[2m'
    RESET=$'\033[0m'
  fi
fi

cpu_count() {
  getconf _NPROCESSORS_ONLN 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || printf '2\n'
}

restrict_environment() {
  local command
  for command in "${GNU_ONLY_COMMANDS[@]}"; do
    printf '#!/bin/sh\necho "%s is not portable" >&2\nexit 127\n' "$command" > "$WORK_DIR/$command"
    chmod +x "$WORK_DIR/$command"
  done
  printf 'enable -n %s\n' "${BASH4_ONLY_BUILTINS[*]}" > "$WORK_DIR/bashenv"
  export PATH="$WORK_DIR:$PATH"
  export BASH_ENV="$WORK_DIR/bashenv"
  export NO_COLOR=1
  export LC_ALL=C
}

# Shellchecks the scripts whose content changed since they last passed (cksum
# per file, cached outside the repo), so an unchanged tree lints in no time.
lint() {
  local cache="${XDG_CACHE_HOME:-$HOME/.cache}/dotdot-tests/lint" sums="$WORK_DIR/sums" changed="$WORK_DIR/changed"
  command -v shellcheck >/dev/null || { echo "⚠️  shellcheck not installed; lint skipped." > "$WORK_DIR/lint"; return 0; }
  mkdir -p "$(dirname -- "$cache")" && touch "$cache"
  find "$SOURCE_DIR" "$REPOSITORY_DIR/plugins" "$REPOSITORY_DIR/install.sh" "$TESTS_DIR" -type f \( -name '*.sh' -o -path '*/bin/dot' \) -print0 \
    | xargs -0 cksum > "$sums"
  grep -vxF -f "$cache" "$sums" | cut -d' ' -f3- > "$changed"
  [ -s "$changed" ] || return 0
  tr '\n' '\0' < "$changed" | xargs -0 -n 8 -P "$JOBS" shellcheck -x -s bash -S warning -e "$LINT_EXCLUSIONS" > "$WORK_DIR/lint" 2>&1 || return 1
  cp "$sums" "$cache"
}

# Runs one test in its own sandbox; its result lands in $WORK_DIR/results/.
run_one() {
  local file="$1" name="$2" result
  result="$WORK_DIR/results/${file##*/}.$name"
  export ASSERTIONS_FILE="$result.assertions"
  if (
    . "$file"
    sandbox::create
    trap sandbox::destroy EXIT
    "$name"
  ) 2>"$result.failure" >/dev/null; then
    : > "$result.passed"
  else
    : > "$result.failed"
  fi
  case "$VERBOSITY" in
    1) [ -e "$result.passed" ] && printf '%s.%s' "$GREEN" "$RESET" || printf '%s.%s' "$RED" "$RESET" ;;
    2) [ -e "$result.passed" ] && printf '  %s✓%s %s %s(%s)%s\n' "$GREEN" "$RESET" "$name" "$DIM" "${file##*/}" "$RESET" \
      || printf '  %sx%s %s %s(%s)%s\n' "$RED" "$RESET" "$name" "$DIM" "${file##*/}" "$RESET" ;;
  esac
}

test_files() {
  local file
  if [ -z "$FILE" ]; then
    find "$TESTS_DIR" -name '*.test.sh' | sort
    return
  fi
  for file in "$FILE" "$TESTS_DIR/core/$FILE.test.sh" "$TESTS_DIR/core/$FILE"; do
    [ -f "$file" ] || continue
    (cd -- "$(dirname -- "$file")" && printf '%s/%s\n' "$PWD" "${file##*/}")
    return
  done
  echo "No test file $FILE." >&2
  exit 2
}

# Every selected test as "<file> <name>".
selected_tests() {
  local file
  while IFS= read -r file; do
    grep -oE '^test_[a-z0-9_]+' "$file" | grep -F -- "$CASE" | sed "s|^|$file |"
  done < <(test_files)
}

report() {
  local result passed=0 failed=0 assertions=0 name
  [ "$VERBOSITY" -ne 1 ] || printf '\n'
  for result in "$WORK_DIR"/results/*.passed; do
    [ -e "$result" ] && passed=$((passed + 1))
  done
  for result in "$WORK_DIR"/results/*.failed; do
    [ -e "$result" ] || continue
    failed=$((failed + 1))
    name="${result%.failed}"
    name="${name##*/}"
    printf '\n❌ %s (%s)\n' "${name#*.test.sh.}" "${name%%.test.sh.*}.test.sh"
    sed 's/^/   /' "${result%.failed}.failure"
  done
  assertions=$(cat "$WORK_DIR"/results/*.assertions 2>/dev/null | wc -c | tr -d ' ')
  printf '\n%s passed, %s failed, %s assertions\n' "$GREEN$passed$RESET" "$( [ "$failed" -eq 0 ] && printf '0' || printf '%s' "$RED$failed$RESET")" "$assertions"
  [ "$failed" -eq 0 ]
}

# A worker started by xargs below: runs one test with the settings exported.
if [ "${1-}" = --run ]; then
  run_one "$2" "$3"
  exit 0
fi

FILE=""
CASE=""
JOBS=$(cpu_count)
VERBOSITY=0
LINT=true
while [ $# -gt 0 ]; do
  case "$1" in
    --file) [ $# -ge 2 ] || { echo "$USAGE" >&2; exit 2; }; FILE="$2"; LINT=false; shift ;;
    --case) [ $# -ge 2 ] || { echo "$USAGE" >&2; exit 2; }; CASE="$2"; LINT=false; shift ;;
    --jobs) [[ "${2-}" =~ ^[1-9][0-9]*$ ]] || { echo "$USAGE" >&2; exit 2; }; JOBS="$2"; shift ;;
    --no-lint) LINT=false ;;
    -v) VERBOSITY=1 ;;
    -vv) VERBOSITY=2 ;;
    -h | --help) echo "$USAGE"; exit 0 ;;
    *) echo "$USAGE" >&2; exit 2 ;;
  esac
  shift
done

WORK_DIR=$(mktemp -d)
trap 'rm -rf -- "$WORK_DIR"' EXIT
mkdir -p "$WORK_DIR/results"
export WORK_DIR VERBOSITY GREEN RED DIM RESET
restrict_environment

lint_status=0
lint_pid=""
if $LINT; then
  lint &
  lint_pid=$!
fi

test_files > /dev/null || exit 2
selected=$(selected_tests)
if [ -z "$selected" ]; then
  echo "No tests match." >&2
  exit 2
fi
printf '%s\n' "$selected" | xargs -n 2 -P "$JOBS" bash "$0" --run
tests_status=0
report || tests_status=1

if [ -n "$lint_pid" ]; then
  wait "$lint_pid" || lint_status=1
  if [ "$lint_status" -ne 0 ]; then
    cat "$WORK_DIR/lint"
    echo "❌ shellcheck found problems."
  fi
fi
[ "$tests_status" -eq 0 ] && [ "$lint_status" -eq 0 ]
