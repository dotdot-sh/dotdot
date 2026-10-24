#!/usr/bin/env bash

dot::use framework.integrations.github-cli.internal.environment

framework.integrations.github-cli.service::is_installed() {
  command -v "$GITHUB_CLI" >/dev/null
}

framework.integrations.github-cli.service::is_authenticated() {
  framework.integrations.github-cli.service::is_installed || return 1
  framework.integrations.github-cli.internal.environment::has_token || framework.integrations.github-cli.internal.environment::gh auth status >/dev/null 2>&1
}

framework.integrations.github-cli.service::run() {
  framework.integrations.github-cli.internal.environment::gh "$@"
}

framework.integrations.github-cli.service::tarball() {
  framework.integrations.github-cli.internal.environment::gh api "repos/$1/tarball/$2" > "$3"
}

framework.integrations.github-cli.service::current_repository() {
  (cd -- "$1" && framework.integrations.github-cli.internal.environment::gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null) || true
}

framework.integrations.github-cli.service::has_repository() {
  framework.integrations.github-cli.internal.environment::gh repo view "$1" --json nameWithOwner >/dev/null 2>&1
}
