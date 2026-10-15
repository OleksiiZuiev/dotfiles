#!/bin/bash
# SessionStart / SessionEnd / UserPromptSubmit hook: records the session in the sessions index.
# Usage: session-index.sh start|end|fill   (hook payload on stdin)
#
# Git runs here, on the OS that owns the working directory; the database write is sessions-db.mjs
# on the Windows node (lib/windows-node.sh).
# Fails open: a failed write logs one line to stderr and the session carries on.

event="$1"
payload=$(cat)

# UserPromptSubmit fires on every prompt; only a /ds:refine or /work-on one can fill a ticket, so
# anything else is turned away here rather than paying for a node start. sessions-db.mjs makes the
# real match.
if [[ "$event" == "fill" ]]; then
  case "$payload" in *'"prompt":"/ds:refine '* | *'"prompt":"/work-on '*) ;; *) exit 0 ;; esac
fi

source "$(dirname "$0")/../lib/windows-node.sh"

branch="" origin="" common_dir=""
if [[ "$event" == "start" ]]; then
  branch=$(git branch --show-current 2>/dev/null)
  origin=$(git remote get-url origin 2>/dev/null)
  common_dir=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)
fi

# Git facts go on stdin ahead of the payload, not in argv or env: Git Bash rewrites path-like
# arguments for a Windows program, and env vars do not cross WSL interop.
if ! printf '%s\n%s\n%s\n%s' "$branch" "$origin" "$common_dir" "$payload" \
    | _windows_node "$(dirname "$0")/sessions-db.mjs" "$event" > /dev/null; then
  echo "session-index: $event write failed (node: ${CLAUDE_WINDOWS_NODE:-the Windows node})" >&2
fi
exit 0
