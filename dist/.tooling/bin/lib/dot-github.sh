#!/usr/bin/env bash
# dot-github.sh — downloads from GitHub repos, public or private.
#
# A logged-in gh, or a GH_TOKEN in dotdot's .env, reaches private repos
# through the GitHub API; without either, public repos are fetched over https
# with curl. Nothing is ever executed from what is downloaded.
#
# Source it after lib/dot-paths.sh and lib/dot-kv.sh.

GITHUB_HOST_URL="https://github.com/"
GITHUB_RAW_URL="https://raw.githubusercontent.com"
GITHUB_REPO_PATTERN='^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$'
GITHUB_REF_PATTERN='^[A-Za-z0-9][A-Za-z0-9._/-]*$'
GITHUB_COMMIT_PATTERN='comment=[0-9a-f]\{40\}'
GITHUB_HEADER_BYTES=1024

if token=$(env_get GH_TOKEN 2>/dev/null) && [ -n "$token" ]; then
  export GH_TOKEN="$token"
fi
unset token

# Prints "owner/repo" for a github.com URL or an "owner/repo" string, or fails.
github_repo() {
  local repo=${1#"$GITHUB_HOST_URL"}
  repo=${repo%/}
  repo=${repo%.git}
  [[ "$repo" =~ $GITHUB_REPO_PATTERN ]] || return 1
  printf '%s\n' "$repo"
}

# True when $1 is a ref (branch, tag, or commit) safe to put in a URL.
github_ref_valid() {
  [[ "$1" =~ $GITHUB_REF_PATTERN ]] && [[ "$1" != *..* ]]
}

# True when gh can make authenticated API calls.
github_api_ready() {
  command -v gh >/dev/null || return 1
  [ -n "${GH_TOKEN-}" ] || gh auth status >/dev/null 2>&1
}

# Downloads the tarball of repo $1 at ref $2 into file $3.
github_tarball() {
  if github_api_ready; then
    gh api "repos/$1/tarball/$2" > "$3"
  else
    curl --proto '=https' --tlsv1.2 -fsSL -o "$3" "$GITHUB_HOST_URL$1/archive/$2.tar.gz"
  fi
}

# Downloads file $3 of repo $1 at ref $2 into file $4.
github_file() {
  if github_api_ready; then
    gh api -H "Accept: application/vnd.github.raw" "repos/$1/contents/$3?ref=$2" > "$4"
  else
    curl --proto '=https' --tlsv1.2 -fsSL -o "$4" "$GITHUB_RAW_URL/$1/$2/$3"
  fi
}

# Prints the commit a GitHub tarball was made from (its pax header), or nothing.
github_tarball_commit() {
  gzip -dc -- "$1" 2>/dev/null | head -c "$GITHUB_HEADER_BYTES" | tr -d '\000' \
    | grep -ao "$GITHUB_COMMIT_PATTERN" | cut -d= -f2 || true
}
