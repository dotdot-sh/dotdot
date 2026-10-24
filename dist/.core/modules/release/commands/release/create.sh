#!/usr/bin/env bash

DESCRIPTION="Export the project minus an exclude list and make a signed release commit in a separate repo."

dot::use framework.console.args core.modules.release.console core.modules.release.service framework.console.output framework.console.prompt

usage() {
  cat <<EOF
bash dot release:create — prepare one signed release commit, tagged v<version>, in
a separate release repo, so the public history holds release commits and
nothing else.

Every file tracked in HEAD is exported except the paths the exclude list
names. Git-ignored files are left out, unless the list names one with a
leading "!" (a build you made, e.g. !dist): that one is copied from disk.
The exclude list itself is always left out, and dotdot's .env never ships.
It runs no project commands (no build, test, or install), so it works the
same for any project: build and test in your own workflow first. It refuses on a
dirty tree, a missing or mismatched signing key, anything that looks like a
secret, or a remote a flag names that has no token stored. Then it asks,
remote by remote, whether to push (default no); without a terminal it pushes
only where a flag says so. bash dot release:push pushes the same way later.
Each remote is pushed over https with its own personal access token, stored
encrypted with bash dot release:token <remote>.

Usage:
  bash dot release:create <version> [--<remote>...] [--push-all] [--cache-pat=N] [--force]
  bash dot release:create --help

Arguments:
  <version>   Semantic version, e.g. 1.2.0 or 1.2.0-rc.1.

Optional:
  --<remote>  Push to that remote without asking, e.g. --github. Repeatable.
              Remote names come from ${RELEASE_REMOTE_PREFIX}<NAME> (lowercased).
  --push-all  Push to every configured remote without asking.
  --force     Force push, overwriting the remotes' branch and tags. Asks
              first ([y/N]: only y or yes goes ahead), and only at a terminal.
  --cache-pat=N
              Keep the decrypted tokens in memory for N minutes from now, so
              pushes until then ask no passphrase; given again, the N minutes
              restart. 0 forgets them. By default nothing is kept.

Settings, read from dotdot's git-ignored $(dot::relative "$RELEASE_ENV_FILE") (added there,
empty, when missing; set them and run again):
  RELEASE_DESTINATION        release repo directory, from the project root
  RELEASE_EXCLUDE_FILE_LIST  exclude list, from the project root: one path per line,
                             "!path" to include a git-ignored path, # comments
  RELEASE_BRANCH             branch in the release repo
  ${RELEASE_REMOTE_PREFIX}<NAME>      https:// url of remote <name> (lowercased); at least one
  RELEASE_SIGNING_KEY      private SSH key file name in \$HOME/.ssh/; its .pub sits next to it
  RELEASE_AUTHOR_NAME      name on the release commits
  RELEASE_AUTHOR_EMAIL     email on the release commits; must belong to the account holding
                           the signing key for GitHub to show "Verified"
  ${RELEASE_TOKEN_PREFIX}<NAME>       remote <name>'s token, encrypted, where there is no keychain;
                           written by bash dot release:token, never by hand

Environment variables are never read. Every setting is required; a missing or
empty one stops the release.

Examples:
  bash dot release:create 1.2.0
  bash dot release:create 1.2.0 --github
  bash dot release:create 1.2.0 --push-all
  bash dot release:create 1.2.0 --github --cache-pat=15
EOF
}

handle() {
  local version="" tag exclusions branch
  while [ $# -gt 0 ]; do
    if core.modules.release.console::parse_push_option "$1"; then
      shift
      continue
    fi
    case "$1" in
      -*) framework.console.args::invalid "Unexpected option: $1" ;;
      *) [ -z "$version" ] || framework.console.args::unexpected "$1"; version="$1"; shift ;;
    esac
  done
  [ -n "$version" ] || framework.console.args::invalid "A version is required."
  [[ "$version" =~ $RELEASE_VERSION_PATTERN ]] || framework.console.args::invalid "Not a semantic version: $version"
  tag="v$version"
  ! $RELEASE_FORCE || framework.console.prompt::confirm_or_exit "Force push $tag, overwriting the remotes' history?" n "bash dot release:create $version --force"
  cd "$RELEASE_PROJECT" || framework.console.output::fail "Cannot enter the project: $RELEASE_PROJECT"
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || framework.console.output::fail "The project is not a git repository: $RELEASE_PROJECT"
  core.modules.release.console::ensure_settings
  RELEASE_DESTINATION=$(dot::config RELEASE_DESTINATION)
  exclusions=$(dot::config RELEASE_EXCLUDE_FILE_LIST)
  branch=$(dot::config RELEASE_BRANCH)
  RELEASE_SIGNING_NAME=$(dot::config RELEASE_SIGNING_KEY)
  RELEASE_AUTHOR_NAME=$(dot::config RELEASE_AUTHOR_NAME)
  RELEASE_AUTHOR_EMAIL=$(dot::config RELEASE_AUTHOR_EMAIL)
  core.modules.release.console::ensure_exclude_list "$exclusions"
  git check-ref-format --branch "$branch" >/dev/null 2>&1 || framework.console.output::fail "RELEASE_BRANCH is not a valid branch name: $branch"
  core.modules.release.service::check_signing_identity
  core.modules.release.service::load_remotes
  core.modules.release.service::check_push_targets
  core.modules.release.service::check_tokens
  [ -z "$(git status --porcelain)" ] || framework.console.output::fail "Working tree is dirty; commit or stash first."
  [ -f "$exclusions" ] || framework.console.output::fail "Exclude list not found: $exclusions"
  core.modules.release.service::read_exclusions "$exclusions"
  core.modules.release.console::print_warnings
  core.modules.release.service::prepare_repository "$branch" "$tag"
  core.modules.release.service::configure_signing
  framework.console.output::title "🔏 Signing the release: enter the passphrase of your signing key"
  core.modules.release.service::start_agent
  framework.console.output::title "📦 Exporting the project minus the exclude list"
  core.modules.release.service::export
  core.modules.release.service::scan_secrets
  core.modules.release.service::commit "$tag"
  core.modules.release.service::stop_agent
  framework.console.output::newline
  framework.console.output::success "Release $tag committed and signed"
  framework.console.output::detail "$(dot::relative "$RELEASE_DESTINATION")"
  core.modules.release.console::push "$branch" "$tag"
}
