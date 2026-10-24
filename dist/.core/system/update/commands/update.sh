#!/usr/bin/env bash

DESCRIPTION="Update dotdot's core (.core/) to the latest dotdot; plugins and context files are untouched."

dot::use framework.console.args framework.helpers.fs framework.console.output framework.console.prompt core.system.update.service

usage() {
  cat <<EOF
bash dot update — update dotdot's core ($DOTDOT_NAME/${UPDATE_TREES[0]}/) to the latest dotdot, downloaded from
$UPDATE_REPOSITORY_URL ($UPDATE_BRANCH), then optionally run bash dot sync.

Plugins ($(dot::relative "$PLUGINS_DIR")/) are left to bash dot plugins:update.
Every context file (AGENTS.md, RULES.md, PRODUCT.md, Features/, Decisions/,
Notes/, USER.md, …) is never read or written.

$(dot::relative "$VERSION_FILE") holds the commit dotdot was last installed or
updated from. The update fetches that commit and the latest one with git (only
those two, into a temporary repo nothing of yours touches), shows both, asks, and:
  - copies every file of the latest commit over dotdot's
  - removes a file only when it existed at the recorded commit and no longer
    exists at the latest (a move counts as removed here, added there). A
    removed file that was edited locally is kept and reported, never deleted
  - leaves every other file alone: your own skills, agents, and scripts
  - records the latest commit, only once everything else succeeded

Without a recorded version, or with a recorded commit the public repo doesn't
have, nothing is removed: files the latest commit lacks are listed for you to
review instead.

-y / --yes answers yes to the update's own question; sync is still asked,
since it changes files outside dotdot.

Every run needs a terminal (piped input is refused), --yes included, so only a
person can start an update.

Usage:
  bash dot update
  bash dot update -y
  bash dot update --help
EOF
}

report() {
  local new="$1"
  framework.console.output::newline
  framework.console.output::success "dotdot is updated to ${new:0:7}: ${#UPDATE_ADDED[@]} added, ${#UPDATE_UPDATED[@]} updated, ${#UPDATE_REMOVED[@]} removed, $UPDATE_UNCHANGED unchanged."
  if [ ${#UPDATE_EDITED[@]} -gt 0 ]; then
    framework.console.output::warn "Removed upstream but edited here, so kept; delete them once reviewed:"
    printf '  %s\n' "${UPDATE_EDITED[@]}"
  fi
  if [ ${#UPDATE_UNKNOWN[@]} -gt 0 ]; then
    framework.console.output::warn "Not in dotdot at ${new:0:7}; kept. Delete the stale ones, keep your own:"
    printf '  %s\n' "${UPDATE_UNKNOWN[@]}"
  fi
}

handle() {
  local confirmed=false old new source tree failure
  case "${1-}" in
    -y | --yes) confirmed=true; shift ;;
  esac
  [ $# -eq 0 ] || framework.console.args::unexpected "$1"
  framework.console.prompt::can_ask || framework.console.output::fail "Aborted — nothing changed. Confirmation needs a terminal; run bash dot update yourself."
  command -v git >/dev/null || framework.console.output::fail "git is required."
  old=$(core.system.update.service::installed_commit)
  framework.helpers.fs::make_temp_dir UPDATE_WORKSPACE || framework.console.output::fail "Could not create a temp directory."
  UPDATE_REPOSITORY="$UPDATE_WORKSPACE/repository"
  framework.console.output::spin "Downloading dotdot..." core.system.update.service::download "$old" || framework.console.output::fail "Download failed. Nothing changed."
  core.system.update.service::has_commit "$UPDATE_NEW_REF" || framework.console.output::fail "The download holds no commit."
  new=$(core.system.update.service::git rev-parse --verify "$UPDATE_NEW_REF^{commit}")
  if [ -n "$old" ] && ! core.system.update.service::has_commit "$UPDATE_OLD_REF"; then
    framework.console.output::warn "The installed version ${old:0:7} isn't in the public repo: nothing will be removed; files the latest lacks are listed instead."
    old=""
  elif [ -z "$old" ]; then
    framework.console.output::warn "No $(dot::relative "$VERSION_FILE"): nothing will be removed; files the latest lacks are listed instead."
  fi
  if [ "$old" = "$new" ]; then
    framework.console.output::success "dotdot is up to date (${new:0:7})."
    return 0
  fi
  framework.console.output::line "Latest: $(core.system.update.service::summary "$new")"
  [ -z "$old" ] || framework.console.output::line "Yours:  $(core.system.update.service::summary "$old")"
  if $confirmed; then
    framework.console.output::line "Update dotdot? yes (--yes)"
  else
    framework.console.prompt::confirm_or_exit "Update dotdot?" n "bash dot update"
  fi
  framework.console.output::line "Updating dotdot..."
  source="$UPDATE_SOURCE"
  core.system.update.service::extract "$new" "$source" "$UPDATE_WORKSPACE/tree" || framework.console.output::fail "Could not read $source/ at ${new:0:7}."
  tree="$UPDATE_WORKSPACE/tree/$source"
  [ -d "$tree/${UPDATE_TREES[0]}" ] || framework.console.output::fail "Commit ${new:0:7} has no $source/${UPDATE_TREES[0]}/."
  core.system.update.service::compare "$tree"
  if [ -n "$old" ]; then
    core.system.update.service::find_removed "$old" "$new" "$source"
  else
    core.system.update.service::find_unknown "$tree"
  fi
  if ! core.system.update.service::copy "$tree"; then
    for failure in "${UPDATE_FAILURES[@]}"; do
      framework.console.output::error "$failure"
    done
    framework.console.output::fail "Update incomplete; version not recorded. Fix the failures above and rerun bash dot update."
  fi
  core.system.update.service::record_version "$new" || framework.console.output::fail "Files updated, but $(dot::relative "$VERSION_FILE") could not be written."
  report "$new"
  framework.console.output::newline
  if framework.console.prompt::confirm "Run bash dot sync now?"; then
    dot::call sync || true
  else
    framework.console.output::line "Run bash dot sync when ready; it relinks moved dotdot links and removes broken ones."
  fi
}
