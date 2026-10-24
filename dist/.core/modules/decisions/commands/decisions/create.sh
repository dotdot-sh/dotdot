#!/usr/bin/env bash

DESCRIPTION="Create a new decision from the decision template."

dot::use framework.console.args core.modules.decisions.console core.modules.decisions.service framework.helpers.fs framework.console.output framework.helpers.template framework.helpers.text

usage() {
  local status heading key
  cat <<EOF
bash dot decisions:create — create a new decision in Decisions/ from the
bundled decision template, numbering and naming it automatically.

The template ($(dot::relative "$DECISION_TEMPLATE")) is the
single source of truth: this command reads it at run time and derives one flag
per section from its headings, plus the status vocabulary from its frontmatter,
so editing the template is all it takes. It also scans Decisions/ for
the highest existing number and takes the next one — which is why the filename
and number are never to be constructed by hand.

Usage:
  bash dot decisions:create --name <text> --statement <text> --elaboration <text> [<status flag>] [<section flags>]...
  bash dot decisions:create --help

This command only creates. To change a decision's status afterwards, use
bash dot decisions:update; to change its prose, edit the file directly, keeping its
number and bumping the frontmatter "modified" stamp.

Required:
  --name <text>          Short name for the filename slug (e.g. "JWT in httpOnly cookie").
                         Not the rule itself — that is --statement.
  --statement <text>     The decision as a first-person rule. Becomes the H1 and,
                         verbatim, the frontmatter description — so write it to stand
                         alone: someone reading only that line must be able to obey it.
                         E.g. "We store the session JWT in an httpOnly cookie so that ..."
  --elaboration <text>   The single plain paragraph under the H1: what must happen,
                         to whom, and what outcomes and side effects exist.

Status flags (one per run; default $DECISION_DEFAULT_STATUS):
EOF
  while IFS= read -r status; do
    printf '  --%-24s mark the decision %s\n' "$status" "$status"
  done < <(core.modules.decisions.service::statuses)
  cat <<EOF
  --$DECISION_SUPERSEDED_FLAG <ref>        record it as already replaced by another decision.
                            The status string is built here and <ref> is checked
                            to exist, so the link cannot be typed wrong.

Section flags (derived live from $(basename -- "$DECISION_TEMPLATE")):
EOF
  while IFS= read -r heading; do
    key=$(framework.helpers.template::key "$heading")
    case "$(core.modules.decisions.service::kind "$key")" in
      decision | feature)
        printf '  --%-24s %s\n' "$key" "$heading"
        printf '  %-26s Repeatable, one %s reference each: "2", "002", or the\n' "" "$(core.modules.decisions.service::kind "$key")"
        printf '  %-26s file name. The link is built for you and the reference is\n' ""
        printf '  %-26s checked to exist.\n' ""
        ;;
      *)
        printf '  --%-24s %s — repeatable, one line per use.\n' "$key" "$heading"
        ;;
    esac
  done < <(framework.helpers.template::headings "$DECISION_TEMPLATE")
  cat <<EOF

Examples:
  bash dot decisions:create \\
    --name "JWT in httpOnly cookie" \\
    --statement "We store the session JWT in an httpOnly cookie so that a XSS foothold cannot read it." \\
    --elaboration "Every authenticated response sets the token as an httpOnly, Secure, SameSite=Lax cookie ..." \\
    --accepted \\
    --influenced-by 002 \\
    --impacts 7

Which sections take references and which take prose is read from the template's
placeholders, not their names — so renaming a heading changes only the flag
name, and the link checking follows it.
EOF
}

handle() {
  local name="" statement="" has_name=false has_statement=false has_elaboration=false
  local status="$DECISION_DEFAULT_STATUS" status_flag="" superseder="" sections_dir key kind link slug path
  [ -f "$DECISION_TEMPLATE" ] || framework.console.output::fail "Template not found: $(dot::relative "$DECISION_TEMPLATE")"
  [ $# -gt 0 ] || framework.console.args::invalid "Missing --name, --statement, and --elaboration."
  framework.helpers.fs::make_temp_dir sections_dir || framework.console.output::fail "Could not create a temp directory."
  while [ $# -gt 0 ]; do
    case "$1" in
      --name) framework.console.args::require_value "$@"; name="$2"; has_name=true; shift 2 ;;
      --statement) framework.console.args::require_value "$@"; statement="$2"; has_statement=true; shift 2 ;;
      --elaboration) framework.console.args::require_value "$@"; printf '%s' "$2" > "$sections_dir/.elaboration"; has_elaboration=true; shift 2 ;;
      "--$DECISION_SUPERSEDED_FLAG")
        [ $# -ge 2 ] || framework.console.args::invalid "--$DECISION_SUPERSEDED_FLAG requires the decision that replaces this one (e.g. --$DECISION_SUPERSEDED_FLAG 007)."
        status_flag=$(core.modules.decisions.console::choose_status "$status_flag" "$DECISION_SUPERSEDED_FLAG")
        superseder="$2"
        shift 2
        ;;
      --*)
        key="${1#--}"
        if core.modules.decisions.service::is_status "$key"; then
          status_flag=$(core.modules.decisions.console::choose_status "$status_flag" "$key")
          status="$key"
          shift
          continue
        fi
        framework.helpers.template::has_key "$DECISION_TEMPLATE" "$key" || framework.console.args::invalid "Unknown flag --$key."
        framework.console.args::require_value "$@"
        kind=$(core.modules.decisions.service::kind "$key")
        if [ "$kind" = text ]; then
          core.modules.decisions.service::append_section "$sections_dir/$key" "$2"
        else
          link=$(core.modules.decisions.service::reference_link "$kind" "$2") || framework.console.args::invalid "--$key '$2' matches no $kind in dotdot."
          core.modules.decisions.service::append_section "$sections_dir/$key" "$link"
        fi
        shift 2
        ;;
      *) framework.console.args::unexpected "$1" ;;
    esac
  done
  $has_name || framework.console.args::invalid "Missing required --name."
  $has_statement || framework.console.args::invalid "Missing required --statement."
  $has_elaboration || framework.console.args::invalid "Missing required --elaboration."
  if [ "$status_flag" = "$DECISION_SUPERSEDED_FLAG" ]; then
    status=$(core.modules.decisions.service::superseded_status "$superseder") \
      || framework.console.args::invalid "--$DECISION_SUPERSEDED_FLAG '$superseder' matches no decision in Decisions/."
  fi
  slug=$(framework.helpers.text::slug "$name")
  [ -n "$slug" ] || framework.console.args::invalid "--name must contain at least one letter or number."
  path=$(core.modules.decisions.service::create "$slug" "$status" "$statement" "$sections_dir") || framework.console.output::fail "Could not create the decision; try again."
  framework.console.output::success "Decision $(framework.helpers.record::number "$(basename -- "$path")") documented"
  framework.console.output::detail "$(dot::relative "$path")"
}
