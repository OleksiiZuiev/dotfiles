# Create git worktree with proper validations
# Usage: start-worktree <branch-name>
#
# Prerequisites (all must pass):
#   - Must be in a git repo
#   - Current path must NOT contain "worktrees" (must be in main repo)
#   - Must be on main branch
#   - Must have no uncommitted changes
#
# Actions:
#   - Pulls latest with rebase
#   - Strips branch prefix (feat/int-31-foo -> int-31-foo)
#   - Creates worktree at ../repo-worktrees/<stripped-branch-name>
#   - CDs into the new worktree

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

    # Validation 2: Must not be in a worktree (path must not contain "worktrees")
    local current_dir="$(pwd)"
    if [[ "$current_dir" == *"worktrees"* ]]; then
        echo "Error: Already in a worktree. Run this from the main repository."
        return 1
    fi

    # Validation 3: Must be on main branch
    local current_branch=$(git branch --show-current)
    if [[ "$current_branch" != "main" ]]; then
        echo "Error: Must be on 'main' branch (currently on '$current_branch')"
        return 1
    fi

    # Validation 4: Must have no uncommitted changes
    if ! git diff --quiet || ! git diff --cached --quiet; then
        echo "Error: Uncommitted changes detected. Commit or stash them first."
        return 1
    fi

    # Pull latest with rebase
    echo "Pulling latest changes..."
    if ! git pull -r; then
        echo "Error: Failed to pull latest changes"
        return 1
    fi

    # Strip branch prefix (e.g., feat/int-31-foo -> int-31-foo)
    local stripped_branch="${branch#*/}"

    # Get repo root and construct worktree directory
    # e.g., /work/github/integrations-service -> /work/github/integrations-service-worktrees/<branch>
    local repo_root=$(git rev-parse --show-toplevel)
    local repo_name=$(basename "$repo_root")
    local repo_parent=$(dirname "$repo_root")
    local worktree_dir="$repo_parent/${repo_name}-worktrees/$stripped_branch"

    # Create worktree with new branch
    echo "Creating worktree at: $worktree_dir"
    if ! git worktree add -b "$branch" "$worktree_dir"; then
        echo "Error: Failed to create worktree"
        return 1
    fi

    # CD into worktree
    echo "Changing to: $worktree_dir"
    cd "$worktree_dir"
}
