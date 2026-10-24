#!/usr/bin/env bash
# install.sh — install dotdot into the current folder.
#
# Downloads dotdot from the repo's main branch, places its dist/ here as
# .dot/, links dotdot's entry point as ./dot, and runs dot sync -y. Nothing
# that already exists is overwritten: an existing .dot/ or dot stops the
# install untouched. Plugins are never installed here: add the ones you trust
# afterwards with bash dot plugins:add <owner>/<name>.
# Output stays quiet: progress lines, then the result; a failing step shows
# its output.

set -euo pipefail

REPO="dotdot-sh/dotdot"
BRANCH="main"
ARCHIVE_URL="https://github.com/$REPO/archive/refs/heads/$BRANCH.tar.gz"
SOURCE_DIR="dist"
DOTDOT_DIR=".dot"
ENTRY_LINK="dot"
ENTRY_POINT="$DOTDOT_DIR/.core/system/bin/dot"
BOOT_FILE=".core/system/boot.sh"
VERSION_FILE="$DOTDOT_DIR/.core/version"
ENV_FILE="$DOTDOT_DIR/.env"
ENV_EXAMPLE="$DOTDOT_DIR/.core/.env.example"
RELEASE_SETTINGS_STUB="$DOTDOT_DIR/.core/modules/release/stubs/env.stub"
TEMP_PREFIX=".dot-install."
REQUIRED_COMMANDS=(curl tar gzip mktemp ln mv)
# dotdot's spinner: one frame every SPINNER_INTERVAL seconds.
SPINNER_FRAMES=(' ·●' ' •⏺' ' ⏺•' ' ●·' ' ⏺•' ' •⏺' ' ·●')
SPINNER_INTERVAL=0.07

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
  source=$(find_source "$temp/tree") || fail "The download holds no dotdot ($SOURCE_DIR/$BOOT_FILE is missing)."

  printf 'Getting %s ready for your project...\n' "$name"
  check_destination
  mv -- "$source/$SOURCE_DIR" "$base/$DOTDOT_DIR" || fail "Could not place dotdot at $base/$DOTDOT_DIR."
  record_version "$temp/dotdot.tar.gz"
  seed_settings
  ln -s -- "$ENTRY_POINT" "$base/$ENTRY_LINK" || fail "Could not link $base/$ENTRY_LINK."
  quietly "Sync" bash "$base/$ENTRY_LINK" sync -y
  quietly "Checking bash $ENTRY_LINK" bash "$base/$ENTRY_LINK"

  printf '\n%s✓ %s is ready!%s\n\n' "$GREEN" "$name$GREEN" "$RESET"
  printf "To finish, just tell your coding agent you're using %s; it will take it from there.\n" "$name"
  printf "Or manually fill in your project's context in %s%s/%s.\n" "$BOLD" "$DOTDOT_DIR" "$RESET"
  printf '\nUsing Claude Code? Add its harness: %sbash %s plugins:add dotdot-sh/claude-code%s\n' "$BOLD" "$ENTRY_LINK" "$RESET"
  printf 'Tip: run %sbash %s%s to see the available commands.\n' "$BOLD" "$ENTRY_LINK" "$RESET"
  printf '\n%s🚀 Build something amazing!%s\n\n' "$BOLD" "$RESET"
}

fail() {
  printf '%s❌ %s%s\n\n' "$RED" "$*" "$RESET" >&2
  exit 1
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
  local label="$1" pid tick=0
  shift
  "$@" >"$log" 2>&1 &
  pid=$!
  if [ -t 1 ]; then
    while kill -0 "$pid" 2>/dev/null; do
      printf '\r%s%s ' "$label" "${SPINNER_FRAMES[$((tick % ${#SPINNER_FRAMES[@]}))]}"
      tick=$((tick + 1))
      sleep "$SPINNER_INTERVAL"
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

# Prints the unpacked archive's single top-level folder, named after the repo
# and branch, which holds dotdot's source.
find_source() {
  local top
  for top in "$1"/*/; do
    if [ -f "$top$SOURCE_DIR/$BOOT_FILE" ]; then
      printf '%s\n' "${top%/}"
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

# Starts dotdot's git-ignored .env, readable only by the user, from dotdot's
# defaults, then the release settings, empty, to fill in when they release.
seed_settings() {
  local file
  for file in "$ENV_EXAMPLE" "$RELEASE_SETTINGS_STUB"; do
    [ -f "$base/$file" ] || continue
    (umask 077 && { cat -- "$base/$file"; printf '\n'; } >> "$base/$ENV_FILE" && chmod 600 "$base/$ENV_FILE") \
      || printf '%s⚠️  Could not create %s.%s\n' "$YELLOW" "$ENV_FILE" "$RESET"
  done
}

# Called last, so a download cut short runs nothing at all.
main "$@"
