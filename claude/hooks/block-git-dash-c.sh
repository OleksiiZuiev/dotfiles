#!/bin/bash
# Block "git -C" usage — use Bash working directory instead.
INPUT=$(cat)

if echo "$INPUT" | grep -q '"git -C'; then
  echo "BLOCKED: Do not use 'git -C <path>'. Set the working directory on the Bash tool call instead." >&2
  exit 2
fi

exit 0
