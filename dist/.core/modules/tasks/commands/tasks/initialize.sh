#!/usr/bin/env bash

DESCRIPTION="Pick the service that keeps the project's tasks (plain files, GitHub, ...)."

dot::use framework.console.args framework.console.output framework.console.prompt core.modules.tasks.service

usage() {
  local service
  cat <<EOF
bash dot tasks:initialize — choose where this project's tasks are kept, then
set that service up. Any tasks:* command runs it on first use.

The choice is saved in $(dot::relative "$ENV_FILE") as $TASK_SERVICE_KEY (the github
service adds TASKS_GITHUB_REPO). That file is git-ignored, so each person sets
it once; every tasks:* command then goes to that service. Running it again
switches services. Existing tasks are not moved: the new service starts with
its own.

Services (one driver each in $(dot::relative "$TASK_DRIVERS_DIR")/):
EOF
  while IFS= read -r service; do
    printf '  %-10s %s\n' "$service" "$(core.modules.tasks.service::service_description "$service")"
  done < <(core.modules.tasks.service::services)
  cat <<EOF

It asks on a terminal (piped input is refused), so only a person can choose.

The github service uses your gh login, or GH_TOKEN in $(dot::relative "$ENV_FILE")
when set: then every task is read and written as that token's owner, for this
project only.

Usage:
  bash dot tasks:initialize
  bash dot tasks:initialize --help
EOF
}

handle() {
  local services=() labels=() service current choice
  [ $# -eq 0 ] || framework.console.args::unexpected "$1"
  framework.console.prompt::can_ask || framework.console.output::fail "Choosing a task service needs a terminal; ask the user to run bash dot tasks:initialize."
  core.modules.tasks.service::require_template
  while IFS= read -r service; do
    services+=("$service")
    labels+=("$service — $(core.modules.tasks.service::service_description "$service")")
  done < <(core.modules.tasks.service::services)
  [ ${#services[@]} -gt 0 ] || framework.console.output::fail "No task services installed in $(dot::relative "$TASK_DRIVERS_DIR")/."
  if current=$(core.modules.tasks.service::selected_service); then
    framework.console.output::line "Tasks are kept in: $(framework.console.output::paint bold "$current"). Switching leaves existing tasks where they are."
  fi
  framework.console.output::newline
  choice=$(framework.console.prompt::choice "Where should this project keep its tasks?" "${labels[@]}") || { framework.console.output::aborted; exit 1; }
  service="${services[$((choice - 1))]}"
  core.modules.tasks.service::load_service "$service"
  dot::use "core.modules.tasks.drivers.$service-setup"
  "core.modules.tasks.drivers.${service}-setup::setup" || framework.console.output::fail "Setting up $service failed — nothing changed."
  core.modules.tasks.service::select_service "$service"
  framework.console.output::success "Tasks are kept in $service ($TASK_SERVICE_KEY in $(dot::relative "$ENV_FILE"))."
}
