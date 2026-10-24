#!/usr/bin/env bash

dot::use framework.helpers.fs framework.helpers.record framework.helpers.template framework.helpers.text

FEATURE_TEMPLATE="$MODULES_DIR/features/skills/dot-document-feature/feature-template.md"
FEATURE_DESCRIPTION_KEY="description"

core.modules.features.service::create() {
  local slug="$1" sections_dir="$2" path description
  path=$(framework.helpers.record::next_path "$FEATURES_DIR" "$FEATURE_PREFIX" "$slug") || return 1
  description=$(framework.helpers.text::oneline < "$sections_dir/$FEATURE_DESCRIPTION_KEY")
  {
    printf -- '---\nname: %s\ndescription: %s\n---\n\n' "$slug" "$description"
    framework.helpers.template::compose "$FEATURE_TEMPLATE" "$sections_dir"
  } > "$sections_dir/.document"
  framework.helpers.template::trim_trailing_blank_lines "$sections_dir/.document"
  framework.helpers.fs::write "$path" < "$sections_dir/.document" || return 1
  printf '%s\n' "$path"
}
