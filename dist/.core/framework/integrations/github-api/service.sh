#!/usr/bin/env bash

dot::use framework.integrations.github-api.internal.request

GITHUB_HOST_URL="https://github.com/"
GITHUB_REPOSITORY_PATTERN='^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$'
GITHUB_REF_PATTERN='^[A-Za-z0-9][A-Za-z0-9._/-]*$'
GITHUB_COMMIT_PATTERN='comment=[0-9a-f]\{40\}'
GITHUB_HEADER_BYTES=1024

framework.integrations.github-api.service::is_repository() {
  [[ "$1" =~ $GITHUB_REPOSITORY_PATTERN ]]
}

framework.integrations.github-api.service::url() {
  printf '%s%s\n' "$GITHUB_HOST_URL" "$1"
}

framework.integrations.github-api.service::is_ref() {
  [[ "$1" =~ $GITHUB_REF_PATTERN ]] && [[ "$1" != *..* ]]
}

framework.integrations.github-api.service::tarball() {
  framework.integrations.github-api.internal.request::tarball "$@"
}

framework.integrations.github-api.service::tarball_commit() {
  gzip -dc -- "$1" 2>/dev/null | head -c "$GITHUB_HEADER_BYTES" | tr -d '\000' \
    | grep -ao "$GITHUB_COMMIT_PATTERN" | cut -d= -f2 || true
}
