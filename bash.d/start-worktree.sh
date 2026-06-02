# Create git worktree with proper validations
# Usage: start-worktree <branch-name>
#
# Supports new and existing branches:
#   - New branch: creates branch + worktree, launches lclaude
#   - Existing local branch: creates worktree for it
#   - Remote-only branch: fetches and creates worktree for it
#
# Prerequisites (all must pass):
#   - Must be in a git repo (main repo or any worktree)
#   - Must have no uncommitted changes
#
# Base branch behavior:
#   - On main: pulls latest with rebase, then creates worktree
#   - On non-main (including from a worktree): warns user and asks for
#     confirmation (y/N), skips pull. New branch is created from the
#     current branch — useful for stacking PRs.
#
# Actions:
#   - Strips branch prefix (feat/int-31-foo -> int-31-foo)
#   - Creates worktree under the main repo's <repo>-worktrees directory,
#     even when invoked from another worktree
#   - CDs into the new worktree
#   - Launches lclaude (new branches only)

start-worktree() {
    local branch="$1"

    # Require branch name argument
    if [[ -z "$branch" ]]; then
        echo "Usage: start-worktree <branch-name>"
        return 1
    fi

    # Validation 1: Must be in a git repo
    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        echo "Error: Not in a git repository"
        return 1
    fi

    # Validation 2: Must have no uncommitted changes
    if ! git diff --quiet || ! git diff --cached --quiet; then
        echo "Error: Uncommitted changes detected. Commit or stash them first."
        return 1
    fi

    # Determine base branch behavior
    local current_branch=$(git branch --show-current)
    if [[ "$current_branch" == "main" ]]; then
        # Pull latest with rebase when on main
        echo "Pulling latest changes..."
        if ! git pull -r; then
            echo "Error: Failed to pull latest changes"
            return 1
        fi
    else
        # Branching from a non-main branch — ask for confirmation
        echo "Warning: You are on branch '$current_branch', not 'main'."
        echo "The new branch will be created from '$current_branch'."
        read -r -p "Continue? (y/N) " confirm
        if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
            echo "Aborted."
            return 1
        fi
    fi

    # Strip branch prefix (e.g., feat/int-31-foo -> int-31-foo)
    local stripped_branch="${branch#*/}"

    # Get the main repo root (not the current worktree's root) and
    # construct worktree directory.
    # In a worktree, --show-toplevel returns the worktree root; we need
    # the main repo root so all worktrees live under one shared folder.
    # --git-common-dir returns the main repo's .git dir (absolute in a
    # worktree, relative in the main repo), so we ask for absolute.
    local main_git_dir
    main_git_dir=$(git rev-parse --path-format=absolute --git-common-dir)
    local repo_root
    repo_root=$(dirname "$main_git_dir")
    local repo_name=$(basename "$repo_root")
    local repo_parent=$(dirname "$repo_root")
    local worktree_dir="$repo_parent/${repo_name}-worktrees/$stripped_branch"

    # Detect branch state
    local local_exists=false
    local remote_exists=false

    if git show-ref --verify --quiet "refs/heads/$branch"; then
        local_exists=true
    fi
    if git show-ref --verify --quiet "refs/remotes/origin/$branch"; then
        remote_exists=true
    fi

    # Create worktree based on branch state
    echo "Creating worktree at: $worktree_dir"
    if [[ "$local_exists" == true ]]; then
        echo "Using existing local branch '$branch'"
        if ! git worktree add "$worktree_dir" "$branch"; then
            echo "Error: Failed to create worktree"
            return 1
        fi
    elif [[ "$remote_exists" == true ]]; then
        echo "Using existing remote branch 'origin/$branch'"
        git fetch origin "$branch"
        if ! git worktree add "$worktree_dir" "$branch"; then
            echo "Error: Failed to create worktree"
            return 1
        fi
    else
        echo "Creating new branch '$branch'"
        if ! git worktree add -b "$branch" "$worktree_dir"; then
            echo "Error: Failed to create worktree"
            return 1
        fi
    fi

    # CD into worktree
    echo "Changing to: $worktree_dir"
    cd "$worktree_dir" || return 1

    # Record the worktree under the shell's pwd form (e.g. /c/... on Git Bash).
    # git rev-parse yields a drive-letter path (C:/...) that lclaude and cd-repo,
    # which compare against pwd, would treat as a distinct entry — surfacing the
    # same worktree twice in their pickers.
    worktree_dir="$(pwd)"

    # Record worktree in ~/.claude_repos so cd-repo can find it later.
    # Runs for all branch states; for new branches lclaude (below) de-dups.
    local history_file="$HOME/.claude_repos"
    local max_history=30
    touch "$history_file"
    local temp_file=$(mktemp)
    echo "$worktree_dir" > "$temp_file"
    grep -v "^${worktree_dir}$" "$history_file" 2>/dev/null | head -n $((max_history - 1)) >> "$temp_file"
    mv "$temp_file" "$history_file"

    # Launch lclaude only for new branches
    if [[ "$local_exists" == false && "$remote_exists" == false ]]; then
        lclaude
    fi
}
