#!/usr/bin/env bash

dot::use framework.console.args core.modules.release.service framework.console.output framework.console.prompt

core.modules.release.console::parse_push_option() {
  case "$1" in
    --push-all) RELEASE_PUSH_ALL=true ;;
    --force) RELEASE_FORCE=true ;;
    --cache-pat=*)
      RELEASE_CACHE_MINUTES="${1#*=}"
      [[ "$RELEASE_CACHE_MINUTES" =~ $RELEASE_CACHE_MINUTES_PATTERN ]] || framework.console.args::invalid "--cache-pat takes whole minutes, e.g. --cache-pat=15"
      ;;
    --*)
      [[ "${1#--}" =~ $RELEASE_REMOTE_NAME_PATTERN ]] || framework.console.args::invalid "Unexpected option: $1"
      RELEASE_PUSH_TO+=("${1#--}")
      ;;
    *) return 1 ;;
  esac
}

core.modules.release.console::wants_push() {
  local name="$1" tag="$2"
  core.modules.release.service::is_targeted "$name" && return 0
  framework.console.prompt::confirm "Push $tag to $name?"
}

core.modules.release.console::push() {
  local branch="$1" tag="$2" index name failures=0 force=""
  ! $RELEASE_FORCE || force=--force
  core.modules.release.service::point_remotes
  framework.console.output::newline
  for index in "${!RELEASE_REMOTES[@]}"; do
    name="${RELEASE_REMOTES[$index]}"
    if ! core.modules.release.console::wants_push "$name" "$tag"; then
      framework.console.output::line "Not pushed to $name. Later: bash dot release:push --$name${force:+ --force}"
      continue
    fi
    [ "$(core.modules.release.service::token_store)" != gpg ] || framework.console.output::info "Pushing to $name: if asked, enter the passphrase of this remote's token."
    if core.modules.release.service::push_with_token "$RELEASE_DESTINATION" "$name" "${RELEASE_REMOTE_URLS[$index]}" -q --atomic ${force:+"$force"} "refs/heads/$branch" --tags; then
      framework.console.output::success "Pushed to $name."
    else
      framework.console.output::error "Push to $name failed. Retry: bash dot release:push --$name${force:+ --force}"
      failures=$((failures + 1))
    fi
  done
  framework.console.output::newline
  [ "$failures" -eq 0 ] || framework.console.output::fail "$failures push(es) failed; the release commit and tag are kept."
}

core.modules.release.console::print_warnings() {
  local warning
  for warning in ${RELEASE_WARNINGS[@]+"${RELEASE_WARNINGS[@]}"}; do
    framework.console.output::warn "$warning"
  done
}

core.modules.release.console::ensure_settings() {
  local added
  added=$(core.modules.release.service::seed_settings)
  [ -n "$added" ] || return 0
  framework.console.output::warn "Release settings were missing, so they were added to $(dot::relative "$RELEASE_ENV_FILE"):"
  framework.console.output::detail "$(printf '%s' "$added" | paste -sd ' ' -)"
  framework.console.output::fail "Set them in $(dot::relative "$RELEASE_ENV_FILE"), then try again."
}

core.modules.release.console::ensure_exclude_list() {
  local created
  created=$(core.modules.release.service::seed_exclude_list "$1")
  [ -n "$created" ] || return 0
  framework.console.output::fail "Created the exclude list $created from dotdot's example; review what it leaves out, then try again."
}
