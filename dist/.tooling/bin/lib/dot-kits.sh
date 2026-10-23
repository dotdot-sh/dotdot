#!/usr/bin/env bash
# dot-kits.sh — kits: fetching, checking, and placing them.
#
# A kit is a GitHub repo with a kit.conf and any of context/, skills/,
# agents/, bin/, and claude/. Its tools are copied to .tooling/kits/<kit>/; its
# context is never copied there, only placed in dotdot's top-level docs: as a
# region between "<!-- <kit>/<File> -->" markers in an existing doc, or as a
# new "<File>-<kit>.md". kitsmap.conf ("<kit>/<File>.md:<Dest>.md" lines)
# overrides where a context file goes.
#
# The lock holds one "<kit>=<url> <ref> <commit>" line per installed kit.
#
# Source it after lib/dot-paths.sh, lib/dot-kv.sh, and lib/dot-github.sh.

KIT_NAME_PATTERN='^[a-z][a-z0-9]*$'
KIT_DOC_PATTERN='^[A-Za-z0-9][A-Za-z0-9._-]*\.md$'
KIT_SCRIPT_PATTERN='^dot-[a-z][a-z0-9-]*\.sh$'
KIT_DEFAULT_REF="main"
KIT_CONF_NAME="kit.conf"
KIT_CONTEXT_DIR="context"
KIT_TOOL_DIRS=(skills agents bin claude)
KIT_CLAUDE_SETTINGS="claude/settings.local.json"
KIT_RESERVED_GROUPS=(help list)

# Prints the core command groups ("task", "decision", …), which no kit may take.
kit_core_groups() {
  local file base
  for file in "$BIN_DIR"/dot-*.sh; do
    base=$(basename -- "$file" .sh)
    base=${base#dot-}
    printf '%s\n' "${base%%-*}"
  done
  printf '%s\n' "${KIT_RESERVED_GROUPS[@]}"
}

# True when $1 is a usable kit name: lowercase letters and digits, no core group.
kit_name_valid() {
  [[ "$1" =~ $KIT_NAME_PATTERN ]] || return 1
  ! kit_core_groups | grep -xF -- "$1" >/dev/null
}

kit_api() {
  tr -d '[:space:]' < "$KIT_API_FILE"
}

# Prints the installed kit names, one per line.
kit_installed() {
  [ -f "$KITS_LOCK" ] || return 0
  awk -F= '/^[a-z][a-z0-9]*=/ { print $1 }' "$KITS_LOCK"
}

# Prints the lock entry of kit $1 ("<url> <ref> <commit>"), or fails.
kit_lock_get() {
  kv_get "$KITS_LOCK" "$1"
}

kit_lock_set() {
  kv_set "$KITS_LOCK" "$1" "$2"
}

kit_lock_delete() {
  [ -f "$KITS_LOCK" ] || return 0
  local tmp="$KITS_LOCK.tmp-$$"
  awk -v k="$1" 'index($0, k "=") != 1' "$KITS_LOCK" > "$tmp" && mv -f -- "$tmp" "$KITS_LOCK"
}

# Prints the repo URL the registry lists for kit name $1, or fails.
kit_registry_url() {
  local index="$KIT_TMP/registry"
  github_file "$KITS_REGISTRY" "$KITS_REGISTRY_REF" "$KITS_REGISTRY_INDEX" "$index" 2>/dev/null \
    || { echo "❌ Could not read the kit registry ($KITS_REGISTRY)." >&2; return 1; }
  kv_get "$index" "$1" || { echo "❌ No kit named $1 in the registry ($KITS_REGISTRY)." >&2; return 1; }
}

# Downloads and unpacks the kit named by $1 ("name", "owner/repo", or a
# github.com URL, each optionally "@ref") into $KIT_TMP. Sets KIT_URL,
# KIT_REF, KIT_COMMIT, and KIT_SRC (the unpacked kit's root).
kit_fetch() {
  local source=${1%@*} repo top
  KIT_REF=$KIT_DEFAULT_REF
  [ "$source" = "$1" ] || KIT_REF=${1##*@}
  github_ref_valid "$KIT_REF" || { echo "❌ Invalid ref: $KIT_REF" >&2; return 1; }
  if [[ "$source" == */* ]]; then
    KIT_URL=$source
  else
    kit_name_valid "$source" || { echo "❌ Invalid kit name: $source" >&2; return 1; }
    KIT_URL=$(kit_registry_url "$source") || return 1
  fi
  repo=$(github_repo "$KIT_URL") || { echo "❌ Not a GitHub repo: $KIT_URL" >&2; return 1; }
  KIT_URL="$GITHUB_HOST_URL$repo"
  echo "Downloading $repo@$KIT_REF…"
  github_tarball "$repo" "$KIT_REF" "$KIT_TMP/kit.tar.gz" \
    || { echo "❌ Could not download $repo@$KIT_REF (private? log in with gh auth login or set GH_TOKEN in $(dotdot_rel "$ENV_FILE"))." >&2; return 1; }
  KIT_COMMIT=$(github_tarball_commit "$KIT_TMP/kit.tar.gz")
  mkdir -p -- "$KIT_TMP/tree"
  tar -xzf "$KIT_TMP/kit.tar.gz" -C "$KIT_TMP/tree" || { echo "❌ Could not unpack $repo@$KIT_REF." >&2; return 1; }
  top=$(find "$KIT_TMP/tree" -mindepth 1 -maxdepth 1 -type d | head -n 1)
  [ -n "$top" ] && [ -f "$top/$KIT_CONF_NAME" ] || { echo "❌ $repo has no $KIT_CONF_NAME at its root." >&2; return 1; }
  KIT_SRC=$top
}

# Checks the unpacked kit at $1 against the kit contract; prints its name.
kit_validate() {
  local src="$1" name requires entry base
  name=$(kv_get "$src/$KIT_CONF_NAME" KIT_NAME) || { echo "❌ KIT_NAME is missing in $KIT_CONF_NAME." >&2; return 1; }
  kit_name_valid "$name" || { echo "❌ Unusable KIT_NAME: $name (lowercase letters and digits, not a core command)." >&2; return 1; }
  requires=$(kv_get "$src/$KIT_CONF_NAME" REQUIRES) || { echo "❌ REQUIRES is missing in $KIT_CONF_NAME." >&2; return 1; }
  [ "$requires" = "$(kit_api)" ] \
    || { echo "❌ $name needs kit API $requires; this dotdot has $(kit_api). Update the kit or dotdot." >&2; return 1; }
  [ -z "$(find "$src" -type l -print -quit)" ] || { echo "❌ $name holds symlinks." >&2; return 1; }
  for entry in "$src/skills"/* "$src/agents"/*; do
    [ -e "$entry" ] || continue
    base=$(basename -- "$entry")
    [[ "$base" == "$name"-* ]] || { echo "❌ $base must be prefixed $name-." >&2; return 1; }
  done
  for entry in "$src/bin"/*; do
    [ -e "$entry" ] || continue
    base=$(basename -- "$entry")
    [ -d "$entry" ] && [ "$base" = lib ] && continue
    [[ "$base" =~ $KIT_SCRIPT_PATTERN ]] || { echo "❌ bin/$base must be named dot-<command>.sh." >&2; return 1; }
  done
  for entry in "$src/$KIT_CONTEXT_DIR"/*; do
    [ -e "$entry" ] || continue
    base=$(basename -- "$entry")
    [ -f "$entry" ] && [[ "$base" =~ $KIT_DOC_PATTERN ]] || { echo "❌ $KIT_CONTEXT_DIR/$base must be a .md file." >&2; return 1; }
  done
  printf '%s\n' "$name"
}

# Prints where context file $2 of kit $1 goes, relative to dotdot's root.
kit_context_dest() {
  local kit="$1" file="$2" dest=""
  if [ -f "$KITS_MAP" ]; then
    dest=$(awk -v s="$kit/$file" '
      { sub(/\r$/, "") }
      /^[ \t]*(#|$)/ { next }
      {
        i = index($0, ":"); if (i == 0) next
        src = substr($0, 1, i - 1); sub(/^kits\//, "", src)
        if (src == s) { print substr($0, i + 1); exit }
      }
    ' "$KITS_MAP")
    dest=${dest#"$DOTDOT_NAME"/}
  fi
  if [ -z "$dest" ]; then
    dest=$file
    [ -f "$DOTDOT_ROOT/$dest" ] || dest="${file%.md}-$kit.md"
  fi
  [[ "$dest" =~ $KIT_DOC_PATTERN ]] || { echo "❌ $KITS_MAP maps $kit/$file to $dest, which is not a top-level .md file." >&2; return 1; }
  printf '%s\n' "$dest"
}

kit_region_open() { printf '<!-- %s/%s -->' "$1" "${2%.md}"; }
kit_region_close() { printf '<!-- /%s/%s -->' "$1" "${2%.md}"; }

# Prints "region" when doc $1 holds one well-formed region of context file $3
# of kit $2, "none" when it holds none; fails on stray or doubled markers.
kit_region_state() {
  local state
  state=$(awk -v open="$(kit_region_open "$2" "$3")" -v closer="$(kit_region_close "$2" "$3")" '
    $0 == open { opens++; if (closes) bad = 1 }
    $0 == closer { closes++; if (!opens) bad = 1 }
    END { if (bad || opens > 1 || closes > 1 || opens != closes) print "bad"; else print (opens ? "region" : "none") }
  ' "$1")
  [ "$state" != bad ] || { echo "❌ $(dotdot_rel "$1") has stray or doubled $(kit_region_open "$2" "$3") markers; fix them first." >&2; return 1; }
  printf '%s\n' "$state"
}

# Prints context file $1's frontmatter field $2, or nothing.
kit_doc_field() {
  awk -v k="$2" '
    NR == 1 && $0 == "---" { infm = 1; next }
    infm && $0 == "---" { exit }
    infm && index($0, k ":") == 1 { v = substr($0, length(k) + 2); sub(/^[ \t]+/, "", v); print v; exit }
  ' "$1"
}

# Prints context file $1 without its frontmatter and leading blank lines.
kit_doc_body() {
  awk '
    NR == 1 && $0 == "---" { infm = 1; next }
    infm { if ($0 == "---") infm = 0; next }
    !started && /^[ \t]*$/ { next }
    { started = 1; print }
  ' "$1"
}

# Places context file $2 of kit $1 (in $3) into its destination doc.
kit_place_doc() {
  local kit="$1" file="$2" doc="$3" dest path region open close description state
  dest=$(kit_context_dest "$kit" "$file") || return 1
  path="$DOTDOT_ROOT/$dest"
  open=$(kit_region_open "$kit" "$file")
  close=$(kit_region_close "$kit" "$file")
  description=$(kit_doc_field "$doc" description)
  region="$KIT_TMP/region"
  {
    printf '%s\n' "$open"
    [ -z "$description" ] || printf '_%s — %s_\n\n' "$kit" "$description"
    kit_doc_body "$doc"
    printf '%s\n' "$close"
  } > "$region"

  if [ -e "$path" ]; then
    state=$(kit_region_state "$path" "$kit" "$file") || return 1
  fi
  if [ ! -e "$path" ]; then
    {
      printf -- '---\nname: %s\ndescription: %s\n---\n\n' "$dest" "${description:-Context from the $kit kit.}"
      cat -- "$region"
    } > "$path"
    echo "  ✅ $file → $(dotdot_rel "$path") (new file)"
  elif [ "$state" = region ]; then
    awk -v open="$open" -v closer="$close" -v rf="$region" '
      $0 == open { while ((getline line < rf) > 0) print line; skip = 1; next }
      skip { if ($0 == closer) skip = 0; next }
      { print }
    ' "$path" > "$path.tmp-$$" && mv -f -- "$path.tmp-$$" "$path"
    echo "  ✅ $file → $(dotdot_rel "$path") (region replaced)"
  else
    { [ ! -s "$path" ] || [ -z "$(tail -n 1 -- "$path")" ] || printf '\n'; cat -- "$region"; } >> "$path"
    echo "  ✅ $file → $(dotdot_rel "$path") (region appended)"
  fi
}

# Places every context file of the unpacked kit $2 for kit $1.
kit_place_context() {
  local kit="$1" src="$2" doc
  for doc in "$src/$KIT_CONTEXT_DIR"/*.md; do
    [ -f "$doc" ] || continue
    kit_place_doc "$kit" "$(basename -- "$doc")" "$doc" || return 1
  done
}

# Removes kit $1's regions from every top-level doc, except those the
# remaining arguments keep ("<Dest>.md|<File>.md": File's region in Dest), and
# deletes docs that hold nothing but frontmatter afterwards.
kit_strip_regions() {
  local kit="$1" path keep
  shift
  keep=" $* "
  for path in "$DOTDOT_ROOT"/*.md; do
    [ -f "$path" ] && grep -q -- "^<!-- $kit/" "$path" || continue
    awk -v p="$kit" -v keep="$keep" -v doc="$(basename -- "$path")" '
      function flush() { while (blanks > 0) { print ""; blanks-- } }
      !skip && index($0, "<!-- " p "/") == 1 && $0 ~ / -->$/ {
        name = substr($0, length(p) + 7); sub(/ -->$/, "", name)
        if (index(keep, " " doc "|" name ".md ") == 0) { skip = 1; closer = "<!-- /" p "/" name " -->"; blanks = 0; next }
      }
      skip { if ($0 == closer) skip = 0; next }
      /^[ \t]*$/ { blanks++; next }
      { flush(); print }
      END { flush() }
    ' "$path" > "$path.tmp-$$" && mv -f -- "$path.tmp-$$" "$path"
    if [ -z "$(kit_doc_body "$path" | tr -d '[:space:]')" ]; then
      rm -f -- "$path"
      echo "  🗑️  removed $(dotdot_rel "$path")"
    fi
  done
}

# Prints "<Dest>.md|<File>.md" for every context file of the unpacked kit $2
# of kit $1: what kit_strip_regions keeps after an update.
kit_context_places() {
  local file
  while IFS= read -r file; do
    printf '%s|%s\n' "$(kit_context_dest "$1" "$file")" "$file"
  done < <(kit_context_files "$2")
}

# Prints the names of the context files in the unpacked kit $1.
kit_context_files() {
  local doc
  for doc in "$1/$KIT_CONTEXT_DIR"/*.md; do
    [ -f "$doc" ] && basename -- "$doc"
  done
}

# Replaces kit $1's tools in .tooling/kits/ with those of the unpacked kit $2.
kit_install_tools() {
  local kit="$1" src="$2" dir dest="$KITS_DIR/$1"
  rm -rf -- "$dest"
  mkdir -p -- "$dest"
  cp -- "$src/$KIT_CONF_NAME" "$dest/"
  for dir in "${KIT_TOOL_DIRS[@]}"; do
    [ -d "$src/$dir" ] && cp -R -- "$src/$dir" "$dest/"
  done
  return 0
}

# Points at the Claude Code settings installed kit $1 suggests, if any. They
# are never applied: the user copies what suits them.
kit_claude_notice() {
  local file="$KITS_DIR/$1/$KIT_CLAUDE_SETTINGS"
  [ -f "$file" ] || return 0
  echo "ℹ️  $1 suggests Claude Code settings in $(dotdot_rel "$file")."
  echo "   dotdot doesn't apply them; copy what makes sense to you into .claude/settings.local.json."
}

# Prints what installing the unpacked kit $2 as $1 would change.
kit_preview() {
  local kit="$1" src="$2" file dest note dir entry
  echo "Context:"
  while IFS= read -r file; do
    dest=$(kit_context_dest "$kit" "$file") || return 1
    if [ ! -e "$DOTDOT_ROOT/$dest" ]; then
      note="new file"
    else
      note=$(kit_region_state "$DOTDOT_ROOT/$dest" "$kit" "$file") || return 1
      [ "$note" = region ] && note="replace region" || note="append region"
    fi
    echo "  $KIT_CONTEXT_DIR/$file → $DOTDOT_NAME/$dest ($note)"
  done < <(kit_context_files "$src")
  echo "Tools → $(dotdot_rel "$KITS_DIR/$kit")/:"
  for dir in "${KIT_TOOL_DIRS[@]}"; do
    for entry in "$src/$dir"/*; do
      [ -e "$entry" ] || continue
      if [ "$dir" = bin ]; then
        echo "  ⚠️  $dir/$(basename -- "$entry") (script: runs on your machine; read it first)"
      else
        echo "  $dir/$(basename -- "$entry")"
      fi
    done
  done
}

# Creates $KIT_TMP, removed when the script exits.
kit_tmp() {
  KIT_TMP=$(mktemp -d) || { echo "❌ Could not create a temp directory." >&2; exit 1; }
  trap 'rm -rf -- "$KIT_TMP"' EXIT
}

# Runs sync without asking: the user already confirmed the kit change.
kit_sync() {
  bash "$BIN_DIR/dot-sync.sh" -y
}
