# Claude-assisted merge/rebase helpers
#
# claude-rebase [target]   Rebase current branch onto origin/<target> (default: main).
# claude-merge  [target]   Merge origin/<target> into current branch (default: main).
#
# Run from the worktree of the branch you want to act on. On conflict, Claude
# is launched in plan mode with a prompt naming the conflicting files and the
# right finalize command.

_claude_git_op_usage() {
    local op="$1"
    local fn="claude-$op"

    local op_action
    local op_target_desc
    local finalize_hint
    if [[ "$op" == "rebase" ]]; then
        op_action="Rebase the current branch onto origin/<target>"
        op_target_desc="origin/<target>"
        finalize_hint="git rebase --continue"
    else
        op_action="Merge origin/<target> into the current branch"
        op_target_desc="origin/<target>"
        finalize_hint="git commit"
    fi

    cat <<EOF
Usage: $fn [target]

$op_action (default target: main).
Run from the worktree of the branch you want to act on.

Flow:
  1. Validate (clean tree, on a branch, not the target, no op in progress)
  2. Fetch $op_target_desc
  3. Run: git $op $op_target_desc
  4. On conflict: launch Claude in plan mode with a resolution prompt
                  (finalize with: $finalize_hint)
  5. On clean success: report and exit

Options:
  -h, --help    Show this help and exit
EOF
}

_claude_git_op_validate() {
    local op="$1"
    local target="$2"

    echo "> Validating..."

    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        echo "ERROR: Not in a git repository"
        return 1
    fi

    if ! git diff --quiet || ! git diff --cached --quiet; then
        echo "ERROR: Uncommitted changes detected. Commit or stash them first."
        return 1
    fi

    local current_branch
    current_branch=$(git branch --show-current)
    if [[ -z "$current_branch" ]]; then
        echo "ERROR: Detached HEAD. Switch to a branch first."
        return 1
    fi

    if [[ "$current_branch" == "$target" ]]; then
        echo "ERROR: Current branch is '$target' — cannot $op onto itself."
        return 1
    fi

    local git_dir
    git_dir=$(git rev-parse --git-dir)
    if [[ -d "$git_dir/rebase-merge" || -d "$git_dir/rebase-apply" ]]; then
        echo "ERROR: Rebase already in progress. Run 'git rebase --abort' or finalize it first."
        return 1
    fi
    if [[ -f "$git_dir/MERGE_HEAD" ]]; then
        echo "ERROR: Merge already in progress. Run 'git merge --abort' or finalize it first."
        return 1
    fi

    echo "  Validation passed."
    return 0
}

_claude_resolve_conflicts() {
    local op="$1"
    local target_ref="$2"
    local source_branch="$3"
    local real_claude="$HOME/.local/bin/claude.exe"

    local conflicting_files
    conflicting_files=$(git diff --name-only --diff-filter=U | tr '\n' ' ')

    local finalize_cmd
    if [[ "$op" == "rebase" ]]; then
        finalize_cmd="git rebase --continue (or --skip / --abort)"
    else
        finalize_cmd="git commit (or git merge --abort)"
    fi

    echo "  Conflicting files: $conflicting_files"
    echo "> Launching Claude in plan mode..."

    local prompt="I just ran 'git $op $target_ref' on branch '$source_branch' and hit conflicts. Conflicting files: $conflicting_files. Inspect the conflict markers, resolve them, stage the resolutions, and finalize the $op with: $finalize_cmd."

    clear
    "$real_claude" --permission-mode plan "$prompt"
}

claude-rebase() {
    if [[ "$1" == "-h" || "$1" == "--help" ]]; then
        _claude_git_op_usage rebase
        return 0
    fi

    local target="${1:-main}"

    _claude_git_op_validate "rebase" "$target" || return 1

    local current_branch
    current_branch=$(git branch --show-current)

    echo "> Fetching origin/$target..."
    if ! git fetch origin "$target"; then
        echo "ERROR: Failed to fetch origin/$target"
        return 1
    fi

    echo "> Rebasing '$current_branch' onto 'origin/$target'..."
    if git rebase "origin/$target"; then
        echo "OK: Rebase completed cleanly."
        return 0
    fi

    local git_dir
    git_dir=$(git rev-parse --git-dir)
    if [[ -d "$git_dir/rebase-merge" || -d "$git_dir/rebase-apply" ]]; then
        echo "  Conflicts detected."
        _claude_resolve_conflicts "rebase" "origin/$target" "$current_branch"
    else
        echo "ERROR: Rebase failed for a non-conflict reason. Investigate manually."
        return 1
    fi
}

claude-merge() {
    if [[ "$1" == "-h" || "$1" == "--help" ]]; then
        _claude_git_op_usage merge
        return 0
    fi

    local target="${1:-main}"

    _claude_git_op_validate "merge" "$target" || return 1

    local current_branch
    current_branch=$(git branch --show-current)

    echo "> Fetching origin/$target..."
    if ! git fetch origin "$target"; then
        echo "ERROR: Failed to fetch origin/$target"
        return 1
    fi

    echo "> Merging 'origin/$target' into '$current_branch'..."
    if git merge "origin/$target"; then
        echo "OK: Merge completed cleanly."
        return 0
    fi

    local git_dir
    git_dir=$(git rev-parse --git-dir)
    if [[ -f "$git_dir/MERGE_HEAD" ]]; then
        echo "  Conflicts detected."
        _claude_resolve_conflicts "merge" "origin/$target" "$current_branch"
    else
        echo "ERROR: Merge failed for a non-conflict reason. Investigate manually."
        return 1
    fi
}
