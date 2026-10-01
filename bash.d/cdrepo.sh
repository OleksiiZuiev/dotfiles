# Quick directory switcher for recent git repos. See `cd-repo --help`.

cd-repo() {
    if [[ "$1" == "-h" || "$1" == "--help" ]]; then
        cat <<'EOF'
Usage: cd-repo [path]

Quick directory switcher for recent git repos, sharing the ~/.claude_repos
history with lclaude (no Claude launch, no console clear).

  cd-repo          Show an fzf menu of recent repos (numbered menu without fzf)
                   and cd to the selection. In a git repo, the current dir is
                   listed first.
  cd-repo <path>   Validate <path> is a git repo, cd there, and record it in
                   history.

Options:
  -h, --help    Show this help and exit
EOF
        return 0
    fi

    local HISTORY_FILE="$HOME/.claude_repos"

    # Helper: record a repo/worktree dir in the shared ~/.claude_repos history
    _cd-repo_add_to_history() {
        bash "$HOME/.claude/scripts/record-repo.sh" "$1"
    }

    # Direct navigation: cd-repo <path>
    if [[ -n "$1" ]]; then
        local target="$1"
        if [[ ! -d "$target" ]]; then
            echo "Not a valid directory: $target"
            return 1
        fi
        if ! git -C "$target" rev-parse --git-dir > /dev/null 2>&1; then
            echo "Not a git repository: $target"
            return 1
        fi
        echo "Changing to: $target"
        cd "$target" || return 1
        _cd-repo_add_to_history "$target"
        return
    fi

    if ! git rev-parse --git-dir > /dev/null 2>&1 && [[ ! -s "$HISTORY_FILE" ]]; then
        echo "No repository history. Use lclaude to build history."
        return 1
    fi

    local dir
    dir=$(_repo_pick) || return 1

    if [[ "$dir" != "$(pwd)" ]]; then
        echo "Changing to: $dir"
        cd "$dir" || return 1
    fi
    _cd-repo_add_to_history "$dir"
}
