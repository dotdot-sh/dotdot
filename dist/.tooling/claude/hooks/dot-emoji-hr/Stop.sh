#!/bin/bash

. "$(dirname "$(realpath "$0")")/../../../bin/lib/dot-paths.sh"
cd "${CLAUDE_PROJECT_DIR:-$BASE}" || exit 0
"$BIN_DIR/dot" emoji:hr -r rainbow --date 2>/dev/null | jq -Rs '{systemMessage: .}'
