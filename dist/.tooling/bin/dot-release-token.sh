#!/usr/bin/env bash
# description: Store, encrypted, the personal access token a release remote pushes with.

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

usage() {
  cat <<EOF
bash dot release:token — store the personal access token that bash dot
release pushes to a remote with, or remove it.

Give the token write access to the release repo and nothing else. It is
asked for without echo, never taken as an argument, and stored encrypted for
that remote's exact url: in the macOS keychain, in the desktop keyring
(libsecret), or, where neither exists, in $(dotdot_rel "$ENV_FILE") as
RELEASE_PAT_<NAME>, encrypted by gpg together with the url, with a
passphrase you choose and are asked for on every push (see --cache-pat in
bash dot release:push --help). Storing again replaces the token, and storing
or removing one drops it from that cache; a changed remote url needs a new
one.

Usage:
  bash dot release:token <remote>
  bash dot release:token <remote> --remove
  bash dot release:token --help

Arguments:
  <remote>    Remote name, from RELEASE_REMOTE_<NAME> (lowercased) in
              $(dotdot_rel "$RELEASE_CONF").

Optional:
  --remove    Remove the stored token instead.

Examples:
  bash dot release:token github
  bash dot release:token github --remove
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

NAME=""
REMOVE=false
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    --remove)
      REMOVE=true
      shift
      ;;
    -*)
      die "unexpected option: $1"
      ;;
    *)
      [ -z "$NAME" ] || die "unexpected argument: $1"
      NAME=$1
      shift
      ;;
  esac
done
[ -n "$NAME" ] || die "a remote name is required"

cd "$BASE"
[ -f "$RELEASE_CONF" ] || fail "release config not found: $(dotdot_rel "$RELEASE_CONF")"
release_remotes
URL=$(release_remote_url "$NAME")

if $REMOVE; then
  token_remove "$URL" || fail "no token stored for $NAME"
  printf '%s✅ %sremoved the token for %s%s\n' "$GREEN$BOLD" "$RESET$GREEN" "$NAME" "$RESET"
  exit 0
fi

[ -t 0 ] || fail "the token is asked for at a terminal; run this one yourself"
read -r -s -p "Token for $NAME ($URL): " TOKEN
echo
[ -n "$TOKEN" ] || fail "no token given; nothing stored"
token_save "$URL" "$TOKEN" || fail "could not store the token for $NAME"
unset TOKEN
printf '%s✅ %stoken for %s stored in the %s store%s\n' "$GREEN$BOLD" "$RESET$GREEN" "$NAME" "$(token_store)" "$RESET"
