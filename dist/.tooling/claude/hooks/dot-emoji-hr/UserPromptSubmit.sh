#!/bin/bash

. "$(dirname "$(realpath "$0")")/../../../bin/lib/dot-paths.sh"
command="bash dot emoji:hr"
jq -n --arg command "$command" '{
  hookSpecificOutput: {
    hookEventName: "UserPromptSubmit",
    additionalContext: ("**Before** your final response or summary of a task, run `" + $command + " <emoji-related-to-the-task> rainbow --date`, then wrap your response with its output.")
  }
}'
