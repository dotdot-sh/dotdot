#!/usr/bin/env bash

DESCRIPTION="Move a task to doing."

dot::use core.modules.tasks.console core.modules.tasks.service

usage() {
  core.modules.tasks.console::status_usage "${DOT_COMMAND#tasks:}"
}

handle() {
  core.modules.tasks.console::move "${DOT_COMMAND#tasks:}" "$@"
}
