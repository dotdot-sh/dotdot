#!/usr/bin/env bash

DESCRIPTION="Seed USER.md and link dotdot and its plugins into the places the harness reads."

dot::use framework.console.args framework.console.output framework.console.prompt core.system.sync.service

usage() {
  local entry
  cat <<EOF
bash dot sync — activate dotdot: seed USER.md, then symlink dotdot's and the
installed plugins' files into the locations the harness reads.

What is linked is up to you: $(dot::relative "$SYNC_MAP") lists every link as
origin::destination, in order, and the first line naming a destination wins.
It starts from dotdot's default (AGENTS.md at the project root) and holds a
block per plugin, written from the plugin's plugin.conf (HARNESS_SKILLS,
HARNESS_AGENTS, LINKS) when it is added and dropped when it is removed. Edit
any line; --refresh <owner>/<name> writes a plugin's block afresh (plugins:update
does). Links never point at dotdot's .env, nor land inside dotdot or .git, and
a plugin's lines stay inside that plugin. A plugin's skills and agents must be
named <name>-..., after the plugin. The map's header explains its shortcuts:
@dotdotSkills, @pluginsSkills (and Agents), @module.<name>.<path>,
@plugin.<owner>.<name>.<path>, a /* ending to link each entry, and
!<destination> to remove a link (symlinks only, never a real file).

Run it after installing dotdot, after creating a git worktree, and after
adding, renaming, or removing anything the links cover. Re-running is safe.
USER.md is created from USER.example.md when it is missing.

Every run previews each destination, then asks [y/N] on a terminal before
changing anything (piped input is refused, unless -y is given):
  - missing                      → linked
  - already a link to dotdot     → left as is ("already linked")
  - a link into dotdot's own files that points elsewhere, broken or not
                                 → relinked ("dotdot link moved; will relink")
  - a broken link into dotdot's own files that no link names, in a
    directory the links point into
                                 → removed ("broken dotdot link; will remove")
  - anything else                → "existing; will skip"

-y / --yes applies the previewed changes without asking, terminal or not.
The installer and plugin commands use it; agents never pass it.

--override changes only what happens to existing destinations once confirmed:
  - a symlink pointing elsewhere → replaced ("existing; will override")
  - a real file                  → renamed to <name>.bak-<timestamp>, then
                                   linked ("existing; will back up and override")
  - a real directory             → still skipped; remove it yourself

Usage:
  bash dot sync
  bash dot sync --override
  bash dot sync --refresh <owner>/<name>
  bash dot sync -y
  bash dot sync --help

Current links (origin::destination, origin relative to dotdot, destination
relative to the project):
EOF
  while IFS= read -r entry; do
    framework.console.output::line "  - $entry"
  done < <(core.system.sync.service::mappings)
  cat <<'EOF'

An origin ending in "/*" links every direct child individually. Link targets
are relative, so the links survive a clone, a move, or a container rebuild.
EOF
}

action_note() {
  case "$1" in
    link) framework.console.output::paint green "(will link)" ;;
    ok) printf '(already linked)' ;;
    move) framework.console.output::paint green "(dotdot link moved; will relink)" ;;
    prune) framework.console.output::paint green "(broken dotdot link; will remove)" ;;
    unlink) framework.console.output::paint green "(removed in sync.map; will unlink)" ;;
    skip) framework.console.output::paint yellow "(existing; will skip)" ;;
    relink) framework.console.output::paint red "(existing; will override)" ;;
    backup) framework.console.output::paint red "(existing; will back up and override)" ;;
  esac
}

print_seeds() {
  local note
  for note in ${SYNC_MAP_NOTES[@]+"${SYNC_MAP_NOTES[@]}"}; do
    framework.console.output::line "  $(framework.console.output::paint green "(will $note)")"
  done
  case "$(core.system.sync.service::user_state)" in
    create) framework.console.output::line "  $DOTDOT_NAME/USER.md $(framework.console.output::paint green "(will create from USER.example.md)")" ;;
    existing) framework.console.output::line "  $DOTDOT_NAME/USER.md $(framework.console.output::paint yellow "(existing; will skip)")" ;;
  esac
}

print_preview() {
  local index
  framework.console.output::line "Preview only; nothing changes unless you answer y below:"
  print_seeds
  for index in ${SYNC_ACTIONS[@]+"${!SYNC_ACTIONS[@]}"}; do
    printf '  %s ' "${SYNC_LABELS[$index]}"
    action_note "${SYNC_ACTIONS[$index]}"
    printf '\n'
  done
  [ "$SYNC_OVERRIDABLE" -eq 0 ] \
    || framework.console.output::line "Run with --override to replace the $SYNC_OVERRIDABLE existing symlink(s)/file(s) above; files are backed up first."
}

print_errors() {
  local message
  for message in ${SYNC_ERRORS[@]+"${SYNC_ERRORS[@]}"}; do
    framework.console.output::error "$message"
  done
  SYNC_ERRORS=()
}

print_result() {
  local warning
  print_errors
  framework.console.output::line "Done. $SYNC_LINKED linked, $SYNC_REMOVED removed, $SYNC_UNCHANGED already linked, $SYNC_SKIPPED skipped, $SYNC_FAILURES failed."
  for warning in ${SYNC_WARNINGS[@]+"${SYNC_WARNINGS[@]}"}; do
    framework.console.output::warn "Overridden: $warning"
  done
}

handle() {
  local override=false confirmed=false refresh=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --override) override=true ;;
      -y | --yes) confirmed=true ;;
      --refresh)
        framework.console.args::require_value "$@"
        [[ "$2" =~ ^[a-z0-9][a-z0-9-]*/[a-z0-9][a-z0-9-]*$ ]] || framework.console.args::invalid "--refresh takes a plugin as <owner>/<name>: $2"
        refresh="$refresh $2"
        shift
        ;;
      *) framework.console.args::unexpected "$1" ;;
    esac
    shift
  done
  core.system.sync.service::plan "$override" "$refresh"
  core.system.sync.service::count_changes
  print_errors
  print_preview
  if [ "$SYNC_CHANGES" -eq 0 ]; then
    framework.console.output::line "Nothing to do."
    [ "$SYNC_FAILURES" -eq 0 ]
    return
  fi
  if $confirmed; then
    framework.console.output::line "Applying $SYNC_CHANGES change(s) (-y)."
  else
    framework.console.prompt::confirm_or_exit "Apply $SYNC_CHANGES change(s)?" n "bash dot sync"
  fi
  core.system.sync.service::apply
  print_result
  [ "$SYNC_FAILURES" -eq 0 ]
}
