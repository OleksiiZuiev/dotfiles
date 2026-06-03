#!/bin/bash
# Append a git repo/worktree directory to the recent-repos history that
# cd-repo and lclaude read from (~/.claude_repos).
#
# Normalizes the path to the shell's pwd form (/c/... on Git Bash) so a
# directory recorded as C:/... and later visited as /c/... is not listed
# twice. Keeps the most-recent 30 entries, most-recent first.
#
# Usage: record-repo.sh <dir>

record_repo_history() {
    local dir="$1"
    local history_file="${CLAUDE_REPOS_FILE:-$HOME/.claude_repos}"
    local max_history=30

    [[ -n "$dir" ]] || return

    # Only record real git repos / worktrees
    git -C "$dir" rev-parse --git-dir > /dev/null 2>&1 || return

    # Normalize to pwd form so C:/... and /c/... don't both appear
    if command -v cygpath > /dev/null 2>&1; then
        dir="$(cygpath -u "$dir")"
    fi

    touch "$history_file"
    local temp_file
    temp_file=$(mktemp)
    echo "$dir" > "$temp_file"
    grep -Fxv -- "$dir" "$history_file" 2>/dev/null | head -n $((max_history - 1)) >> "$temp_file"
    mv "$temp_file" "$history_file"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    record_repo_history "$1"
fi
