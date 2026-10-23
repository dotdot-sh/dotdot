#!/usr/bin/env bash
# description: Update dotdot's core (.tooling/) to the latest public dotdot; context files are untouched.

set -euo pipefail

. "$(dirname "$0")/lib/dot-paths.sh"
. "$(dirname "$0")/lib/dot-confirm.sh"

usage() {
  cat <<EOF
bash dot update — update dotdot's core ($DOTDOT_NAME/.tooling/) to the latest
dotdot, downloaded from $DOTDOT_REPO_URL ($DOTDOT_REPO_REF),
then optionally run bash dot sync.

Only $DOTDOT_NAME/.tooling/ changes, kits aside: $(dotdot_rel "$KITS_DIR")/,
$(dotdot_rel "$KITS_LOCK"), and $(dotdot_rel "$KITS_MAP") are left to bash dot kit:update.
Every context file outside it (AGENTS.md, RULES.md, PRODUCT.md, Features/,
Decisions/, Notes/, USER.md, …) is never read or written.

.tooling/conf/version holds the commit dotdot was last installed or updated from.
The update fetches that commit and the latest one with git (only those two,
into a temporary repo nothing of yours touches), shows both, asks, and:
  - copies every .tooling/ file of the latest commit over dotdot's
  - removes a file only when it existed at the recorded commit and no longer
    exists at the latest (a move counts as removed here, added there). A
    removed file that was edited locally is kept and reported, never deleted
  - leaves every other file alone: your own skills, agents, and scripts
  - records the latest commit in .tooling/conf/version, only once everything
    else succeeded

Without a .tooling/conf/version, or with a recorded commit the public repo
doesn't have, nothing is removed: files the latest commit lacks are listed for
you to review instead.

-y / --yes answers yes to the update's own question; sync is still asked,
since it changes files outside .tooling/.

Every run needs a terminal (piped input is refused), --yes included, so only a
person can start an update.

Usage:
  bash dot update
  bash dot update -y
  bash dot update --help
EOF
}

YES=false
case "${1-}" in
  -h | --help) usage; exit 0 ;;
  -y | --yes) YES=true ;;
  "") ;;
  *) echo "❌ Unknown argument: $1" >&2; usage >&2; exit 1 ;;
esac
[ $# -le 1 ] || { echo "❌ Unknown argument: $2" >&2; usage >&2; exit 1; }

if [ -t 1 ]; then
  BOLD=$'\033[1m'; RED=$'\033[31m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'; RESET=$'\033[0m'
else
  BOLD=""; RED=""; GREEN=""; YELLOW=""; RESET=""
fi
NAME="${BOLD}dotdot${RESET}"
SPINNER_FRAMES='|/-\'
SPINNER_DELAY=0.1

die() {
  printf '%s❌ %s%s\n' "$RED" "$*" "$RESET" >&2
  exit 1
}

# The download's git: a temporary repo of its own, with nothing in any config
# able to run a program.
cgit() {
  git -c core.fsmonitor=false -c core.hooksPath=/dev/null -c protocol.allow=never -c protocol.https.allow=always \
    -C "$TOP" "$@"
}

# Fetches the latest commit and, when recorded, the installed one into $TOP,
# as refs/dotdot/new and refs/dotdot/old. Only the latest is required.
download() {
  git init -q -- "$TOP"
  GIT_TERMINAL_PROMPT=0 cgit fetch -q --depth 1 --no-tags "$DOTDOT_REPO_URL" "+refs/heads/$DOTDOT_REPO_REF:refs/dotdot/new"
  [ -z "$1" ] || GIT_TERMINAL_PROMPT=0 cgit fetch -q --depth 1 --no-tags "$DOTDOT_REPO_URL" "+$1:refs/dotdot/old" || true
}

# Prints label $1, with a spinner after it on a terminal while "$@" runs in
# the background; its output is kept in $LOG and shown only if it fails.
spin() {
  local label="$1" pid frame=0
  shift
  "$@" >"$LOG" 2>&1 &
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
    sed 's/^/   /' "$LOG" >&2
    die "Nothing changed."
  fi
}

# The installer rewrites ".dot/" to a renamed dotdot's own name in every text
# file it copies; the same rewrite keeps an update's files comparable to them.
renamed() {
  if [ "$DOTDOT_NAME" = ".dot" ]; then
    cat
  else
    sed "s|\.dot/|$(printf '%s' "$DOTDOT_NAME/" | sed 's/[|&\\]/\\&/g')|g"
  fi
}

# True when the .tooling/-relative path $1 belongs to kits, which only
# the kit:* commands manage.
kit_owned() {
  case "$TOOLING_DIR/$1" in
    "$KITS_DIR"/* | "$KITS_LOCK" | "$KITS_MAP") return 0 ;;
  esac
  return 1
}

# Removes $1's parent directories while they are empty, up to .tooling.
prune_parents() {
  local dir
  dir=$(dirname -- "$1")
  while [ "$dir" != "$TOOLING_DIR" ] && rmdir -- "$dir" 2>/dev/null; do
    dir=$(dirname -- "$dir")
  done
}

main() {
  [ -t 0 ] || die "Aborted — nothing changed. Confirmation needs a terminal; run bash dot update yourself."
  command -v git >/dev/null || die "git is required."

  local old=""
  if [ -f "$VERSION_FILE" ]; then
    old=$(tr -d '[:space:]' < "$VERSION_FILE")
    [[ "$old" =~ ^[0-9a-f]{40}([0-9a-f]{24})?$ ]] || die "$(dotdot_rel "$VERSION_FILE") does not hold a commit hash."
  fi

  # Global: the EXIT trap runs after main has returned.
  TMP=$(mktemp -d) || die "Could not create a temp directory."
  trap 'rm -rf -- "$TMP"' EXIT INT TERM HUP
  TOP="$TMP/repo"
  LOG="$TMP/log"
  spin "Downloading $NAME..." download "$old"
  local new prefix="$DOTDOT_REPO_SOURCE/$TOOLING_NAME"
  new=$(cgit rev-parse --verify refs/dotdot/new^{commit}) || die "The download holds no commit."
  if [ -n "$old" ] && ! cgit rev-parse -q --verify "refs/dotdot/old^{commit}" >/dev/null; then
    printf "%s⚠️  The installed version %s isn't in the public repo: nothing will be removed; files the latest lacks are listed instead.%s\n" \
      "$YELLOW" "${old:0:7}" "$RESET"
    old=""
  elif [ -z "$old" ]; then
    printf '%s⚠️  No %s: nothing will be removed; files the latest lacks are listed instead.%s\n' \
      "$YELLOW" "$(dotdot_rel "$VERSION_FILE")" "$RESET"
  fi
  if [ "$old" = "$new" ]; then
    printf '%s✓ %s is up to date%s (%s).\n' "$GREEN" "$NAME$GREEN" "$RESET" "${new:0:7}"
    exit 0
  fi

  echo "Latest: $(cgit log -1 --format='%h %s' "$new")"
  [ -z "$old" ] || echo "Yours:  $(cgit log -1 --format='%h %s' "$old")"
  if $YES; then
    echo "Update $(dotdot_rel "$TOOLING_DIR")/? yes (--yes)"
  else
    confirm_or_exit "Update $(dotdot_rel "$TOOLING_DIR")/?" n "bash dot update"
  fi
  printf 'Updating %s...\n' "$NAME"

  # From the commit itself, so the recorded version always names exactly the
  # files that were copied.
  mkdir -p -- "$TMP/tree"
  cgit archive --format=tar "$new" -- ":(literal)$prefix" | tar -x -C "$TMP/tree" \
    || die "Could not read $prefix/ at ${new:0:7}."
  local tree="$TMP/tree/$prefix"
  [ -d "$tree" ] || die "Commit ${new:0:7} has no $prefix/."
  if [ "$DOTDOT_NAME" != ".dot" ]; then
    grep -rlZ --binary-files=without-match -F '.dot/' "$tree" \
      | while IFS= read -r -d '' f; do renamed < "$f" > "$f.tmp" && cat "$f.tmp" > "$f" && rm -f "$f.tmp"; done
  fi

  local rel added=() updated=() removed=() edited=() unknown=() same=0
  while IFS= read -r -d '' rel; do
    rel=${rel#./}
    if [ ! -e "$TOOLING_DIR/$rel" ] && [ ! -L "$TOOLING_DIR/$rel" ]; then
      added+=("$rel")
    elif [ -L "$tree/$rel" ] || [ -L "$TOOLING_DIR/$rel" ] || ! cmp -s -- "$tree/$rel" "$TOOLING_DIR/$rel"; then
      updated+=("$rel")
    else
      same=$((same + 1))
    fi
  done < <(cd -- "$tree" && find . \( -type f -o -type l \) -print0 | sort -z)

  local path dest
  if [ -n "$old" ]; then
    # Present at the recorded commit, absent at HEAD. --no-renames makes a move
    # a plain delete plus add, so no similarity guess decides what goes.
    while IFS= read -r -d '' path; do
      rel=${path#"$prefix"/}
      [ "$rel" != "$path" ] || continue
      [ "$rel" != conf/version ] || continue
      dest=$(resolve_within "$rel" "$TOOLING_DIR") || continue
      [ -e "$dest" ] || [ -L "$dest" ] || continue
      if [ ! -L "$dest" ] && cgit show "$old:$path" | renamed | cmp -s - "$dest"; then
        removed+=("$rel")
      else
        edited+=("$rel")
      fi
    done < <(cgit diff -z --no-renames --diff-filter=D --name-only "$old" "$new" -- ":(literal)$prefix")
  else
    while IFS= read -r -d '' rel; do
      rel=${rel#./}
      [ "$rel" != conf/version ] || continue
      kit_owned "$rel" && continue
      [ -e "$tree/$rel" ] || [ -L "$tree/$rel" ] || unknown+=("$rel")
    done < <(cd -- "$TOOLING_DIR" && find . \( -type f -o -type l \) -print0 | sort -z)
  fi

  # Each file goes through a temp copy and a rename, so a running script —
  # this one included — keeps reading its old copy instead of a half-written one.
  local part failed=0
  for rel in "${added[@]+"${added[@]}"}" "${updated[@]+"${updated[@]}"}"; do
    dest="$TOOLING_DIR/$rel"
    part="$dest.dot-update-$$"
    if mkdir -p -- "$(dirname -- "$dest")" && cp -P -p -- "$tree/$rel" "$part" && mv -f -T -- "$part" "$dest"; then
      :
    else
      rm -f -- "$part"
      printf '%sFAILED:%s could not copy %s\n' "$RED" "$RESET" "$rel" >&2
      failed=$((failed + 1))
    fi
  done
  for rel in "${removed[@]+"${removed[@]}"}"; do
    if rm -f -- "$TOOLING_DIR/$rel"; then
      prune_parents "$TOOLING_DIR/$rel"
    else
      printf '%sFAILED:%s could not remove %s\n' "$RED" "$RESET" "$rel" >&2
      failed=$((failed + 1))
    fi
  done
  [ "$failed" -eq 0 ] || die "Update incomplete: $failed failure(s) above; version not recorded. Fix them and rerun bash dot update."

  mkdir -p -- "$CONF_DIR" \
    && printf '%s\n' "$new" > "$VERSION_FILE.dot-update-$$" && mv -f -- "$VERSION_FILE.dot-update-$$" "$VERSION_FILE" \
    || die "Files updated, but $(dotdot_rel "$VERSION_FILE") could not be written."
  printf '\n%s✓ %s is updated%s to %s: %d added, %d updated, %d removed, %d unchanged.\n' \
    "$GREEN" "$NAME$GREEN" "$RESET" "${new:0:7}" "${#added[@]}" "${#updated[@]}" "${#removed[@]}" "$same"
  if [ ${#edited[@]} -gt 0 ]; then
    printf '%s⚠️  Removed upstream but edited here, so kept; delete them once reviewed:%s\n' "$YELLOW" "$RESET"
    printf '  %s\n' "${edited[@]}"
  fi
  if [ ${#unknown[@]} -gt 0 ]; then
    printf '%s⚠️  Not in dotdot at %s; kept. Delete the stale ones, keep your own:%s\n' "$YELLOW" "${new:0:7}" "$RESET"
    printf '  %s\n' "${unknown[@]}"
  fi

  # Sync, through the freshly updated script, which asks its own [y/N],
  # relinks every link into .tooling/ whose file moved and removes the broken
  # ones a renamed or removed file left.
  echo
  if confirm "Run bash dot sync now?"; then
    bash "$BIN_DIR/dot-sync.sh" || true
  else
    echo "Run bash dot sync when ready; it relinks moved dotdot links and removes broken ones."
  fi
}

# Called on the same line as exit, so bash has read all it needs before the
# update replaces this very file.
main "$@"; exit
