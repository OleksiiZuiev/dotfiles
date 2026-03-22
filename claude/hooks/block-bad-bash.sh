#!/bin/bash
# Guard hook: block genuinely dangerous CLI patterns.
# Style rules (no chaining, no cd) are enforced by CLAUDE.md instructions.
#
# Extract only the command portion (before any quoted strings) to avoid
# false positives from commit messages or string arguments.
INPUT=$(cat)
CMD_PART=$(echo "$INPUT" | sed "s/['\"].*//")

# GIT_DIR/GIT_WORK_TREE env vars — use `git -C <path>` instead
if echo "$CMD_PART" | grep -qE '^\s*(GIT_DIR|GIT_WORK_TREE)='; then
  echo "BLOCKED: Use 'git -C <path>' instead of GIT_DIR/GIT_WORK_TREE env vars." >&2
  exit 2
fi

# Force push — irreversible remote history loss
if echo "$CMD_PART" | grep -qE 'git\s+push\s+.*--(force|force-with-lease)'; then
  echo "BLOCKED: Force push detected. This can cause irreversible remote history loss." >&2
  exit 2
fi
if echo "$CMD_PART" | grep -qE 'git\s+push\s+-[a-zA-Z]*f'; then
  echo "BLOCKED: Force push (-f) detected. This can cause irreversible remote history loss." >&2
  exit 2
fi

# Azure destructive operations
if echo "$CMD_PART" | grep -qE '\baz\b.*\b(delete|purge)\b'; then
  echo "BLOCKED: Azure destructive operation (delete/purge) detected." >&2
  exit 2
fi

# AWS destructive operations
if echo "$CMD_PART" | grep -qE '\baws\b.*\bdelete\b'; then
  echo "BLOCKED: AWS destructive operation (delete) detected." >&2
  exit 2
fi

# Kubernetes destructive operations
if echo "$CMD_PART" | grep -qE '\bkubectl\s+delete\b'; then
  echo "BLOCKED: kubectl delete detected." >&2
  exit 2
fi

# Terraform destroy
if echo "$CMD_PART" | grep -qE '\bterraform\s+destroy\b'; then
  echo "BLOCKED: terraform destroy detected." >&2
  exit 2
fi

exit 0
