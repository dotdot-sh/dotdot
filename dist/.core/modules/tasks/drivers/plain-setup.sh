#!/usr/bin/env bash

dot::use framework.console.output

core.modules.tasks.drivers.plain-setup::setup() {
  core.modules.tasks.drivers.plain::configure
  framework.console.output::line "Tasks are files in $(dot::relative "$TASKS_DIR")/."
}
