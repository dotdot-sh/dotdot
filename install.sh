#!/usr/bin/env bash
# install.sh — install dotdot into the current folder.
#
# Downloads dotdot from the repo's main branch, places its dist/ here as
# .dot/, seeds the project root from dotdot's conf/stubs/ (never over an
# existing file; ".env.stub" is appended to dotdot's .dot/.env), links dotdot's entry point
# as ./dot and runs dot sync -y. Nothing that already exists is
# overwritten: an existing .dot/ or dotdot stops the install untouched.
#
# It asks one question, on the terminal even when piped from curl: whether to
# keep the release features. No (the default, and the answer without a
# terminal) removes the release commands and seeds none of their stubs.
# Output stays quiet: two progress lines, then the result; a failing step
# shows its output.

set -euo pipefail

REPO="dotdot-sh/dotdot"
BRANCH="main"
ARCHIVE_URL="https://github.com/$REPO/archive/refs/heads/$BRANCH.tar.gz"
SOURCE_DIR="dist"
DOTDOT_DIR=".dot"
ENTRY_LINK="dot"
ENTRY_POINT="$DOTDOT_DIR/.tooling/bin/dot"
PATHS_LIB=".tooling/bin/lib/dot-paths.sh"
STUBS_DIR="$DOTDOT_DIR/.tooling/conf/stubs"
VERSION_FILE="$DOTDOT_DIR/.tooling/conf/version"
ENV_STUB_NAME=".env"
ENV_FILE="$DOTDOT_DIR/.env"
RELEASE_FILES=(
  .tooling/bin/dot-release.sh
  .tooling/bin/dot-release-push.sh
  .tooling/bin/dot-release-token.sh
  .tooling/bin/lib/dot-release.sh
)
RELEASE_STUBS=(release.conf.stub release.exclude.stub .env.stub)
TEMP_PREFIX=".dot-install."
REQUIRED_COMMANDS=(curl tar gzip mktemp ln mv)
SPINNER_FRAMES='|/-\'
SPINNER_DELAY=0.1

main() {
  local GREEN="" RED="" YELLOW="" BOLD="" RESET=""
  if [ -t 1 ]; then
    GREEN=$'\033[32m' RED=$'\033[31m' YELLOW=$'\033[33m' BOLD=$'\033[1m' RESET=$'\033[0m'
  fi
  local name="${BOLD}dotdot${RESET}"
  base="$PWD"
  check_requirements
  check_destination

  temp=$(mktemp -d "$base/$TEMP_PREFIX"XXXXXX) || fail "Could not create a temp folder in $base."
  trap 'rm -rf -- "$temp"' EXIT
  trap 'exit 130' INT TERM HUP
  log="$temp/log"
  spin "Downloading $name..." download_and_unpack
  local source
  source=$(find_source "$temp/tree") || fail "The download holds no dotdot ($SOURCE_DIR/$PATHS_LIB is missing)."

  printf 'Getting %s ready for your project...\n' "$name"
  local release=false
  ask "Do you want the release features?" && release=true
  check_destination
  mv -- "$source" "$base/$DOTDOT_DIR" || fail "Could not place dotdot at $base/$DOTDOT_DIR."
  record_version "$temp/dotdot.tar.gz"
  $release || drop_release
  seed_stubs
  ln -s -- "$ENTRY_POINT" "$base/$ENTRY_LINK" || fail "Could not link $base/$ENTRY_LINK."
  quietly "Sync" bash "$base/$ENTRY_LINK" sync -y
  quietly "Checking bash $ENTRY_LINK" bash "$base/$ENTRY_LINK"

  printf '\n%s✓ %s is ready!%s\n\n' "$GREEN" "$name$GREEN" "$RESET"
  printf "To finish, just tell your coding agent you're using %s; it will take it from there.\n" "$name"
  printf "Or manually fill in your project's context in %s%s/%s.\n" "$BOLD" "$DOTDOT_DIR" "$RESET"
  printf '\nTip: run %sbash %s%s to see the available commands.\n' "$BOLD" "$ENTRY_LINK" "$RESET"
  printf '\n%s🚀 Build something amazing!%s\n\n' "$BOLD" "$RESET"
}

fail() {
  printf '%s❌ %s%s\n\n' "$RED" "$*" "$RESET" >&2
  exit 1
}

# Asks question $1 on the terminal, even when this script came through a
# pipe, and succeeds on y or yes. No terminal, or Enter, means no.
ask() {
  local reply=""
  { : </dev/tty; } 2>/dev/null || return 1
  read -r -p "$1 [y/N] " reply </dev/tty || return 1
  [[ $reply =~ ^[Yy]([Ee][Ss])?$ ]]
}

# Runs "$@" with its output kept in $log, shown only if it fails as step $1.
quietly() {
  local label="$1"
  shift
  if ! "$@" >"$log" 2>&1; then
    printf '%s❌ %s failed:%s\n' "$RED" "$label" "$RESET" >&2
    sed 's/^/   /' "$log" >&2
    fail "Fix the errors above, then run bash $ENTRY_LINK sync."
  fi
}

# Removes the release commands and their stubs, so nothing of them is seeded.
drop_release() {
  local file
  for file in "${RELEASE_FILES[@]}"; do
    rm -f -- "$base/$DOTDOT_DIR/$file"
  done
  for file in "${RELEASE_STUBS[@]}"; do
    rm -f -- "$base/$STUBS_DIR/$file"
  done
}

check_requirements() {
  local command missing=()
  for command in "${REQUIRED_COMMANDS[@]}"; do
    command -v "$command" >/dev/null || missing+=("$command")
  done
  [ ${#missing[@]} -eq 0 ] || fail "Missing required commands: ${missing[*]}"
}

check_destination() {
  local name
  if [ "$base" = "/" ] || [ "$base" = "${HOME-}" ]; then
    fail "Run this from your project's folder, not $base."
  fi
  [ -w "$base" ] || fail "$base is not writable."
  for name in "$DOTDOT_DIR" "$ENTRY_LINK"; do
    if [ -e "$base/$name" ] || [ -L "$base/$name" ]; then
      fail "$base/$name already exists, so nothing was installed."
    fi
  done
}

download_and_unpack() {
  mkdir -p -- "$temp/tree"
  curl --proto '=https' --tlsv1.2 -fsSL -o "$temp/dotdot.tar.gz" "$ARCHIVE_URL"
  tar -xzf "$temp/dotdot.tar.gz" -C "$temp/tree"
}

# Prints label $1, with a spinner after it on a terminal while "$@" runs in
# the background; its output is kept in $log and shown only if it fails.
spin() {
  local label="$1" pid frame=0
  shift
  "$@" >"$log" 2>&1 &
  pid=$!
  if [ -t 1 ]; then
    while kill -0 "$pid" 2>/dev/null; do
      printf '\r%s %s' "$label" "${SPINNER_FRAMES:frame++%${#SPINNER_FRAMES}:1}"
      sleep "$SPINNER_DELAY"
    done
    printf '\r\033[K'
  fi
  printf '%s\n' "$label"
  if ! wait "$pid"; then
    printf '%s❌ Download failed:%s\n' "$RED" "$RESET" >&2
    sed 's/^/   /' "$log" >&2
    fail "Nothing was installed."
  fi
}

# Prints dotdot's source folder inside the unpacked archive, whose single
# top-level folder is named after the repo and branch.
find_source() {
  local top
  for top in "$1"/*/; do
    if [ -f "$top$SOURCE_DIR/$PATHS_LIB" ]; then
      printf '%s\n' "${top%/}/$SOURCE_DIR"
      return
    fi
  done
  return 1
}

# GitHub archives carry their commit in a pax header; dot update diffs
# against it to know what it may remove. Without it, the first update just
# removes nothing.
record_version() {
  local commit
  commit=$(gzip -dc -- "$1" 2>/dev/null | head -c 1024 | tr -d '\000' | grep -ao 'comment=[0-9a-f]\{40\}' | cut -d= -f2 || true)
  if [ -n "$commit" ]; then
    printf '%s\n' "$commit" > "$base/$VERSION_FILE"
  else
    printf '%s⚠️  Could not read the commit; the first dot update will not remove staled files.%s\n' "$YELLOW" "$RESET"
  fi
}

# "<name>.stub" becomes "<name>" in the project root, skipped when that file
# already exists; ".env.stub" is appended to dotdot's .env instead.
seed_stubs() {
  local stub name target
  [ -d "$base/$STUBS_DIR" ] || return 0
  for stub in "$base/$STUBS_DIR"/*.stub "$base/$STUBS_DIR"/.*.stub; do
    [ -f "$stub" ] || continue
    name=$(basename -- "$stub" .stub)
    target="$base/$name"
    if [ "$name" = "$ENV_STUB_NAME" ]; then
      target="$base/$ENV_FILE"
      if [ -s "$target" ] && [ -n "$(tail -c 1 -- "$target")" ]; then
        printf '\n' >> "$target"
      fi
      cat -- "$stub" >> "$target" \
        || printf '%s❌ Could not add %s to %s%s\n' "$RED" "$(basename -- "$stub")" "$target" "$RESET"
    elif [ -e "$target" ] || [ -L "$target" ]; then
      printf '%s⚠️  Kept the existing %s; compare it with %s%s\n' "$YELLOW" "$target" "$stub" "$RESET"
    else
      cp -- "$stub" "$target" || printf '%s❌ Could not create %s%s\n' "$RED" "$target" "$RESET"
    fi
  done
}

# Called last, so a download cut short runs nothing at all.
main "$@"
