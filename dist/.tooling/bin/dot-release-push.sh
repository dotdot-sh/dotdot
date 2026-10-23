#!/usr/bin/env bash
# description: Push the release repo to its remotes, each with its own stored access token.

set -euo pipefail

. "$(dirname "$0")/lib/dot-paths.sh"
. "$(dirname "$0")/lib/dot-kv.sh"

if [ -t 1 ]; then
  BOLD=$(printf '\033[1m'); RED=$(printf '\033[31m'); GREEN=$(printf '\033[32m')
  RESET=$(printf '\033[0m')
else
  BOLD=""; RED=""; GREEN=""; RESET=""
fi

. "$(dirname "$0")/lib/dot-release.sh"
. "$(dirname "$0")/lib/dot-confirm.sh"

usage() {
  cat <<EOF
bash dot release:push — push the release repo's branch and all its tags to the
configured remotes. bash dot release ends with it; run it alone to retry or
finish a push.

Each remote is pushed over https with the personal access token stored for
it (bash dot release:token <remote>); no other credential is used. It asks,
remote by remote, whether to push (default no); without a terminal it pushes
only where a flag says so.

Usage:
  bash dot release:push [--<remote>...] [--push-all] [--cache-pat=N] [--force]
  bash dot release:push --help

Optional:
  --<remote>  Push to that remote without asking, e.g. --github. Repeatable.
              Remote names come from RELEASE_REMOTE_<NAME> (lowercased).
  --push-all  Push to every configured remote without asking.
  --force     Force push, overwriting the remotes' branch and tags. Asks
              first ([y/N]: only y or yes goes ahead), and only at a terminal.
  --cache-pat=N
              Keep the decrypted tokens in memory for N minutes from now, so
              pushes until then ask no passphrase; given again, the N minutes
              restart. 0 forgets them. By default nothing is kept.

Config, read from $(dotdot_rel "$RELEASE_CONF"):
  RELEASE_DESTINATION      release repo directory, from the project root
  RELEASE_BRANCH           branch in the release repo
  RELEASE_REMOTE_<NAME>    https:// url of remote <name> (lowercased); at least one

Examples:
  bash dot release:push
  bash dot release:push --github
  bash dot release:push --github --cache-pat=15
EOF
}

die() {
  printf '%s❌ %s%s\n\n' "$RED$BOLD" "$1" "$RESET" >&2
  usage >&2
  exit 1
}

fail() {
  printf '%s❌ %s%s\n' "$RED$BOLD" "$1" "$RESET" >&2
  exit 1
}

PUSH_ALL=false
FORCE=false
PUSH_TO=()
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    --push-all)
      PUSH_ALL=true
      shift
      ;;
    --force)
      FORCE=true
      shift
      ;;
    --cache-pat=*)
      TOKEN_CACHE_MINUTES=${1#*=}
      [[ $TOKEN_CACHE_MINUTES =~ $CACHE_MINUTES_PATTERN ]] || die "--cache-pat takes whole minutes, e.g. --cache-pat=15"
      shift
      ;;
    --*)
      [[ ${1#--} =~ $REMOTE_NAME_PATTERN ]] || die "unexpected option: $1"
      PUSH_TO+=("${1#--}")
      shift
      ;;
    *)
      die "unexpected argument: $1"
      ;;
  esac
done
! $FORCE || confirm_or_exit "Force push, overwriting the remotes' history?" n "bash dot release:push --force"

cd "$BASE"
[ -f "$RELEASE_CONF" ] || fail "release config not found: $(dotdot_rel "$RELEASE_CONF")"
DEST=$(setting RELEASE_DESTINATION)
BRANCH=$(setting RELEASE_BRANCH)
release_remotes
for name in "${PUSH_TO[@]}"; do
  release_remote_url "$name" >/dev/null
done

[ -d "$DEST/.git" ] || fail "no release repo at $DEST; run bash dot release <version> first"
rel() { git -C "$DEST" "$@"; }
[ "$(rel symbolic-ref --short HEAD)" = "$BRANCH" ] || fail "release repo is not on branch $BRANCH"
rel rev-parse -q --verify HEAD >/dev/null || fail "release repo has no release commit yet"
TAG=$(rel describe --tags --exact-match HEAD 2>/dev/null || rel rev-parse --short HEAD)

release_push
