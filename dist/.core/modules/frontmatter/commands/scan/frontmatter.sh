#!/usr/bin/env bash

DESCRIPTION="Print only the frontmatter of dotdot Markdown docs."

dot::use framework.console.args framework.helpers.frontmatter framework.helpers.fs framework.console.output

SCAN_MISSING_FRONTMATTER="(no frontmatter)"

usage() {
  cat <<'EOF'
bash dot scan:frontmatter — print each *.md file's frontmatter block verbatim,
one file at a time, without the rest of the body.

Lets a skill or agent survey a directory of dotdot *.md-style files (e.g.
Features/, Decisions/) cheaply — enough to judge relevance or
spot duplicates without spending context on the full bodies. Read a file in
full only once its frontmatter says it's worth it.

Dumps whatever fields a file actually declares rather than picking out a
fixed set, so files with extra keys (ignore, status, tags, ...) survey
just as well as ones with only name/description.

Usage:
  bash dot scan:frontmatter <directory|file.md>
  bash dot scan:frontmatter --help

Arguments:
  <directory>   Scan every *.md directly inside it, separated by a rule.
  <file.md>     Scan just that one file.

Notes:
  - A relative path is dotdot-relative, so "Features" and
    ".dot/Features" mean the same thing from any working directory.
    A path that resolves outside dotdot is rejected, not scanned.
  - Output paths are printed dotdot-relative, ready to pass to another tool.
  - A file with no frontmatter is reported as "(no frontmatter)" rather than
    skipped, which is how you spot docs still missing one.
EOF
}

print_frontmatter() {
  local file="$1" label="$2"
  framework.console.output::line "$label"
  if framework.helpers.frontmatter::exists "$file"; then
    framework.helpers.frontmatter::block "$file"
  else
    framework.console.output::line "$SCAN_MISSING_FRONTMATTER"
  fi
}

scan_directory() {
  local directory="$1" label="$2" file found=false
  for file in "$directory"/*.md; do
    [ -e "$file" ] || continue
    if ! framework.helpers.fs::within "$file" "$DOTDOT_ROOT" >/dev/null; then
      framework.console.output::error "Skipped, resolves outside dotdot: $label/$(basename -- "$file")"
      continue
    fi
    ! $found || framework.console.output::rule
    found=true
    print_frontmatter "$file" "$label/$(basename -- "$file")"
  done
  $found || framework.console.output::line "(no .md files in $label)"
}

handle() {
  local label target
  [ $# -eq 1 ] || framework.console.args::invalid "Give one directory or Markdown file."
  label="$1"
  while [ "${label%/}" != "$label" ] && [ "$label" != "/" ]; do
    label="${label%/}"
  done
  target=$(framework.helpers.fs::within "$(paths::in_dotdot "$label")" "$DOTDOT_ROOT") \
    || framework.console.output::fail "Path resolves outside the dotdot directory: $label"
  if [ -d "$target" ]; then
    scan_directory "$target" "$label"
  elif [ -f "$target" ]; then
    case "$label" in
      *.md) print_frontmatter "$target" "$label" ;;
      *) framework.console.output::fail "Not a Markdown file: $label" ;;
    esac
  else
    framework.console.output::fail "Not a directory or Markdown file: $label"
  fi
}
