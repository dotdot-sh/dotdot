#!/usr/bin/env bash

DESCRIPTION="Create a new feature from the feature template."

dot::use framework.console.args core.modules.features.service framework.helpers.fs framework.console.output framework.helpers.template framework.helpers.text

usage() {
  local heading key
  cat <<EOF
bash dot features:create — create a new feature file in Features/ from the
bundled feature template, numbering and naming it automatically.

The template ($(dot::relative "$FEATURE_TEMPLATE")) is the
single source of truth: this command reads it at run time and derives one
flag per section from its headings, so adding a section there makes the flag
appear here with nothing to keep in sync by hand. It also scans
Features/ for the highest existing number and takes the next one —
which is why the filename and number are never to be constructed by hand.

Usage:
  bash dot features:create --name <text> --description <text> [section flags...]
  bash dot features:create --help

All flags except --name and --description are optional; sections left unset
are written as "None", the convention for a section with nothing relevant in
it. This command only creates — to change an existing feature, edit its file
directly, preserving its frontmatter name and number.

Required:
  --name <text>          Feature name/title — becomes the file's slug and frontmatter name.
  --description <text>   One-line summary — used as the frontmatter description and the Description section.

Section flags (derived live from $(basename -- "$FEATURE_TEMPLATE")):
EOF
  while IFS= read -r heading; do
    key=$(framework.helpers.template::key "$heading")
    [ "$key" != "$FEATURE_DESCRIPTION_KEY" ] || continue
    printf '  --%-28s %s\n' "$key" "$heading"
  done < <(framework.helpers.template::headings "$FEATURE_TEMPLATE")
  cat <<EOF

Examples:
  bash dot features:create \\
    --name "Password reset" \\
    --description "Lets a user reset a forgotten password via an emailed link." \\
    --specification "Given a registered user ... When ... Then ..." \\
    --related-features "7"
EOF
}

handle() {
  local name="" has_name=false sections_dir key slug path
  [ -f "$FEATURE_TEMPLATE" ] || framework.console.output::fail "Template not found: $(dot::relative "$FEATURE_TEMPLATE")"
  [ $# -gt 0 ] || framework.console.args::invalid "Missing --name and --description."
  framework.helpers.fs::make_temp_dir sections_dir || framework.console.output::fail "Could not create a temp directory."
  while [ $# -gt 0 ]; do
    case "$1" in
      --name) framework.console.args::require_value "$@"; name="$2"; has_name=true; shift 2 ;;
      --*)
        key="${1#--}"
        framework.helpers.template::has_key "$FEATURE_TEMPLATE" "$key" || framework.console.args::invalid "Unknown flag --$key."
        framework.console.args::require_value "$@"
        printf '%s' "$2" > "$sections_dir/$key"
        shift 2
        ;;
      *) framework.console.args::unexpected "$1" ;;
    esac
  done
  $has_name || framework.console.args::invalid "Missing required --name."
  [ -e "$sections_dir/$FEATURE_DESCRIPTION_KEY" ] || framework.console.args::invalid "Missing required --$FEATURE_DESCRIPTION_KEY."
  slug=$(framework.helpers.text::slug "$name")
  [ -n "$slug" ] || framework.console.args::invalid "--name must contain at least one letter or number."
  path=$(core.modules.features.service::create "$slug" "$sections_dir") || framework.console.output::fail "Could not create the feature; try again."
  framework.console.output::success "Feature $(framework.helpers.record::number "$(basename -- "$path")") documented"
  framework.console.output::detail "$(dot::relative "$path")"
}
