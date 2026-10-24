#!/usr/bin/env bash

scaffold_plugin() {
  dot plugins:new "$1"
  assert_success "scaffold $1"
}

test_new_plugin_installs_and_runs_under_its_owner() {
  printf '@pluginsSkills::.claude/skills\n' > "$DOTDOT/sync.map"
  scaffold_plugin acme/widgets
  printf -- '---\ndescription: d\n---\n\nwidgets rule\n' > "$SANDBOX/widgets/dotdot/context/STANDARDS.md"
  add_plugin acme/widgets widgets
  dot sync -y
  dot acme:hello dotdot
  assert_success
  assert_contains "$OUTPUT" "Hello, dotdot!"
  assert_contains "$(cat "$DOTDOT/STANDARDS.md")" "widgets rule"
  assert_link_to "$SANDBOX/.claude/skills/widgets-example" "$DOTDOT/.plugins/acme/widgets/skills/widgets-example"
  dot plugins:list
  assert_contains "$OUTPUT" "acme/widgets  path:widgets"
}

test_only_the_dotdot_folder_is_installed() {
  scaffold_plugin acme/widgets
  printf 'repository readme\n' > "$SANDBOX/widgets/README.md"
  add_plugin acme/widgets widgets
  assert_file "$DOTDOT/.plugins/acme/widgets/plugin.conf"
  assert_no_file "$DOTDOT/.plugins/acme/widgets/README.md"
  assert_no_file "$DOTDOT/.plugins/acme/widgets/dotdot"
}

test_plugin_add_needs_a_terminal_even_with_yes() {
  scaffold_plugin acme/widgets
  dot plugins:add acme/widgets --from ./widgets --yes
  assert_failure
  assert_contains "$ERRORS" "terminal"
  assert_contains "$ERRORS" "not from dotdot"
  assert_no_file "$DOTDOT/.plugins/acme"
}

test_plugin_ids_are_owner_and_name() {
  dot plugins:add widgets --from ./widgets
  assert_failure
  assert_contains "$ERRORS" "<owner>/<name>"
  dot plugins:add acme/Not_Valid
  assert_failure
  assert_contains "$ERRORS" "<owner>/<name>"
}

test_repos_without_a_dotdot_folder_are_refused() {
  mkdir -p "$SANDBOX/plain"
  core "dot::use core.system.plugins.service; core.system.plugins.service::fetch acme/plain '' plain"
  assert_failure
  assert_contains "$ERRORS" "no dotdot/ folder"
}

test_plugin_must_target_this_api() {
  scaffold_plugin acme/widgets
  sed -i.bak 's/^REQUIRES=.*/REQUIRES=99/' "$SANDBOX/widgets/dotdot/plugin.conf"
  core "dot::use core.system.plugins.service core.system.plugins.manifest
    core.system.plugins.service::fetch acme/widgets '' widgets
    core.system.plugins.manifest::validate \"\$PLUGIN_SOURCE\" acme/widgets"
  assert_failure
  assert_contains "$ERRORS" "plugin API"
}

test_plugin_commands_follow_the_layout() {
  scaffold_plugin acme/widgets
  mkdir -p "$SANDBOX/widgets/dotdot/commands/a/b"
  : > "$SANDBOX/widgets/dotdot/commands/a/b/deep.sh"
  core "dot::use core.system.plugins.service core.system.plugins.manifest
    core.system.plugins.service::fetch acme/widgets '' widgets
    core.system.plugins.manifest::validate \"\$PLUGIN_SOURCE\" acme/widgets"
  assert_failure
  assert_contains "$ERRORS" "levels deep"
}

validate_plugin() {
  core "dot::use core.system.plugins.service core.system.plugins.manifest
    core.system.plugins.service::fetch $1 '' $2
    core.system.plugins.manifest::validate \"\$PLUGIN_SOURCE\" $1"
}

test_taken_commands_are_refused() {
  scaffold_plugin acme/widgets
  scaffold_plugin acme/gadgets
  add_plugin acme/widgets widgets
  validate_plugin acme/gadgets gadgets
  assert_failure
  assert_contains "$ERRORS" "already taken: acme:hello"
}

test_owner_may_not_be_a_core_command_name() {
  scaffold_plugin tasks/widgets
  validate_plugin tasks/widgets widgets
  assert_failure
  assert_contains "$ERRORS" "dotdot's own command names"
}

test_linked_entries_must_carry_the_plugin_name() {
  scaffold_plugin acme/widgets
  mkdir -p "$SANDBOX/widgets/dotdot/skills/dot-onboard"
  validate_plugin acme/widgets widgets
  assert_failure
  assert_contains "$ERRORS" "must be named widgets-"
}

test_linked_entries_may_not_clash_between_plugins() {
  scaffold_plugin acme/widgets
  add_plugin acme/widgets widgets
  dot plugins:new other/widgets --path other
  assert_success
  rm -f "$SANDBOX/other/dotdot/commands/hello.sh"
  validate_plugin other/widgets other
  assert_failure
  assert_contains "$ERRORS" "skills/widgets-example is already taken"
}

test_sync_never_lets_a_plugin_replace_a_core_link() {
  scaffold_plugin acme/widgets
  { cat "$DOTDOT/.core/system/sync/stubs/sync.map"; printf '@RULES.md::.claude/rules/RULES.md\n@pluginsSkills::.claude/skills\n'; } > "$DOTDOT/sync.map"
  add_plugin acme/widgets widgets
  mkdir -p "$DOTDOT/.plugins/acme/widgets/skills/dot-onboard"
  : > "$DOTDOT/.plugins/acme/widgets/skills/dot-onboard/SKILL.md"
  printf '# <!-- acme/widgets -->\n@RULES.md::AGENTS.md\n@SECURITY.md::.claude/rules/RULES.md\n# <!-- /acme/widgets -->\n' >> "$DOTDOT/sync.map"
  dot sync -y
  assert_failure
  assert_contains "$ERRORS" "dot-onboard clashes with .claude/skills/dot-onboard"
  assert_contains "$ERRORS" "clashes with AGENTS.md"
  assert_contains "$ERRORS" "clashes with .claude/rules/RULES.md"
  assert_link_to "$SANDBOX/AGENTS.md" "$DOTDOT/AGENTS.md"
  assert_link_to "$SANDBOX/.claude/skills/dot-onboard" "$DOTDOT/.core/modules/onboarding/skills/dot-onboard"
  assert_link_to "$SANDBOX/.claude/rules/RULES.md" "$DOTDOT/RULES.md"
}

test_sync_never_links_secrets_or_into_git() {
  scaffold_plugin acme/widgets
  add_plugin acme/widgets widgets
  printf 'GH_TOKEN=secret\n' > "$DOTDOT/.env"
  printf '@.env::leak\n../../.env::leak2\n# <!-- acme/widgets -->\nplugin.conf::.git/hooks/pre-commit\nplugin.conf::.dot/AGENTS.md\n# <!-- /acme/widgets -->\n' >> "$DOTDOT/sync.map"
  dot sync -y
  assert_failure
  assert_no_file "$SANDBOX/leak"
  assert_contains "$ERRORS" "Unknown shortcut @.env"
  assert_no_file "$SANDBOX/leak2"
  assert_no_file "$SANDBOX/.git/hooks/pre-commit"
  [ ! -L "$DOTDOT/AGENTS.md" ] || fail "a plugin linked into dotdot"
}

test_plugin_links_are_validated_when_added() {
  local setting reason
  scaffold_plugin acme/widgets
  while IFS='|' read -r setting reason; do
    printf 'REQUIRES=1\n%s\n' "$setting" > "$SANDBOX/widgets/dotdot/plugin.conf"
    validate_plugin acme/widgets widgets
    assert_failure "$setting must be refused"
    assert_contains "$ERRORS" "$reason"
  done <<'CASES'
LINKS=../x::y|must be a path inside the plugin
LINKS=@.env::y|must name one of dotdot's top-level docs
LINKS=plugin.conf::.git/config|must be a project path outside
LINKS=plugin.conf::../outside|must be a project path outside
LINKS=plugin.conf::.dot/x|must be a project path outside
LINKS=plugin.conf::dot|must be a project path outside
LINKS=plugin.conf::AGENTS.md|is already linked in .dot/sync.map
LINKS=plugin.conf|give <origin>::<destination>
LINKS=missing.conf::x|is not in the plugin
HARNESS_SKILLS=.dot/skills|must be a project directory
CASES
}

test_plugin_link_destinations_may_not_clash() {
  scaffold_plugin acme/widgets
  printf 'REQUIRES=1\nLINKS=plugin.conf::widgets.conf\n' > "$SANDBOX/widgets/dotdot/plugin.conf"
  add_plugin acme/widgets widgets
  dot plugins:new other/gadgets --path gadgets
  printf 'REQUIRES=1\nLINKS=plugin.conf::widgets.conf\n' > "$SANDBOX/gadgets/dotdot/plugin.conf"
  validate_plugin other/gadgets gadgets
  assert_failure
  assert_contains "$ERRORS" "widgets.conf is already linked"
}

test_lock_keeps_plugin_names_apart() {
  scaffold_plugin acme-x/y
  dot plugins:new acme/x-y --path other
  assert_success
  add_plugin acme-x/y y
  add_plugin acme/x-y other
  assert_equal "$(cat "$DOTDOT/.plugins/plugins.lock")" "acme-x/y=path:y - -
acme/x-y=path:other - -"
  core "dot::use core.system.plugins.manifest
    core.system.plugins.manifest::unlock acme/x-y
    core.system.plugins.manifest::installed"
  assert_equal "$OUTPUT" "acme-x/y"
}

test_plugin_remove_keeps_project_records() {
  scaffold_plugin acme/widgets
  printf -- '---\ndescription: d\n---\n\nwidgets rule\n' > "$SANDBOX/widgets/dotdot/context/STANDARDS.md"
  printf 'REQUIRES=1\nDIRECTORIES=Widgets\n' > "$SANDBOX/widgets/dotdot/plugin.conf"
  add_plugin acme/widgets widgets
  assert_file "$DOTDOT/Widgets/.gitkeep"
  printf 'kept\n' > "$DOTDOT/Widgets/w001.md"
  dot plugins:remove acme/widgets
  assert_failure
  assert_contains "$ERRORS" "Confirmation needs a terminal"
  core "dot::use core.system.plugins.context core.system.plugins.service core.system.plugins.manifest
    core.system.plugins.context::strip acme/widgets >/dev/null
    core.system.plugins.service::uninstall acme/widgets
    core.system.plugins.manifest::unlock acme/widgets"
  assert_success
  assert_contains "$OUTPUT" "kept"
  assert_file "$DOTDOT/Widgets/w001.md"
  assert_no_file "$DOTDOT/.plugins/acme"
  assert_not_contains "$(cat "$DOTDOT/STANDARDS.md")" "widgets rule"
}

test_plugin_stubs_never_overwrite() {
  scaffold_plugin acme/widgets
  mkdir -p "$SANDBOX/widgets/dotdot/stubs"
  printf 'theirs\n' > "$SANDBOX/widgets/dotdot/stubs/widgets.conf.stub"
  printf 'theirs\n' > "$SANDBOX/widgets/dotdot/stubs/fresh.conf.stub"
  printf 'mine\n' > "$SANDBOX/widgets.conf"
  add_plugin acme/widgets widgets
  assert_equal "$(cat "$SANDBOX/widgets.conf")" "mine"
  assert_equal "$(cat "$SANDBOX/fresh.conf")" "theirs"
}

test_plugin_env_stub_adds_only_missing_settings() {
  scaffold_plugin acme/widgets
  mkdir -p "$SANDBOX/widgets/dotdot/stubs"
  printf 'ACME__WIDGETS__KEY=\nACME__WIDGETS__MODE=fast\n' > "$SANDBOX/widgets/dotdot/stubs/env.stub"
  printf 'ACME__WIDGETS__KEY=mine\n' > "$DOTDOT/.env"
  add_plugin acme/widgets widgets
  add_plugin acme/widgets widgets
  assert_equal "$(cat "$DOTDOT/.env")" "ACME__WIDGETS__KEY=mine
ACME__WIDGETS__MODE=fast"
}

test_plugin_env_stub_creates_a_private_env() {
  scaffold_plugin acme/widgets
  mkdir -p "$SANDBOX/widgets/dotdot/stubs"
  printf 'ACME__WIDGETS__KEY=\n' > "$SANDBOX/widgets/dotdot/stubs/env.stub"
  add_plugin acme/widgets widgets
  assert_equal "$(ls -l "$DOTDOT/.env" | cut -c1-10)" "-rw-------"
}

test_plugin_settings_carry_the_plugin_prefix() {
  scaffold_plugin acme/widgets
  mkdir -p "$SANDBOX/widgets/dotdot/stubs"
  printf 'GH_TOKEN=\n' > "$SANDBOX/widgets/dotdot/stubs/env.stub"
  validate_plugin acme/widgets widgets
  assert_failure
  assert_contains "$ERRORS" "must start with ACME__WIDGETS__: GH_TOKEN"
  rm "$SANDBOX/widgets/dotdot/stubs/env.stub"
  add_plugin acme/widgets widgets
  printf 'GH_TOKEN=secret\nACME__WIDGETS__KEY=own\n' > "$DOTDOT/.env"
  printf '#!/usr/bin/env bash\nDESCRIPTION="Probe."\nusage() { :; }\nhandle() { dot::config "$1"; }\n' > "$DOTDOT/.plugins/acme/widgets/commands/probe.sh"
  dot acme:probe ACME__WIDGETS__KEY
  assert_success
  assert_equal "$OUTPUT" "own"
  dot acme:probe GH_TOKEN
  assert_failure
  assert_contains "$ERRORS" "acme/widgets's settings must start with ACME__WIDGETS__: GH_TOKEN"
}

test_plugins_get_no_paths_outside_their_folder() {
  local kind
  scaffold_plugin acme/widgets
  add_plugin acme/widgets widgets
  printf '#!/usr/bin/env bash\nDESCRIPTION="Probe."\nusage() { :; }\nhandle() { dot::path "$1"; }\n' > "$DOTDOT/.plugins/acme/widgets/commands/probe.sh"
  for kind in data env; do
    dot acme:probe "$kind"
    assert_failure "dot::path $kind"
  done
  dot acme:probe plugin
  assert_success
  assert_equal "$OUTPUT" "$DOTDOT/.plugins/acme/widgets"
}

test_plugin_stubs_may_not_seed_git() {
  scaffold_plugin acme/widgets
  mkdir -p "$SANDBOX/widgets/dotdot/stubs/.git/hooks"
  printf 'theirs\n' > "$SANDBOX/widgets/dotdot/stubs/.git/hooks/pre-commit.stub"
  core "dot::use core.system.plugins.manifest core.system.plugins.service
    core.system.plugins.service::fetch acme/widgets '' widgets
    core.system.plugins.manifest::validate \"\$PLUGIN_SOURCE\" acme/widgets"
  assert_failure
  assert_contains "$ERRORS" "may not seed git"
}

test_plugin_owner_may_start_with_a_digit() {
  scaffold_plugin 42acme/widgets
  add_plugin 42acme/widgets widgets
  dot 42acme:hello dotdot
  assert_success
  assert_contains "$OUTPUT" "Hello, dotdot!"
}

test_plugin_update_lists_what_changed() {
  scaffold_plugin acme/widgets
  add_plugin acme/widgets widgets
  sed -i.bak 's/Hello/Howdy/' "$SANDBOX/widgets/dotdot/commands/hello.sh"
  rm -f "$SANDBOX/widgets/dotdot/commands/hello.sh.bak"
  core "dot::use core.system.plugins.service
    core.system.plugins.service::fetch acme/widgets '' widgets
    core.system.plugins.service::changed_files acme/widgets \"\$PLUGIN_SOURCE\""
  assert_success
  assert_equal "$OUTPUT" "changed	commands/hello.sh"
}

test_plugin_new_stays_inside_the_project() {
  dot plugins:new acme/widgets --path ../outside
  assert_failure
  assert_contains "$ERRORS" "inside the project"
}

test_plugins_cannot_reach_core_internals_or_each_other() {
  local module
  scaffold_plugin acme/widgets
  scaffold_plugin other/gizmos
  add_plugin acme/widgets widgets
  add_plugin other/gizmos gizmos
  printf '#!/usr/bin/env bash\nother.gizmos::x() { :; }\n' > "$DOTDOT/.plugins/other/gizmos/tool.sh"
  for module in core.modules.notes.service framework.integrations.github-api.internal.request plugins.other.gizmos.tool; do
    printf '#!/usr/bin/env bash\nDESCRIPTION="Probe."\nusage() { :; }\nhandle() { dot::use %s; }\n' "$module" > "$DOTDOT/.plugins/acme/widgets/commands/probe.sh"
    dot acme:probe
    assert_failure "$module must be private"
    assert_contains "$ERRORS" "may not use"
  done
  printf '#!/usr/bin/env bash\nDESCRIPTION="Probe."\nusage() { :; }\nhandle() { dot::use framework.helpers.text framework.console.output framework.integrations.github-api.service; framework.console.output::success ok; }\n' \
    > "$DOTDOT/.plugins/acme/widgets/commands/probe.sh"
  dot acme:probe
  assert_success
}

test_core_modules_keep_to_themselves() {
  printf '#!/usr/bin/env bash\ndot::use core.modules.tasks.service\n' > "$DOTDOT/.core/modules/notes/probe.sh"
  core ". '$DOTDOT/.core/modules/notes/probe.sh'"
  assert_failure
  assert_contains "$ERRORS" "may not use the dotdot module core.modules.tasks.service"
  printf '#!/usr/bin/env bash\ndot::use core.system.plugins.service\n' > "$DOTDOT/.core/system/sync/probe.sh"
  core ". '$DOTDOT/.core/system/sync/probe.sh'"
  assert_failure
  assert_contains "$ERRORS" "may not use the dotdot module core.system.plugins.service"
  printf '#!/usr/bin/env bash\ndot::use framework.integrations.github-api.internal.request\n' > "$DOTDOT/.core/framework/helpers/probe.sh"
  core ". '$DOTDOT/.core/framework/helpers/probe.sh'"
  assert_failure
  assert_contains "$ERRORS" "may not use"
  printf '#!/usr/bin/env bash\ndot::use core.modules.notes.service framework.helpers.text\n' > "$DOTDOT/.core/modules/notes/probe.sh"
  core ". '$DOTDOT/.core/modules/notes/probe.sh'"
  assert_success
}

test_leftover_environment_variables_are_ignored() {
  mkdir -p "$SANDBOX/precious"
  : > "$SANDBOX/precious/keep"
  scaffold_plugin acme/widgets
  core "PLUGINS_WORKSPACE='$SANDBOX/precious' DOT_PLUGIN=other/gizmos; export PLUGINS_WORKSPACE DOT_PLUGIN
    bash ./dot plugins:list >/dev/null
    dot::use core.system.plugins.service; core.system.plugins.service::fetch acme/widgets '' widgets"
  assert_success
  assert_file "$SANDBOX/precious/keep"
}
