#!/usr/bin/env bash
# dot-paths.sh — dotdot's single source of truth for where things live.
#
# dotdot always sits in one directory inside the project it serves, both when
# applied to a real project and when developed in its own repo. That makes the
# two anchors below unconditional — there is no "dev mode" to detect and nothing to configure:
#
#   DOTDOT_ROOT     dotdot itself (.dot)
#   TOOLING_DIR  dotdot's tooling directory, found by walking up from the script
#   BASE         the project dotdot serves — always dotdot's parent
#
# plus every other location the scripts use (see "declared once" below).
#
# Sourcing it also exports TZ from the user's timezone (see dotdot_timezone).
#
# Source it from a script in .dot/.tooling/bin before using them:
#   . "$(dirname "$0")/lib/dot-paths.sh"
#
# Paths inside dotdot are built from $DOTDOT_ROOT, paths in the host project
# from $BASE. Relative arguments a user or skill passes in are resolved with
# dotdot_path(), so they read the same whatever the caller's working directory.

# Resolve $0 through any symlinks so the anchors hold even when a script is
# invoked through one. Directory symlinks are handled by "cd -P" below.
#
# The hop count is capped: a symlink cycle would otherwise spin here forever,
# hanging every script that sources this file rather than failing.
_dotdot_self="$0"
_dotdot_hops=0
while [ -L "$_dotdot_self" ]; do
  _dotdot_hops=$((_dotdot_hops + 1))
  if [ "$_dotdot_hops" -gt 40 ]; then
    echo "❌ too many levels of symbolic links resolving $0" >&2
    return 1 2>/dev/null || exit 1
  fi
  _dotdot_link=$(readlink "$_dotdot_self")
  case "$_dotdot_link" in
    /*) _dotdot_self="$_dotdot_link" ;;
    *) _dotdot_self="$(dirname "$_dotdot_self")/$_dotdot_link" ;;
  esac
done
unset _dotdot_hops

SCRIPT_DIR=$(CDPATH= cd -P -- "$(dirname -- "$_dotdot_self")" && pwd)
unset _dotdot_self _dotdot_link

# Every script, the dotdot entry point included, lives under the tooling
# directory, so dotdot is found by walking up to it rather than by counting
# levels: moving a script inside the tooling directory changes nothing here.
TOOLING_NAME=".tooling"
_dotdot_dir=$SCRIPT_DIR
while [ "$(basename -- "$_dotdot_dir")" != "$TOOLING_NAME" ]; do
  if [ "$_dotdot_dir" = "/" ]; then
    echo "❌ no $TOOLING_NAME directory above $SCRIPT_DIR" >&2
    return 1 2>/dev/null || exit 1
  fi
  _dotdot_dir=$(dirname -- "$_dotdot_dir")
done
TOOLING_DIR=$_dotdot_dir
DOTDOT_ROOT=$(dirname -- "$TOOLING_DIR")
BASE=$(CDPATH= cd -P -- "$DOTDOT_ROOT/.." && pwd)
DOTDOT_NAME=$(basename -- "$DOTDOT_ROOT")
unset _dotdot_dir

# Every location a script needs, declared once. Nothing else in dotdot spells
# these paths out.
BIN_DIR="$TOOLING_DIR/bin"
SKILLS_DIR="$TOOLING_DIR/skills"
AGENTS_DIR="$TOOLING_DIR/agents"
CLAUDE_DIR="$TOOLING_DIR/claude"
DECISIONS_DIR="$DOTDOT_ROOT/Decisions"
FEATURES_DIR="$DOTDOT_ROOT/Features"
NOTES_DIR="$DOTDOT_ROOT/Notes"
IDEAS_DIR="$DOTDOT_ROOT/Ideas"
DECISION_TEMPLATE="$SKILLS_DIR/dot-document-decision/decision-template.md"
FEATURE_TEMPLATE="$SKILLS_DIR/dot-document-feature/feature-template.md"
USER_FILE="$DOTDOT_ROOT/USER.md"
USER_EXAMPLE_FILE="$DOTDOT_ROOT/USER.example.md"
LOCAL_SETTINGS_FILE="$BASE/.claude/settings.local.json"
LOCAL_SETTINGS_EXAMPLE_FILE="$CLAUDE_DIR/example.settings.local.json"
SCHEMA_FILE="$DOTDOT_ROOT/SCHEMA.md"
TASKS_DIR="$DOTDOT_ROOT/Tasks"
TASK_TEMPLATE="$SKILLS_DIR/dot-document-task/task-template.md"
TASK_SERVICES_DIR="$BIN_DIR/task"
CONF_DIR="$TOOLING_DIR/conf"
TASKS_CONF="$CONF_DIR/tasks.conf"
VERSION_FILE="$CONF_DIR/version"
READY_FILE="$CONF_DIR/ready"
KITS_DIR="$TOOLING_DIR/kits"
KITS_LOCK="$CONF_DIR/kits.lock"
KITS_MAP="$CONF_DIR/kitsmap.conf"
KIT_API_FILE="$CONF_DIR/kit-api"
DOTDOT_REPO_URL="https://github.com/dotdot-sh/dotdot.git"
DOTDOT_REPO_REF="main"
DOTDOT_REPO_SOURCE="dist"
KITS_REGISTRY="dotdot-sh/dotdot-kits"
KITS_REGISTRY_REF="main"
KITS_REGISTRY_INDEX="kits"
ENV_FILE="$DOTDOT_ROOT/.env"
RELEASE_CONF="$BASE/release.conf"
RELEASE_TOKEN_CACHE="$HOME/.cache/dotdot-release/socket"
ENTRY_LINK="$BASE/dot"

# Prints a dotdot path relative to the project ($BASE), for messages and for
# anything handed to a tool that runs from the project root.
dotdot_rel() {
  case "$1" in
    "$BASE"/*) printf '%s\n' "${1#"$BASE"/}" ;;
    *) printf '%s\n' "$1" ;;
  esac
}

# Prints a dotdot path relative to dotdot ($DOTDOT_ROOT).
dotdot_inner() {
  case "$1" in
    "$DOTDOT_ROOT"/*) printf '%s\n' "${1#"$DOTDOT_ROOT"/}" ;;
    *) printf '%s\n' "$1" ;;
  esac
}

# Prints an absolute path for a dotdot path. Absolute input is passed through;
# relative input resolves against $DOTDOT_ROOT rather than the caller's working
# directory, so "Features" means the same thing from anywhere.
#
# Skills and docs spell these paths from the project root (".dot/Features"),
# while dotdot's own files spell them bare ("Features").
# Both are accepted: a leading dotdot directory name is stripped first.
#
# This only spells a path — it does not confine one. Anything that came from
# a caller has to go through resolve_within() below before it is opened.
dotdot_path() {
  _kp_rel="$1"
  case "$_kp_rel" in
    /*) printf '%s\n' "$_kp_rel"; return ;;
    "$(basename "$DOTDOT_ROOT")") _kp_rel="." ;;
    "$(basename "$DOTDOT_ROOT")"/*) _kp_rel="${_kp_rel#*/}" ;;
  esac
  printf '%s\n' "$DOTDOT_ROOT/$_kp_rel"
}

# Prints $1 as an absolute, fully resolved path taken relative to the anchor
# directory $2, or fails if the result lands outside that anchor. An absolute
# $1 is checked like any other, never trusted.
#
# Every path that reaches a script from outside it — a --dir flag, a scan
# target, an argument a skill assembled from a document — belongs here first.
# Without it "../.." walks straight out of the project, which dotdot's rules
# forbid, and a symlink inside the project does the same more quietly. The
# whole path is resolved, final component included, so neither route survives.
#
# The containment test is a prefix comparison rather than a `case` glob: an
# anchor holding "*", "?" or "[" would be read as a pattern there, and a path
# that merely looks like the anchor would be waved through.
resolve_within() {
  _rw_rel="$1"
  _rw_anchor="$2"
  case "$_rw_rel" in
    /*) _rw_abs="$_rw_rel" ;;
    *) _rw_abs="$_rw_anchor/$_rw_rel" ;;
  esac
  _rw_abs=$(realpath -m -- "$_rw_abs") || return 1
  if [ "$_rw_abs" != "$_rw_anchor" ] &&
     [ "${_rw_abs#"$_rw_anchor"/}" = "$_rw_abs" ]; then
    return 1
  fi
  printf '%s\n' "$_rw_abs"
}

# Exports TZ from "timezone:" in USER.md's frontmatter, so every time a dotdot
# script prints follows the user's zone rather than the machine's. An IANA
# name ("Europe/Berlin") tracks daylight saving; "UTC+2" is a fixed offset in
# whole hours. Missing or unknown values leave the system timezone untouched.
dotdot_timezone() {
  _tz=$(awk '
    NR == 1 && $0 == "---" { infm = 1; next }
    infm && $0 == "---" { exit }
    infm && /^timezone:/ {
      sub(/^timezone:[ \t]*/, ""); sub(/[ \t]*#.*$/, ""); gsub(/["\047 \t]/, "")
      print; exit
    }
  ' "$DOTDOT_ROOT/USER.md" 2>/dev/null || true)
  [ -n "$_tz" ] || return 0
  # POSIX TZ inverts the offset sign: UTC+2 is Etc/GMT-2.
  case "$_tz" in
    UTC+[0-9] | UTC+1[0-4]) _tz="Etc/GMT-${_tz#UTC+}" ;;
    UTC-[0-9] | UTC-1[0-2]) _tz="Etc/GMT+${_tz#UTC-}" ;;
  esac
  # Only a real zoneinfo name reaches TZ, never a path or a POSIX rule string.
  if printf '%s' "$_tz" | grep -Eq '^[A-Za-z][A-Za-z0-9_+-]*(/[A-Za-z0-9_+-]+)*$' &&
     [ -f "/usr/share/zoneinfo/$_tz" ]; then
    export TZ="$_tz"
  else
    echo "⚠️ ignoring unknown timezone in USER.md: $_tz" >&2
  fi
}
dotdot_timezone
