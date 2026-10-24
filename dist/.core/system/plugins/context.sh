#!/usr/bin/env bash

dot::use core.system.plugins.manifest framework.helpers.frontmatter framework.helpers.fs

core.system.plugins.context::files() {
  local document
  for document in "$1/$PLUGIN_CONTEXT_DIR"/*.md; do
    [ -f "$document" ] && basename -- "$document"
  done
  return 0
}

core.system.plugins.context::destination() {
  local plugin="$1" file="$2" destination=""
  if [ -f "$PLUGINS_MAP" ]; then
    destination=$(awk -v wanted="$plugin/$file" '
      { sub(/\r$/, "") }
      /^[ \t]*(#|$)/ { next }
      {
        split_at = index($0, ":"); if (split_at == 0) next
        if (substr($0, 1, split_at - 1) == wanted) { print substr($0, split_at + 1); exit }
      }
    ' "$PLUGINS_MAP")
    destination="${destination#"$DOTDOT_NAME"/}"
  fi
  if [ -z "$destination" ]; then
    destination="$file"
    [ -f "$DOTDOT_ROOT/$destination" ] || destination="${file%.md}-${plugin//\//-}.md"
  fi
  [[ "$destination" =~ $PLUGIN_DOCUMENT_PATTERN ]] \
    || { dot::raise "$(dot::relative "$PLUGINS_MAP") maps $plugin/$file to $destination, which is not a top-level .md file."; return 1; }
  printf '%s\n' "$destination"
}

core.system.plugins.context::open() {
  printf '<!-- %s/%s -->' "$1" "${2%.md}"
}

core.system.plugins.context::close() {
  printf '<!-- /%s/%s -->' "$1" "${2%.md}"
}

core.system.plugins.context::state() {
  local document="$1" plugin="$2" file="$3" state
  state=$(awk -v open="$(core.system.plugins.context::open "$plugin" "$file")" -v closer="$(core.system.plugins.context::close "$plugin" "$file")" '
    $0 == open { opens++; if (closes) broken = 1 }
    $0 == closer { closes++; if (!opens) broken = 1 }
    END { if (broken || opens > 1 || closes > 1 || opens != closes) print "broken"; else print (opens ? "region" : "none") }
  ' "$document")
  [ "$state" != broken ] \
    || { dot::raise "$(dot::relative "$document") has stray or doubled $(core.system.plugins.context::open "$plugin" "$file") markers; fix them first."; return 1; }
  printf '%s\n' "$state"
}

core.system.plugins.context::region() {
  local plugin="$1" file="$2" source="$3" description
  description=$(framework.helpers.frontmatter::field "$source" description)
  core.system.plugins.context::open "$plugin" "$file"
  printf '\n'
  [ -z "$description" ] || printf '_%s — %s_\n\n' "$plugin" "$description"
  framework.helpers.frontmatter::body "$source"
  core.system.plugins.context::close "$plugin" "$file"
  printf '\n'
}

core.system.plugins.context::place() {
  local plugin="$1" file="$2" source="$3" workspace="$4" destination path region state description
  destination=$(core.system.plugins.context::destination "$plugin" "$file") || return 1
  path="$DOTDOT_ROOT/$destination"
  region="$workspace/region"
  core.system.plugins.context::region "$plugin" "$file" "$source" > "$region"
  if [ ! -e "$path" ]; then
    description=$(framework.helpers.frontmatter::field "$source" description)
    {
      printf -- '---\nname: %s\ndescription: %s\n---\n\n' "$destination" "${description:-Context from the $plugin plugin.}"
      cat -- "$region"
    } > "$path"
    printf '%s\t%s\tnew file\n' "$file" "$(dot::relative "$path")"
    return 0
  fi
  state=$(core.system.plugins.context::state "$path" "$plugin" "$file") || return 1
  if [ "$state" = region ]; then
    awk -v open="$(core.system.plugins.context::open "$plugin" "$file")" -v closer="$(core.system.plugins.context::close "$plugin" "$file")" -v source="$region" '
      $0 == open { while ((getline line < source) > 0) print line; skip = 1; next }
      skip { if ($0 == closer) skip = 0; next }
      { print }
    ' "$path" | framework.helpers.fs::replace "$path"
    printf '%s\t%s\tregion replaced\n' "$file" "$(dot::relative "$path")"
    return 0
  fi
  { [ ! -s "$path" ] || [ -z "$(tail -n 1 -- "$path")" ] || printf '\n'; cat -- "$region"; } >> "$path"
  printf '%s\t%s\tregion appended\n' "$file" "$(dot::relative "$path")"
}

core.system.plugins.context::place_all() {
  local plugin="$1" source="$2" workspace="$3" file
  while IFS= read -r file; do
    core.system.plugins.context::place "$plugin" "$file" "$source/$PLUGIN_CONTEXT_DIR/$file" "$workspace" || return 1
  done < <(core.system.plugins.context::files "$source")
}

core.system.plugins.context::places() {
  local plugin="$1" source="$2" file
  while IFS= read -r file; do
    printf '%s|%s\n' "$(core.system.plugins.context::destination "$plugin" "$file")" "$file"
  done < <(core.system.plugins.context::files "$source")
}

core.system.plugins.context::strip() {
  local plugin="$1" path kept
  shift
  kept=" $* "
  for path in "$DOTDOT_ROOT"/*.md; do
    [ -f "$path" ] && grep -q -- "^<!-- $plugin/" "$path" || continue
    awk -v plugin="$plugin" -v kept="$kept" -v document="$(basename -- "$path")" '
      function flush() { while (blanks > 0) { print ""; blanks-- } }
      !skip && index($0, "<!-- " plugin "/") == 1 && $0 ~ / -->$/ {
        name = substr($0, length(plugin) + 7); sub(/ -->$/, "", name)
        if (index(kept, " " document "|" name ".md ") == 0) { skip = 1; closer = "<!-- /" plugin "/" name " -->"; blanks = 0; next }
      }
      skip { if ($0 == closer) skip = 0; next }
      /^[ \t]*$/ { blanks++; next }
      { flush(); print }
      END { flush() }
    ' "$path" | framework.helpers.fs::replace "$path"
    if [ -z "$(framework.helpers.frontmatter::body "$path" | tr -d '[:space:]')" ]; then
      rm -f -- "$path"
      dot::relative "$path"
    fi
  done
}
