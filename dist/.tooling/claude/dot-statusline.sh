#!/bin/bash
input=$(cat)

# Exports TZ from the user's timezone, so reset times print in it.
. "$(dirname "$(realpath "$0")")/../bin/lib/dot-paths.sh"

# ── Helpers ──────────────────────────────────────────────────────────────
YELLOW=$'\033[33m'
RED=$'\033[31m'
RESET=$'\033[0m'

# JSON field as text, control chars stripped so it can't inject escapes.
get() { printf '%s' "$input" | jq -r "$1 // empty" | LC_ALL=C tr -d '[:cntrl:]'; }

# Rounded non-negative integer, 0 for anything else.
int() {
  local n
  n=$(printf '%.0f' "${1:-0}" 2>/dev/null)
  case "$n" in '' | *[!0-9]*) echo 0 ;; *) echo "$n" ;; esac
}

# Wrap a value in a color. Usage: paint COLOR VALUE
paint() { if [ -n "$1" ] && [ -n "$2" ]; then printf '%s%s%s' "$1" "$2" "$RESET"; else printf '%s' "$2"; fi; }

# Color for a percentage. Usage: pct_color PCT [MID=70] [HIGH=90]
pct_color() {
  if (($1 >= ${3:-90})); then echo "$RED"; elif (($1 >= ${2:-70})); then echo "$YELLOW"; fi
}

# Format a unix epoch in local time. Usage: fmt_time EPOCH FORMAT
fmt_time() {
  (($1 > 0)) || return
  LC_ALL=C date -d "@$1" +"$2" 2>/dev/null || LC_ALL=C date -r "$1" +"$2"
}

# ── Variables ────────────────────────────────────────────────────────────
CUR=$(get .workspace.current_dir)
ROOT=$(get .workspace.project_dir)
ROOT="${ROOT:-${CLAUDE_PROJECT_DIR-}}"
if [ -z "$ROOT" ] || [ -z "$CUR" ] || [ "$CUR" = "$ROOT" ]; then
  REL=$(basename -- "${ROOT:-${CUR:-.}}")
  ICON="📡"
elif [ "${CUR#"$ROOT"/}" != "$CUR" ]; then
  # Prefix comparison, not a case glob: "*", "?" or "[" in a path would match too much
  REL="$(basename -- "$ROOT")/${CUR#"$ROOT"/}"
  ICON="⚠️"
else
  REL="$CUR"
  ICON="⚠️"
fi
WORKTREE=$(get .worktree.branch)
if [ -n "$WORKTREE" ]; then CWD=$(paint $'\033[34m' "🌳 $WORKTREE"); else CWD=$(paint $'\033[34m' "$ICON $REL/"); fi

# No context data yet (fresh session) means nothing used, not everything.
REMAINING=$(get .context_window.remaining_percentage)
REMAINING=$(int "${REMAINING:-100}")
CONTEXT_PCT=$((REMAINING > 100 ? 0 : 100 - REMAINING))
CONTEXT=$(paint "$(pct_color "$CONTEXT_PCT" 60 80)" "$CONTEXT_PCT%")

MODEL_NAME=$(get .model.display_name)
AGENT=$(get .agent.name)
MODEL="${MODEL_NAME:-Unknown}${AGENT:+:$AGENT}"

THINKING=$(get .effort.level)
case "$THINKING" in
  max) THINKING=$(paint "$RED" "$THINKING") ;;
  xhigh) THINKING=$(paint "$YELLOW" "$THINKING") ;;
esac

OUTPUT=$(get .output_style.name)
[ "$(printf '%s' "$OUTPUT" | tr '[:upper:]' '[:lower:]')" = "concise" ] || OUTPUT=$(paint "$YELLOW" "$OUTPUT")

SESSION_PCT=$(int "$(get .rate_limits.five_hour.used_percentage)")
SESSION_USED=$(paint "$(pct_color "$SESSION_PCT")" "$SESSION_PCT%")
SESSION_RESET=$(fmt_time "$(int "$(get .rate_limits.five_hour.resets_at)")" '%H:%M')

WEEK_PCT=$(int "$(get .rate_limits.seven_day.used_percentage)")
WEEK_USED=$(paint "$(pct_color "$WEEK_PCT")" "$WEEK_PCT%")
WEEK_EPOCH=$(int "$(get .rate_limits.seven_day.resets_at)")
WEEK_RESET="$(fmt_time "$WEEK_EPOCH" '%a' | cut -c1-2) $(fmt_time "$WEEK_EPOCH" '%H:%M')"

TOKENS=$(($(int "$(get .context_window.current_usage.input_tokens)") + $(int "$(get .context_window.current_usage.output_tokens)")))

COST=$(LC_ALL=C printf '$%.2f' "$(get .cost.total_cost_usd)" 2>/dev/null)

# ── Output ───────────────────────────────────────────────────────────────
printf '%s\n' "$CWD ($CONTEXT) $MODEL $THINKING $OUTPUT ($SESSION_USED - $SESSION_RESET) ($WEEK_USED - $WEEK_RESET) (${TOKENS}t @ $COST)"
