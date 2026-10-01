#!/bin/bash
# SessionStart / SessionEnd hook: records the session in the sessions index.
# Usage: session-index.sh start|end   (hook payload on stdin)
#
# Git runs here, on the OS that owns the working directory; the database write is always the
# Windows node running sessions-db.mjs, because WSL writers over /mnt/c are not safe.
# Fails open: a failed write logs one line to stderr and the session carries on.

event="$1"
payload=$(cat)

writer="$(dirname "$0")/sessions-db.mjs"
if [[ -n "$WSL_DISTRO_NAME" ]]; then
  node_bin="${CLAUDE_SESSIONS_NODE:-/mnt/c/Program Files/nodejs/node.exe}"
  writer=$(wslpath -w "$writer" 2>/dev/null)
else
  node_bin="${CLAUDE_SESSIONS_NODE:-node}"
  writer=$(cygpath -w "$writer" 2>/dev/null)
fi

branch="" origin="" common_dir=""
if [[ "$event" == "start" ]]; then
  branch=$(git branch --show-current 2>/dev/null)
  origin=$(git remote get-url origin 2>/dev/null)
  common_dir=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)
fi

# Git facts go on stdin ahead of the payload, not in argv or env: Git Bash rewrites path-like
# arguments for a Windows program, and env vars do not cross WSL interop.
if ! printf '%s\n%s\n%s\n%s' "$branch" "$origin" "$common_dir" "$payload" \
    | "$node_bin" --disable-warning=ExperimentalWarning "$writer" "$event" > /dev/null; then
  echo "session-index: $event write failed (node: $node_bin)" >&2
fi
exit 0
