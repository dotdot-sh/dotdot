#!/usr/bin/env bash

GITHUB_CLI="gh"

framework.integrations.github-cli.internal.environment::token() {
  dot::optional_config GH_TOKEN || true
}

framework.integrations.github-cli.internal.environment::has_token() {
  [ -n "$(framework.integrations.github-cli.internal.environment::token)" ]
}

framework.integrations.github-cli.internal.environment::gh() {
  local token
  token=$(framework.integrations.github-cli.internal.environment::token)
  if [ -n "$token" ]; then
    GH_TOKEN="$token" GH_PROMPT_DISABLED=1 "$GITHUB_CLI" "$@"
  else
    GH_PROMPT_DISABLED=1 "$GITHUB_CLI" "$@"
  fi
}
