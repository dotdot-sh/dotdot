#!/usr/bin/env bash
# description: Seed USER.md and local settings, and link dotdot into the places the harness reads.

set -euo pipefail

. "$(dirname "$0")/lib/dot-paths.sh"
. "$(dirname "$0")/lib/dot-confirm.sh"

# Each entry is "origin::destination". An origin is relative to dotdot
# ($DOTDOT_ROOT), a destination to the project dotdot serves ($BASE) — that
# split is what lets the same table work whether dotdot is applied to a
# real project or being developed in its own repo.
#
# A directory origin is symlinked as a single unit ("full" mode) —
# unless the origin ends with "/*", which switches to "tree" mode:
# symlink every direct child of that directory (files and subdirectories
# alike) individually at the destination, one level deep only — a
# subdirectory is linked as a whole unit, not recursed into. ".gitkeep"
# entries are skipped. The "/*" suffix has no effect on a file origin,
# which is always symlinked directly either way.
#
# Arguments are read first; --help and a bad argument are acted on once
# usage() exists.
override=false
yes=false
arg_error=""
show_help=false
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) show_help=true ;;
    --override) override=true ;;
    -y|--yes) yes=true ;;
    *) arg_error="Unknown argument: $1"; break ;;
  esac
  shift
done

MAPPINGS=(
  "AGENTS.md::AGENTS.md"
  "RULES.md::.claude/rules/RULES.md"
  "SECURITY.md::.claude/rules/SECURITY.md"
  "USER.md::.claude/rules/USER.md"
  "PRODUCT.md::.claude/rules/PRODUCT.md"
  "$(dotdot_inner "$CLAUDE_DIR")/*::.claude/"
  "$(dotdot_inner "$SKILLS_DIR")/*::.claude/skills/"
  "$(dotdot_inner "$AGENTS_DIR")/*::.claude/agents/"
)
# Every kit's skills and agents are linked like dotdot's own.
for kit_dir in "$KITS_DIR"/*/; do
  for kind in skills agents; do
    [ -d "$kit_dir$kind" ] || continue
    MAPPINGS+=("$(dotdot_inner "${kit_dir%/}")/$kind/*::.claude/$kind/")
  done
done

usage() {
  cat <<'EOF'
bash dot sync — activate dotdot: seed USER.md and .claude/settings.local.json,
then symlink files and directories
from dotdot into the locations the harness actually reads, based on the
hardcoded MAPPINGS table in the script.

A skill, agent, or instruction file added under dotdot is invisible to the
harness until it is linked into place — this is what makes it exist. Run it
after installing dotdot, after creating a git worktree, and after adding,
renaming, or removing anything the table covers. Re-running is safe.

USER.md is created from USER.example.md only when it is missing; an existing
one is never touched, not even with --override.

.claude/settings.local.json (personal, git-ignored, e.g. claude.ai connectors
on or off) is copied from dotdot's example.settings.local.json only when it is
missing, never linked, so editing it never edits dotdot. An existing one is
never touched, not even with --override; the preview says when it differs from
dotdot's example, for you to merge by hand.

Every run previews each destination, then asks [y/N] on a terminal before
changing anything (piped input is refused, unless -y is given):
  - missing                      → linked
  - already a link to dotdot     → left as is ("already linked")
  - a link into dotdot's .tooling/ that points elsewhere, broken or not
                                 → relinked ("dotdot link moved; will relink"):
                                   it is dotdot's own, left behind when a
                                   file moved (bash dot update)
  - a broken link into dotdot's .tooling/ that no mapping names, in a
    directory the table links into
                                 → removed ("broken dotdot link; will remove"):
                                   left behind when a dotdot file was renamed
                                   or removed
  - anything else                → "existing; will skip"

-y / --yes applies the previewed changes without asking, terminal or not.
The installer uses it; agents never pass it, since it approves the changes on
the user's behalf.

The entry point's "dot" link at the project root is the installer's, not
sync's.

--override changes only what happens to existing destinations once confirmed:
  - a symlink pointing elsewhere → replaced ("existing; will override")
  - a real file                  → renamed to <name>.bak-<timestamp>, then
                                   linked ("existing; will back up and override")
  - a real directory             → still skipped; remove it yourself
and every override is listed again as a warning at the end.

Usage:
  bash dot sync
  bash dot sync --override
  bash dot sync -y
  bash dot sync --help

Current mappings (origin::destination, origin relative to dotdot,
destination relative to the project dotdot serves):
EOF
  for entry in "${MAPPINGS[@]}"; do
    echo "  - $entry"
  done
  cat <<'EOF'

Notes:
  - An origin ending in "/*" links every direct child individually ("tree"
    mode), one level deep; without it a directory is linked as a single
    unit. ".gitkeep" entries are skipped.
  - Link targets are written relative to the link's own directory, so the
    links survive a clone, a move, or a container rebuild.
EOF
}

if [ -n "$arg_error" ]; then
  echo "❌ $arg_error" >&2; usage >&2; exit 1
fi
if $show_help; then
  usage; exit 0
fi


# --- colors (skipped unless both streams are a terminal) ---
# Results are split across stdout and stderr, so both have to be a terminal
# before either is colored — otherwise redirecting one of them would leave
# escape codes in the captured output.
if [ -t 1 ] && [ -t 2 ]; then
  RED=$(printf '\033[31m'); GREEN=$(printf '\033[32m')
  YELLOW=$(printf '\033[33m'); RESET=$(printf '\033[0m')
else
  RED=""; GREEN=""; YELLOW=""; RESET=""
fi

failed=0
fail() {
  printf '%sFAILED:%s %s\n' "$RED" "$RESET" "$1" >&2
  failed=$((failed + 1))
}

# Resolves $1 against the anchor directory $2 to an absolute path (even if it
# doesn't exist yet) and prints it, or fails if it escapes that anchor.
#
# Only the parent directory is resolved through symlinks, never the final
# component: on a rerun the destination IS a symlink into dotdot, and
# resolving it would hand back the origin's own path — which the caller would
# then dutifully delete and relink to itself, destroying the source file.
resolve_under() {
  local rel="$1" anchor="$2" parent base abs
  parent="$(realpath -m -- "$(dirname -- "$anchor/$rel")")"
  base="$(basename -- "$anchor/$rel")"
  # "." and ".." as the final component would name the parent itself, which
  # no mapping can legitimately mean and which the containment check below
  # would wave through.
  case "$base" in
    .|..) return 1 ;;
  esac
  abs="$parent/$base"
  # Prefix comparison rather than a `case` glob: in pattern position a "*",
  # "?" or "[" in the anchor is a wildcard, and a path that merely resembles
  # the anchor would pass containment.
  if [ "$abs" != "$anchor" ] && [ "${abs#"$anchor"/}" = "$abs" ]; then
    return 1
  fi
  printf '%s\n' "$abs"
}

# --- 1. Plan ---
# USER.md holds personal preferences and is deliberately untracked: created
# once from the example, never replaced. It is planned like a link so the
# USER.md mapping below can count on it existing once the run is confirmed.
user_file="$USER_FILE"
seed_user=false
if [ ! -e "$user_file" ] && [ ! -L "$user_file" ] && [ -f "$USER_EXAMPLE_FILE" ]; then
  seed_user=true
fi

# The project's personal Claude settings: a copy, not a link, since each
# person edits their own. Created once from dotdot's example, never replaced.
seed_local=false
if [ ! -e "$LOCAL_SETTINGS_FILE" ] && [ ! -L "$LOCAL_SETTINGS_FILE" ] && [ -f "$LOCAL_SETTINGS_EXAMPLE_FILE" ]; then
  seed_local=true
fi

# Every link is classified before anything changes, so the preview is
# exactly what will happen, and an aborted run changes nothing.
#   link     destination missing
#   ok       already a symlink to this origin
#   move     symlink into .tooling/ pointing elsewhere, relinked
#   prune    broken symlink into .tooling/ no mapping names, removed
#   skip     exists; left alone
#   relink   symlink elsewhere, replaced (--override)
#   backup   real file, renamed then linked (--override)
P_ORIGIN=(); P_DEST=(); P_LABEL=(); P_ACTION=()
# Every directory a tree mapping links into, even one left empty, is swept
# for broken links: a removed kit leaves its links in .claude/agents/
# when dotdot has no agents of its own.
TREE_DIRS=()
overridable=0

# True when the absolute path $1 lies inside dotdot's .tooling/.
in_tooling() {
  [ "${1#"$TOOLING_DIR"/}" != "$1" ]
}

plan() {
  local origin="$1" dest="$2" label="$3" action
  if [ ! -e "$dest" ] && [ ! -L "$dest" ]; then
    action=link
  elif [ -L "$dest" ] && [ "$(realpath -m -- "$dest")" = "$(realpath -m -- "$origin")" ]; then
    action=ok
  elif [ -L "$dest" ] && in_tooling "$(realpath -m -- "$dest")"; then
    action=move
  elif [ -d "$dest" ] && [ ! -L "$dest" ]; then
    action=skip
  elif ! $override; then
    action=skip
    overridable=$((overridable + 1))
  elif [ -L "$dest" ]; then
    action=relink
  else
    action=backup
  fi
  P_ORIGIN+=("$origin"); P_DEST+=("$dest"); P_LABEL+=("$label"); P_ACTION+=("$action")
}

for entry in "${MAPPINGS[@]}"; do
  # "::" is the field separator; normalize it to a single unit-separator
  # byte first since IFS splits on individual characters, not substrings,
  # and "::" would otherwise leave a spurious empty field between colons.
  IFS=$'\x1f' read -r origin dest <<<"${entry//::/$'\x1f'}"

  origin_path="$origin"
  tree=false
  if [[ "$origin" == */\* ]]; then
    tree=true
    origin_path="${origin%/\*}"
  fi

  if ! origin_abs="$(resolve_under "$origin_path" "$DOTDOT_ROOT")"; then
    fail "origin '$origin_path' resolves outside the dotdot directory"; continue
  fi
  if ! dest_abs="$(resolve_under "$dest" "$BASE")"; then
    fail "destination '$dest' resolves outside the project directory"; continue
  fi
  if [ ! -e "$origin_abs" ] && ! { $seed_user && [ "$origin_abs" = "$user_file" ]; }; then
    fail "origin '$origin_path' does not exist"; continue
  fi
  if $tree && [ ! -d "$origin_abs" ]; then
    fail "origin '$origin' uses the '/*' tree pattern but is not a directory"; continue
  fi

  # resolve_under deliberately leaves the last path component unresolved, so
  # that a destination which is already a link into dotdot is replaced rather
  # than followed back to the origin. In tree mode that component is not the
  # link being replaced though — it is a directory this writes *into*, and a
  # symlink there lands every child outside the project while the containment
  # check above still sees an in-project path.
  if $tree && [ -L "$dest_abs" ]; then
    fail "destination '$dest' is a symlink to a directory — refusing to write through it; remove it if you want dotdot linked there"
    continue
  fi

  if $tree; then
    TREE_DIRS+=("$dest_abs")
    while IFS= read -r -d '' child; do
      name="$(basename -- "$child")"
      [ "$name" = ".gitkeep" ] && continue
      plan "$child" "$dest_abs/$name" "${dest%/}/$name"
    done < <(find "$origin_abs" -mindepth 1 -maxdepth 1 -print0 | sort -z)
  else
    plan "$origin_abs" "$dest_abs" "$dest"
  fi
done

# Broken links into .tooling/ that no mapping names, in every directory the
# table links into: what a renamed or removed dotdot file leaves behind. Only
# links pointing into dotdot's own core qualify, so nothing else is touched.
# The installer's entry point link is never sync's to touch, broken or not.
planned() {
  local d
  for d in "${P_DEST[@]+"${P_DEST[@]}"}"; do
    [ "$d" != "$1" ] || return 0
  done
  return 1
}
while IFS= read -r -d '' dir; do
  [ -d "$dir" ] && [ ! -L "$dir" ] || continue
  while IFS= read -r -d '' lnk; do
    [ "$lnk" != "$ENTRY_LINK" ] && [ ! -e "$lnk" ] && in_tooling "$(realpath -m -- "$lnk")" && ! planned "$lnk" || continue
    P_ORIGIN+=(""); P_DEST+=("$lnk"); P_LABEL+=("$(dotdot_rel "$lnk")"); P_ACTION+=(prune)
  done < <(find "$dir" -mindepth 1 -maxdepth 1 -type l -print0 | sort -z)
done < <({
  for d in "${P_DEST[@]+"${P_DEST[@]}"}"; do printf '%s\0' "$(dirname -- "$d")"; done
  for d in "${TREE_DIRS[@]+"${TREE_DIRS[@]}"}"; do printf '%s\0' "$d"; done
} | sort -zu)

# --- 2. Preview ---
echo "Preview only; nothing changes unless you answer y below:"
changes=0
if $seed_user; then
  echo "  $DOTDOT_NAME/USER.md ${GREEN}(will create from USER.example.md)${RESET}"
  changes=1
elif [ -e "$user_file" ]; then
  echo "  $DOTDOT_NAME/USER.md ${YELLOW}(existing; will skip)${RESET}"
fi
local_example="$(dotdot_rel "$LOCAL_SETTINGS_EXAMPLE_FILE")"
if $seed_local; then
  echo "  .claude/settings.local.json ${GREEN}(will create from $local_example)${RESET}"
  changes=$((changes + 1))
elif [ ! -f "$LOCAL_SETTINGS_EXAMPLE_FILE" ]; then
  :
elif cmp -s -- "$LOCAL_SETTINGS_EXAMPLE_FILE" "$LOCAL_SETTINGS_FILE"; then
  echo "  .claude/settings.local.json (existing; matches dotdot's example)"
else
  echo "  .claude/settings.local.json ${YELLOW}(existing; will skip — differs from $local_example, merge any new defaults by hand)${RESET}"
fi
for i in "${!P_ACTION[@]}"; do
  case "${P_ACTION[$i]}" in
    link) note="${GREEN}(will link)${RESET}"; changes=$((changes + 1)) ;;
    ok) note="(already linked)" ;;
    move) note="${GREEN}(dotdot link moved; will relink)${RESET}"; changes=$((changes + 1)) ;;
    prune) note="${GREEN}(broken dotdot link; will remove)${RESET}"; changes=$((changes + 1)) ;;
    skip) note="${YELLOW}(existing; will skip)${RESET}" ;;
    relink) note="${RED}(existing; will override)${RESET}"; changes=$((changes + 1)) ;;
    backup) note="${RED}(existing; will back up and override)${RESET}"; changes=$((changes + 1)) ;;
  esac
  echo "  ${P_LABEL[$i]} $note"
done
if [ "$overridable" -gt 0 ]; then
  echo "Run with --override to replace the $overridable existing symlink(s)/file(s) above; files are backed up first."
fi

# --- 3. Confirm ---
if [ "$changes" -eq 0 ]; then
  echo "Nothing to do."
  [ "$failed" -eq 0 ]; exit
fi
# Only a person can confirm: piped or scripted input is refused, so no agent
# or script can approve changes on anyone's behalf — unless the person
# running it already did, with -y.
if $yes; then
  echo "Applying $changes change(s) (-y)."
else
  confirm_or_exit "Apply $changes change(s)?" n "bash dot sync"
fi

# --- 4. Apply ---
# Link targets are relative to the link's own directory, so the links stay
# valid when the project is cloned, moved, or rebuilt in a container.
link() {
  local target="$1" link_path="$2" link_dir
  link_dir="$(dirname -- "$link_path")"
  mkdir -p -- "$link_dir"
  ln -s -- "$(realpath -m --relative-to="$link_dir" -- "$target")" "$link_path"
}

if $seed_user; then
  sed '/^ignore: true$/d' "$USER_EXAMPLE_FILE" > "$user_file"
fi
if $seed_local; then
  mkdir -p -- "$(dirname -- "$LOCAL_SETTINGS_FILE")" \
    && cp -- "$LOCAL_SETTINGS_EXAMPLE_FILE" "$LOCAL_SETTINGS_FILE" \
    || fail "could not create .claude/settings.local.json"
fi

linked=0; unchanged=0; skipped=0; removed=0
warnings=()
stamp=$(date +%Y%m%d-%H%M%S)
for i in "${!P_ACTION[@]}"; do
  origin="${P_ORIGIN[$i]}"; dest="${P_DEST[$i]}"; label="${P_LABEL[$i]}"
  case "${P_ACTION[$i]}" in
    ok) unchanged=$((unchanged + 1)); continue ;;
    skip) skipped=$((skipped + 1)); continue ;;
    prune)
      if rm -f -- "$dest"; then removed=$((removed + 1)); else fail "could not remove $label"; fi
      continue ;;
    move) rm -f -- "$dest" ;;
    relink)
      warnings+=("replaced symlink $label (was -> $(readlink -- "$dest"))")
      rm -f -- "$dest" ;;
    backup)
      mv -- "$dest" "$dest.bak-$stamp"
      warnings+=("backed up $label -> $label.bak-$stamp") ;;
  esac
  if link "$origin" "$dest"; then
    linked=$((linked + 1))
  else
    fail "could not link $label"
  fi
done

echo "Done. $linked linked, $removed broken removed, $unchanged already linked, $skipped skipped, $failed failed."
for w in "${warnings[@]+"${warnings[@]}"}"; do
  printf '%s✓  Overridden:%s %s\n' "$GREEN" "$RESET" "$w" >&2
done
[ "$failed" -eq 0 ]
