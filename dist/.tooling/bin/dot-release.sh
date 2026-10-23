#!/usr/bin/env bash
# description: Export the project minus an exclude list and make a signed release commit in a separate repo.

set -euo pipefail

. "$(dirname "$0")/lib/dot-paths.sh"
. "$(dirname "$0")/lib/dot-kv.sh"
. "$(dirname "$0")/lib/dot-release.sh"
. "$(dirname "$0")/lib/dot-confirm.sh"

if [ -t 1 ]; then
  BOLD=$(printf '\033[1m'); RED=$(printf '\033[31m'); GREEN=$(printf '\033[32m')
  CYAN=$(printf '\033[36m'); RESET=$(printf '\033[0m')
else
  BOLD=""; RED=""; GREEN=""; CYAN=""; RESET=""
fi

usage() {
  cat <<EOF
bash dot release — prepare one signed release commit, tagged v<version>, in
a separate release repo, so the public history holds release commits and
nothing else.

Every file tracked in HEAD is exported except the paths the exclude list
names. Git-ignored files are left out, unless the list names one with a
leading "!" (a build you made, e.g. !dist): that one is copied from disk.
The release config and the exclude list themselves are always left out.
It runs no project commands (no build, test, or install), so it works the
same for any kit: build and test in your own workflow first. It refuses on a
dirty tree, a missing or mismatched signing key, anything that looks like a
secret, or a remote a flag names that has no token stored. Then it asks,
remote by remote, whether to push (default no); without a terminal it pushes
only where a flag says so. bash dot release:push pushes the same way later.
Each remote is pushed over https with its own personal access token, stored
encrypted with bash dot release:token <remote>.

Usage:
  bash dot release <version> [--<remote>...] [--push-all] [--cache-pat=N] [--force]
  bash dot release --help

Arguments:
  <version>   Semantic version, e.g. 1.2.0 or 1.2.0-rc.1.

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
  RELEASE_EXCLUDE_FILE_LIST  exclude list, from the project root: one path per line,
                           "!path" to include a git-ignored path, # comments
  RELEASE_BRANCH           branch in the release repo
  RELEASE_REMOTE_<NAME>    https:// url of remote <name> (lowercased); at least one

Signing, read from dotdot's git-ignored $(dotdot_rel "$ENV_FILE"):
  RELEASE_SIGNING_KEY      private SSH key file name in \$HOME/.ssh/; its .pub sits next to it
  RELEASE_AUTHOR_NAME      name on the release commits
  RELEASE_AUTHOR_EMAIL     email on the release commits; must belong to the account holding
                           the signing key for GitHub to show "Verified"
  RELEASE_PAT_<NAME>       remote <name>'s token, encrypted, where there is no keychain;
                           written by bash dot release:token, never by hand

Environment variables are never read. Every setting is required; a missing or
empty one stops the release.

Examples:
  bash dot release 1.2.0
  bash dot release 1.2.0 --github
  bash dot release 1.2.0 --push-all
  bash dot release 1.2.0 --github --cache-pat=15
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

step() {
  printf '%s%s%s\n' "$CYAN" "$1" "$RESET"
}

VERSION=""
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
    -*)
      die "unexpected option: $1"
      ;;
    *)
      [ -z "$VERSION" ] || die "unexpected argument: $1"
      VERSION=$1
      shift
      ;;
  esac
done
[ -n "$VERSION" ] || die "a version is required"
[[ $VERSION =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$ ]] || die "not a semantic version: $VERSION"
TAG="v$VERSION"
! $FORCE || confirm_or_exit "Force push $TAG, overwriting the remotes' history?" n "bash dot release $VERSION --force"

cd "$BASE"
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || fail "the project is not a git repository: $BASE"

[ -f "$RELEASE_CONF" ] || fail "release config not found: $(dotdot_rel "$RELEASE_CONF")"

DEST=$(setting RELEASE_DESTINATION)
EXCLUDE_LIST=$(setting RELEASE_EXCLUDE_FILE_LIST)
BRANCH=$(setting RELEASE_BRANCH)
SIGNING_NAME=$(setting RELEASE_SIGNING_KEY "$ENV_FILE")
AUTHOR_NAME=$(setting RELEASE_AUTHOR_NAME "$ENV_FILE")
AUTHOR_EMAIL=$(setting RELEASE_AUTHOR_EMAIL "$ENV_FILE")
git check-ref-format --branch "$BRANCH" >/dev/null 2>&1 || fail "RELEASE_BRANCH is not a valid branch name: $BRANCH"
[[ $SIGNING_NAME =~ ^[A-Za-z0-9_][A-Za-z0-9._-]*$ ]] \
  || fail "RELEASE_SIGNING_KEY must be a file name in $HOME/.ssh/, not a path: $SIGNING_NAME"
[[ $SIGNING_NAME != *.pub ]] \
  || fail "RELEASE_SIGNING_KEY names the private key (e.g. ${SIGNING_NAME%.pub}), not its .pub: $SIGNING_NAME"
SIGNING_KEY="$HOME/.ssh/$SIGNING_NAME"
[[ $AUTHOR_NAME =~ ^[^[:cntrl:]\<\>]+$ ]] || fail "invalid RELEASE_AUTHOR_NAME (control characters or < >)"
[[ $AUTHOR_EMAIL =~ ^[^[:space:]\<\>@]+@[^[:space:]\<\>@]+$ ]] || fail "invalid RELEASE_AUTHOR_EMAIL (not a single address)"

release_remotes
for name in "${PUSH_TO[@]}"; do
  release_remote_url "$name" >/dev/null
done
# A remote that will be pushed without asking needs its token before anything
# is committed, so a release never lands that it cannot push.
for i in "${!REMOTES[@]}"; do
  $PUSH_ALL || [[ " ${PUSH_TO[*]} " == *" ${REMOTES[$i]} "* ]] || continue
  token_exists "${REMOTE_URLS[$i]}" \
    || fail "no token for ${REMOTES[$i]}; store one first: bash dot release:token ${REMOTES[$i]}"
done
PUBLIC_KEY="$SIGNING_KEY.pub"
[ -f "$SIGNING_KEY" ] || fail "private signing key not found: $SIGNING_KEY"
[ -f "$PUBLIC_KEY" ] || fail "public key not found (needed to verify the signature): $PUBLIC_KEY"


[ -z "$(git status --porcelain)" ] || fail "working tree is dirty; commit or stash first"
[ -f "$EXCLUDE_LIST" ] || fail "exclude list not found: $EXCLUDE_LIST"

# A plain line keeps a tracked path out; "!path" brings in a git-ignored one
# (a build) from disk, only when it holds no symlink, so nothing outside the
# project can ride along. The release's own config never ships.
excluded=("$(dotdot_rel "$RELEASE_CONF")" "$EXCLUDE_LIST")
copied=()
while IFS= read -r line || [ -n "$line" ]; do
  line=${line%%#*}
  line=$(echo "$line" | xargs)
  [ -n "$line" ] || continue
  include=false
  if [[ $line == '!'* ]]; then
    include=true
    line=${line#!}
  fi
  line=${line%/}
  resolved=$(resolve_within "$line" "$BASE") && [ "$resolved" != "$BASE" ] \
    || fail "listed path is outside the project: $line"
  if $include; then
    [ -e "$line" ] && git check-ignore -q "$line" || fail "!$line must be a git-ignored path on disk"
    case "$ENV_FILE" in "$resolved"/*|"$resolved") fail "!$line holds dotdot's .env" ;; esac
    [ -z "$(find "$line" -type l -print -quit)" ] || fail "!$line holds symlinks"
    copied+=("$line")
  else
    git cat-file -e "HEAD:$line" 2>/dev/null \
      || printf '%s⚠️  excluded path is not in HEAD, nothing to leave out: %s%s\n' "$CYAN" "$line" "$RESET" >&2
    excluded+=("$line")
  fi
done < "$EXCLUDE_LIST"
pathspec=(.)
for path in "${excluded[@]}"; do
  pathspec+=(":(exclude,literal)$path")
done
[ -n "$(git ls-files -- "${pathspec[@]}")" ] || fail "the exclude list leaves nothing to release"

mkdir -p "$DEST"
DEST=$(cd "$DEST" && pwd -P)
case "$BASE/" in "$DEST"/*) fail "destination must not contain this repo: $DEST" ;; esac

if [ ! -d "$DEST/.git" ]; then
  [ -z "$(ls -A "$DEST")" ] || fail "destination is neither empty nor a git repo: $DEST"
  git init -q -b "$BRANCH" "$DEST"
fi
rel() { git -C "$DEST" "$@"; }
[ "$(rel symbolic-ref --short HEAD)" = "$BRANCH" ] || fail "release repo is not on branch $BRANCH"
[ -z "$(rel status --porcelain)" ] || [ -z "$(rel rev-parse -q --verify HEAD)" ] \
  || fail "release repo has uncommitted changes: $DEST"
! rel rev-parse -q --verify "refs/tags/$TAG" >/dev/null || fail "tag already exists: $TAG"

for tool in ssh-keygen ssh-agent ssh-add; do
  command -v "$tool" >/dev/null || fail "$tool not found; it is needed to sign with an SSH key"
done
rel config user.name "$AUTHOR_NAME"
rel config user.email "$AUTHOR_EMAIL"
EMAIL=$AUTHOR_EMAIL
SIGNERS="$DEST/.git/allowed_signers"
printf '%s namespaces="git" %s\n' "$EMAIL" "$(cat "$PUBLIC_KEY")" > "$SIGNERS"
rel config gpg.format ssh
rel config user.signingkey "$PUBLIC_KEY"
rel config gpg.ssh.allowedSignersFile "$SIGNERS"
rel config commit.gpgsign true
rel config tag.gpgsign true

# Every signature (this probe, the commit, the tag) goes through an ssh-agent
# of this run's own, on a socket in a private temp dir, holding the signing key
# alone: its passphrase is asked once, and the user's own agent is never used.
# Signing with the .pub tells ssh-keygen and git to sign through the agent. The
# agent stops once the tag is signed, or on any exit; the key expires in it
# after 10 minutes regardless.
probe=$(mktemp -d)
stop_agent() {
  [ -z "${SSH_AGENT_PID-}" ] || ssh-agent -k >/dev/null 2>&1 || true
  unset SSH_AUTH_SOCK SSH_AGENT_PID
}
trap 'stop_agent; rm -rf "$probe"' EXIT
agent=$(ssh-agent -s -a "$probe/agent") || fail "could not start ssh-agent for signing"
SSH_AGENT_PID=$(sed -n 's/^SSH_AGENT_PID=\([0-9][0-9]*\);.*/\1/p' <<<"$agent")
[ -n "$SSH_AGENT_PID" ] || fail "could not start ssh-agent for signing"
export SSH_AUTH_SOCK="$probe/agent" SSH_AGENT_PID
step "🔏 Signing the release: enter the passphrase of your signing key"
ssh-add -q -t 600 -- "$SIGNING_KEY" \
  || fail "cannot load $SIGNING_KEY (wrong passphrase, or the file is readable by others: chmod 600)"
echo "release signing probe" > "$probe/payload"
ssh-keygen -Y sign -q -f "$PUBLIC_KEY" -n git "$probe/payload" \
  || fail "cannot sign with $SIGNING_KEY"
ssh-keygen -Y verify -q -f "$SIGNERS" -I "$EMAIL" -n git -s "$probe/payload.sig" < "$probe/payload" >/dev/null \
  || fail "$PUBLIC_KEY does not verify signatures made with $SIGNING_KEY"


step "📦 Exporting the project minus the exclude list"
find "$DEST" -mindepth 1 -maxdepth 1 ! -name .git -exec rm -rf {} +
git archive --format=tar HEAD -- "${pathspec[@]}" | tar -x -C "$DEST"
for path in "${copied[@]}"; do
  mkdir -p "$DEST/$(dirname -- "$path")"
  cp -R -- "$path" "$DEST/$path"
done

# dotdot's .env never ships, however it got into the export (tracked by
# mistake, or a "!" line).
[ ! -e "$DEST/$(dotdot_rel "$ENV_FILE")" ] || fail "$(dotdot_rel "$ENV_FILE") is in the export, nothing committed; untrack or exclude it"
secrets='sk-or-v1-[A-Za-z0-9]{32,}|sk-ant-[A-Za-z0-9_-]{32,}|BEGIN [A-Z ]*PRIVATE KEY|AKIA[0-9A-Z]{16}|hf_[A-Za-z0-9]{30,}|gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{30,}|RELEASE_PAT_[A-Z0-9_]+=[A-Za-z0-9+/]{20,}'
if hits=$(grep -rIlE --exclude-dir=.git "$secrets" "$DEST"); then
  fail "possible secrets in export, nothing committed:
$hits"
fi

rel add -A
[ ${#copied[@]} -eq 0 ] || rel add -f -- "${copied[@]}"
rel diff --cached --quiet && fail "no changes since the last release"
rel commit -q -S -m "Release $TAG" -m "Source: $(git rev-parse --short HEAD)"

verify() { rel "$@" >/dev/null 2>&1; }
verify verify-commit HEAD || fail "release commit is not validly signed by $PUBLIC_KEY; not tagged"
rel tag -s "$TAG" -m "Release $TAG"
verify verify-tag "$TAG" || fail "tag $TAG is not validly signed by $PUBLIC_KEY"
stop_agent

printf '\n%s🚀 %sRelease %s committed and signed%s\n' "$CYAN" "$BOLD" "$TAG" "$RESET"
printf '%s✅ %s%s%s\n' "$GREEN$BOLD" "$RESET$GREEN" "$(dotdot_rel "$DEST")" "$RESET"
release_push
