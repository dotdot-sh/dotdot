#!/usr/bin/env bash

skill_paths() {
  find "$DOTDOT"/.core/system/*/skills "$DOTDOT"/.core/modules/*/skills -mindepth 1 -maxdepth 1 -type d
}

test_sync_links_and_seeds() {
  dot sync -y
  assert_success
  assert_link_to "$SANDBOX/AGENTS.md" "$DOTDOT/AGENTS.md"
  assert_file "$DOTDOT/USER.md"
}

test_sync_is_idempotent() {
  dot sync -y
  dot sync -y
  assert_success
  assert_contains "$OUTPUT" "Nothing to do."
}

test_sync_needs_confirmation_without_yes() {
  dot sync
  assert_failure
  assert_contains "$ERRORS" "Confirmation needs a terminal"
  assert_no_file "$SANDBOX/AGENTS.md"
}

test_sync_prunes_broken_dotdot_links_and_keeps_foreign_ones() {
  dot sync -y
  ln -s ../../.dot/.core/system/sync/skills/removed-skill "$SANDBOX/.claude/skills/removed-skill"
  ln -s /nonexistent/elsewhere "$SANDBOX/.claude/skills/foreign"
  dot sync -y
  assert_success
  assert_no_file "$SANDBOX/.claude/skills/removed-skill"
  [ -L "$SANDBOX/.claude/skills/foreign" ] || fail "a foreign link was removed"
}

test_sync_never_overwrites_files_without_override() {
  printf 'mine\n' > "$SANDBOX/AGENTS.md"
  dot sync -y
  assert_equal "$(cat "$SANDBOX/AGENTS.md")" "mine"
  dot sync -y --override
  assert_success
  assert_link_to "$SANDBOX/AGENTS.md" "$DOTDOT/AGENTS.md"
  [ -n "$(find "$SANDBOX" -maxdepth 1 -name 'AGENTS.md.bak-*')" ] || fail "no backup was made"
}

test_claude_code_plugin_installs_and_links_cleanly() {
  add_claude_code
  assert_success
  [ -z "$ERRORS" ] || fail "sync reported problems: $ERRORS"
}

test_claude_code_statusline_runs_through_its_link() {
  copy_claude_code
  mkdir -p "$SANDBOX/.claude"
  ln -s ../.dot/.plugins/dotdot-sh/claude-code/claude/claude-code-statusline.sh "$SANDBOX/.claude/claude-code-statusline.sh"
  run bash -c "printf '%s' '{\"model\":{\"display_name\":\"Opus\"}}' | bash .claude/claude-code-statusline.sh"
  assert_success
  assert_contains "$OUTPUT" "Opus"
}

test_sync_seeds_a_map_the_user_controls() {
  dot sync -y
  assert_success
  assert_file "$DOTDOT/sync.map"
  printf '@RULES.md::RULES-here.md\n' > "$DOTDOT/sync.map"
  rm "$SANDBOX/AGENTS.md"
  dot sync -y
  assert_success
  assert_link_to "$SANDBOX/RULES-here.md" "$DOTDOT/RULES.md"
  assert_no_file "$SANDBOX/AGENTS.md"
  assert_equal "$(cat "$DOTDOT/sync.map")" "@RULES.md::RULES-here.md"
}

test_plugins_get_a_block_in_the_map_that_the_user_can_edit() {
  local plugin="$DOTDOT/.plugins/acme/widgets"
  dot plugins:new acme/widgets --path widgets
  printf 'REQUIRES=1\nLINKS=plugin.conf::widgets.conf\n' > "$SANDBOX/widgets/dotdot/plugin.conf"
  add_plugin acme/widgets widgets
  dot sync -y
  assert_success
  assert_link_to "$SANDBOX/widgets.conf" "$plugin/plugin.conf"
  sed -i.bak 's|^plugin.conf::widgets.conf$|# &|' "$DOTDOT/sync.map" && rm -f "$DOTDOT/sync.map.bak"
  rm "$SANDBOX/widgets.conf"
  dot sync -y
  assert_success
  assert_no_file "$SANDBOX/widgets.conf"
  dot sync -y --refresh acme/widgets
  assert_success
  assert_link_to "$SANDBOX/widgets.conf" "$plugin/plugin.conf"
  core "dot::use core.system.plugins.service core.system.plugins.manifest
    core.system.plugins.service::uninstall acme/widgets >/dev/null
    core.system.plugins.manifest::unlock acme/widgets"
  dot sync -y
  assert_success
  assert_no_file "$SANDBOX/widgets.conf"
  printf '@AGENTS.md::widgets.conf\n' >> "$DOTDOT/sync.map"
  dot sync -y
  assert_success
  assert_link_to "$SANDBOX/widgets.conf" "$DOTDOT/AGENTS.md"
}

test_sync_keeps_a_plugin_block_inside_its_plugin() {
  add_claude_code
  sed -i.bak 's|^claude/claude-code-statusline.sh::.*|../../../.env::leak|' "$DOTDOT/sync.map" && rm -f "$DOTDOT/sync.map.bak"
  printf 'GH_TOKEN=secret\n' > "$DOTDOT/.env"
  dot sync -y
  assert_failure
  assert_no_file "$SANDBOX/leak"
}

test_sync_map_shortcuts_resolve_modules_plugins_and_sets() {
  dot plugins:new acme/widgets --path widgets
  add_plugin acme/widgets widgets
  cat > "$DOTDOT/sync.map" <<'MAP'
@module.notes.skills.dot-tool-notes::one/dot-tool-notes
@module.notes.skills::whole/skills
@module.tasks.skills/*::each/
@module.sync.skills.dot-tool-sync::system/dot-tool-sync
@plugin.acme.widgets.skills.widgets-example::plugin/widgets-example
@plugin.acme.widgets.plugin.conf::plugin/widgets.conf
@dotdotSkills::dotdot/
@pluginsSkills::plugins/
MAP
  dot sync -y
  assert_success
  assert_link_to "$SANDBOX/one/dot-tool-notes" "$DOTDOT/.core/modules/notes/skills/dot-tool-notes"
  assert_link_to "$SANDBOX/whole/skills" "$DOTDOT/.core/modules/notes/skills"
  assert_link_to "$SANDBOX/each/dot-create-task" "$DOTDOT/.core/modules/tasks/skills/dot-create-task"
  assert_link_to "$SANDBOX/system/dot-tool-sync" "$DOTDOT/.core/system/sync/skills/dot-tool-sync"
  assert_link_to "$SANDBOX/plugin/widgets-example" "$DOTDOT/.plugins/acme/widgets/skills/widgets-example"
  assert_link_to "$SANDBOX/plugin/widgets.conf" "$DOTDOT/.plugins/acme/widgets/plugin.conf"
  assert_link_to "$SANDBOX/dotdot/dot-onboard" "$DOTDOT/.core/modules/onboarding/skills/dot-onboard"
  assert_no_file "$SANDBOX/dotdot/widgets-example"
  assert_link_to "$SANDBOX/plugins/widgets-example" "$DOTDOT/.plugins/acme/widgets/skills/widgets-example"
  assert_no_file "$SANDBOX/plugins/dot-onboard"
}

test_sync_map_removals_win_and_never_touch_real_files() {
  printf '@AGENTS.md::AGENTS.md\n@RULES.md::rules.md\n' > "$DOTDOT/sync.map"
  printf 'mine\n' > "$SANDBOX/real.md"
  dot sync -y
  assert_link_to "$SANDBOX/rules.md" "$DOTDOT/RULES.md"
  printf '@AGENTS.md::AGENTS.md\n@RULES.md::rules.md\n!rules.md\n!real.md\n' > "$DOTDOT/sync.map"
  dot sync -y
  assert_success
  assert_no_file "$SANDBOX/rules.md"
  assert_equal "$(cat "$SANDBOX/real.md")" "mine"
  dot sync -y
  assert_no_file "$SANDBOX/rules.md"
  printf '!.git/config\n' >> "$DOTDOT/sync.map"
  dot sync -y
  assert_failure
  assert_contains "$ERRORS" "Removal '!.git/config' is not a project path outside dotdot and .git"
}

test_sync_map_refuses_unknown_shortcuts() {
  printf '@everything::x\n' > "$DOTDOT/sync.map"
  dot sync -y
  assert_failure
  assert_contains "$ERRORS" "Unknown shortcut @everything"
}

test_skill_and_agent_sets_follow_the_skills_standard() {
  mkdir -p "$DOTDOT/.core/system/sync/skills/not-a-skill" "$DOTDOT/.core/modules/notes/agents" "$DOTDOT/.core/modules/newmodule/skills/new-skill"
  : > "$DOTDOT/.core/modules/newmodule/skills/new-skill/SKILL.md"
  : > "$DOTDOT/.core/modules/notes/agents/notes-agent.md"
  : > "$DOTDOT/.core/modules/notes/agents/README.txt"
  printf '@dotdotSkills::.claude/skills/\n@dotdotAgents::.claude/agents/\n' > "$DOTDOT/sync.map"
  dot sync -y
  assert_success
  assert_link_to "$SANDBOX/.claude/skills/dot-tool-sync" "$DOTDOT/.core/system/sync/skills/dot-tool-sync"
  assert_link_to "$SANDBOX/.claude/skills/dot-onboard" "$DOTDOT/.core/modules/onboarding/skills/dot-onboard"
  assert_link_to "$SANDBOX/.claude/skills/new-skill" "$DOTDOT/.core/modules/newmodule/skills/new-skill"
  assert_no_file "$SANDBOX/.claude/skills/not-a-skill"
  assert_link_to "$SANDBOX/.claude/agents/notes-agent.md" "$DOTDOT/.core/modules/notes/agents/notes-agent.md"
  assert_no_file "$SANDBOX/.claude/agents/README.txt"
}
