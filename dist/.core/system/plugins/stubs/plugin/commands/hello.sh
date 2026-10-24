#!/usr/bin/env bash

DESCRIPTION="Greet from the plugin."

dot::use framework.console.args framework.console.output

usage() {
  framework.console.output::line "bash dot $DOT_COMMAND — greet from the plugin."
  framework.console.output::newline
  framework.console.output::line "Usage:"
  framework.console.output::line "  bash dot $DOT_COMMAND [name]"
}

handle() {
  [ $# -le 1 ] || framework.console.args::unexpected "$2"
  framework.console.output::success "Hello, ${1:-world}!"
}
