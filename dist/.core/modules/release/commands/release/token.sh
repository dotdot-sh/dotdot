#!/usr/bin/env bash

DESCRIPTION="Store, encrypted, the personal access token a release remote pushes with."

dot::use framework.console.args core.modules.release.console core.modules.release.service framework.console.output framework.console.prompt

usage() {
  cat <<EOF
bash dot release:token — store the personal access token that bash dot
release pushes to a remote with, or remove it.

Give the token write access to the release repo and nothing else. It is
asked for without echo, never taken as an argument, and stored encrypted for
that remote's exact url: in the macOS keychain, in the desktop keyring
(libsecret), or, where neither exists, in $(dot::relative "$RELEASE_ENV_FILE") as
${RELEASE_TOKEN_PREFIX}<NAME>, encrypted by gpg together with the url, with a
passphrase you choose and are asked for on every push (see --cache-pat in
bash dot release:push --help). Storing again replaces the token, and storing
or removing one drops it from that cache; a changed remote url needs a new
one.

Usage:
  bash dot release:token <remote>
  bash dot release:token <remote> --remove
  bash dot release:token --help

Arguments:
  <remote>    Remote name, from ${RELEASE_REMOTE_PREFIX}<NAME> (lowercased) in
              $(dot::relative "$RELEASE_ENV_FILE").

Optional:
  --remove    Remove the stored token instead.

Examples:
  bash dot release:token github
  bash dot release:token github --remove
EOF
}

handle() {
  local name="" remove=false url token
  while [ $# -gt 0 ]; do
    case "$1" in
      --remove) remove=true; shift ;;
      -*) framework.console.args::invalid "Unexpected option: $1" ;;
      *) [ -z "$name" ] || framework.console.args::unexpected "$1"; name="$1"; shift ;;
    esac
  done
  [ -n "$name" ] || framework.console.args::invalid "A remote name is required."
  cd "$RELEASE_PROJECT" || framework.console.output::fail "Cannot enter the project: $RELEASE_PROJECT"
  core.modules.release.console::ensure_settings
  core.modules.release.service::load_remotes
  url=$(core.modules.release.service::remote_url "$name")
  if $remove; then
    core.modules.release.service::remove_token "$url" || framework.console.output::fail "No token stored for $name."
    framework.console.output::success "Removed the token for $name"
    return 0
  fi
  framework.console.prompt::can_ask || framework.console.output::fail "The token is asked for at a terminal; run this one yourself."
  token=$(framework.console.prompt::secret "Token for $name ($url)")
  [ -n "$token" ] || framework.console.output::fail "No token given; nothing stored."
  [ "$(core.modules.release.service::token_store)" != gpg ] \
    || framework.console.output::info "Choose a passphrase to encrypt the token for $name, then repeat it; pushes ask for it."
  core.modules.release.service::save_token "$url" "$token" || framework.console.output::fail "Could not store the token for $name."
  token=""
  framework.console.output::success "Token for $name stored in the $(core.modules.release.service::token_store) store"
}
