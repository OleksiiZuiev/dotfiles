# Create a git worktree (new, existing-local, or remote-only branch), then cd
# in. See `start-worktree --help`.

start-worktree() {
    if [[ "$1" == "-h" || "$1" == "--help" ]]; then
        cat <<'EOF'
Usage: start-worktree <branch-name>

Create a git worktree for <branch-name> under the main repo's
<repo>-worktrees/ directory and cd into it. Works from the main repo or any
worktree (the worktree always lands under the main repo's shared folder).

Branch handling:
  - New branch:            creates the branch + worktree, then launches lclaude
  - Existing local branch: creates a worktree for it
  - Remote-only branch:    fetches origin/<branch> and creates a worktree

Prerequisites:
  - In a git repo
  - No uncommitted changes

Base branch (the worktree itself is made by claude/scripts/make-worktree.sh):
  - On main:     the new branch starts from an up-to-date origin/main
  - On non-main: warns and asks for confirmation (y/N); the new branch is
                 created from the current branch — useful for stacking PRs

Options:
  -h, --help    Show this help and exit
EOF
        return 0
    fi

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

    # Branching from a non-main branch stacks on it — ask for confirmation
    local current_branch=$(git branch --show-current)
    local base=()
    if [[ "$current_branch" != "main" ]]; then
        echo "Warning: You are on branch '$current_branch', not 'main'."
        echo "The new branch will be created from '$current_branch'."
        read -r -p "Continue? (y/N) " confirm
        if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
            echo "Aborted."
            return 1
        fi
        base=("$current_branch")
    fi

    local local_exists=false
    local remote_exists=false
    if git show-ref --verify --quiet "refs/heads/$branch"; then
        local_exists=true
    fi
    if git show-ref --verify --quiet "refs/remotes/origin/$branch"; then
        remote_exists=true
    fi

    local worktree_dir
    worktree_dir=$(bash "$HOME/.claude/scripts/make-worktree.sh" . "$branch" "${base[@]}") || return 1

    echo "Changing to: $worktree_dir"
    cd "$worktree_dir" || return 1

    # Launch lclaude only for new branches
    if [[ "$local_exists" == false && "$remote_exists" == false ]]; then
        lclaude
    fi
}
