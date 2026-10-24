#!/usr/bin/env bash

dot::use framework.helpers.net

GITHUB_API_URL="https://api.github.com"
GITHUB_ARCHIVE_URL="https://github.com"

framework.integrations.github-api.internal.request::token() {
  dot::optional_config GH_TOKEN || true
}

# Downloads <repository>@<ref> as a tarball: through the API as the token's
# owner when GH_TOKEN is set, else from the public archive.
framework.integrations.github-api.internal.request::tarball() {
  local repository="$1" ref="$2" file="$3" token
  token=$(framework.integrations.github-api.internal.request::token)
  if [ -z "$token" ]; then
    framework.helpers.net::download "$GITHUB_ARCHIVE_URL/$repository/archive/$ref.tar.gz" "$file"
    return
  fi
  framework.helpers.net::download "$GITHUB_API_URL/repos/$repository/tarball/$ref" "$file" "Authorization: Bearer $token"
}
