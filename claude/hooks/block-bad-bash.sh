#!/bin/bash
# Guard hook for Bash tool calls (PreToolUse):
#  - auto-approves the known-safe throwaway-worktree teardown so it doesn't trip the
#    destructive-command prompt that fires even under auto permission mode;
#  - blocks genuinely dangerous patterns (force push, cloud delete/destroy);
#  - blocks `cd`, which CLAUDE.md also forbids. A cd compound leaves the working directory
#    unresolvable to the permission checker, so a search it would otherwise auto-approve turns
#    into a manual prompt -- and unlike CLAUDE.md, this reaches subagents.

INPUT=$(cat)

# The PreToolUse payload is JSON; the real command is tool_input.command. Parsing is gated
# behind a cheap substring pre-filter so python runs only for a command that could actually
# match — every other Bash call (ls, git status, builds, tests) skips it and the hook stays fast.
extract_cmd() {
  printf '%s' "$INPUT" \
    | python -c 'import sys,json; sys.stdout.write(json.load(sys.stdin).get("tool_input",{}).get("command",""))' 2>/dev/null
}

CMD=""
if [[ "$INPUT" == *rm* || "$INPUT" == *force* || "$INPUT" == *push* || "$INPUT" == *delete* \
   || "$INPUT" == *purge* || "$INPUT" == *destroy* || "$INPUT" == *teardown* \
   || "$INPUT" == *GIT_DIR* || "$INPUT" == *GIT_WORK_TREE* || "$INPUT" == *"cd "* ]]; then
  CMD=$(extract_cmd)
fi

# ---- Auto-approve: throwaway-worktree teardown helper ------------------------------------
# /ds:work-on and /ds:polish-pr call `worktree-teardown <path> [branch]` (a bash.d
# function) to tear down their private worktrees. Its `rm -rf` lives inside the function, so
# the command Claude issues carries no dangerous token — but allow it explicitly so the
# no-prompt guarantee is deterministic rather than resting on the destructive classifier
# happening to ignore an unknown command.
if [[ "$CMD" =~ ^[[:space:]]*worktree-teardown[[:space:]] ]]; then
  printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow","permissionDecisionReason":"Auto-approved worktree-teardown (/ds:work-on, /ds:polish-pr throwaway-worktree helper)."}}'
  exit 0
fi

# ---- Auto-approve: raw rm -rf of a worktree path (defense-in-depth) ----------------------
# The teardown helper above is the primary path. This still covers a stray raw
# `rm -rf "<...-worktrees/...>"` — e.g. a manual cleanup — matching either a forward-slash or
# a Windows backslash separator. Auto-approve that one narrow case; every other rm -rf still
# hits the normal prompt.
if [[ "$CMD" =~ ^[[:space:]]*rm[[:space:]]+-[rf][rf][[:space:]] ]] \
   && [[ "$CMD" == *-worktrees/* || "$CMD" == *-worktrees\\* ]]; then
  printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow","permissionDecisionReason":"Auto-approved throwaway-worktree teardown: rm -rf of a *-worktrees/* path (/ds:work-on, /ds:polish-pr)."}}'
  exit 0
fi

# ---- Block: genuinely dangerous patterns -------------------------------------------------
# A dangerous command lives on the FIRST line of the command; commit-message prose lives in
# heredoc bodies on later lines (or inside a -m "..." string). So scan only the first line,
# with quoted string literals stripped, so a message that merely mentions e.g. "--force" or
# "kubectl delete" can't false-trigger a block. A `;`- or `&&`-chained command sits on that same
# first line, so every segment of a chain is still scanned. (Limitation: a dangerous command buried
# on a later line of a multi-line command isn't caught.)
CMD_NOSTR=$(printf '%s' "$CMD" | sed -n '1p' | sed "s/\"[^\"]*\"//g; s/'[^']*'//g")

if [[ "$CMD_NOSTR" =~ ^[[:space:]]*(GIT_DIR|GIT_WORK_TREE)= ]]; then
  echo "BLOCKED: Use 'git -C <path>' instead of GIT_DIR/GIT_WORK_TREE env vars." >&2
  exit 2
fi
if echo "$CMD_NOSTR" | grep -qE '(^|[;&|][[:space:]]*)cd[[:space:]]'; then
  echo "BLOCKED: No 'cd'. Use 'git -C <path>' or absolute paths. A cd compound also hides the search root from the permission checker, which turns an auto-approved read into a manual prompt." >&2
  exit 2
fi
if echo "$CMD_NOSTR" | grep -qE 'git[[:space:]]+push[[:space:]].*--(force|force-with-lease)'; then
  echo "BLOCKED: Force push detected. This can cause irreversible remote history loss." >&2
  exit 2
fi
if echo "$CMD_NOSTR" | grep -qE 'git[[:space:]]+push[[:space:]]+-[a-zA-Z]*f'; then
  echo "BLOCKED: Force push (-f) detected. This can cause irreversible remote history loss." >&2
  exit 2
fi
if echo "$CMD_NOSTR" | grep -qE '\baz\b.*\b(delete|purge)\b'; then
  echo "BLOCKED: Azure destructive operation (delete/purge) detected." >&2
  exit 2
fi
if echo "$CMD_NOSTR" | grep -qE '\baws\b.*\bdelete\b'; then
  echo "BLOCKED: AWS destructive operation (delete) detected." >&2
  exit 2
fi
if echo "$CMD_NOSTR" | grep -qE '\bkubectl[[:space:]]+delete\b'; then
  echo "BLOCKED: kubectl delete detected." >&2
  exit 2
fi
if echo "$CMD_NOSTR" | grep -qE '\bterraform[[:space:]]+destroy\b'; then
  echo "BLOCKED: terraform destroy detected." >&2
  exit 2
fi

exit 0
