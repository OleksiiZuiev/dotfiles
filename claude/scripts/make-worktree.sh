#!/bin/bash
# Create (or reuse) a git worktree for a branch and print its path. Never prompts.
#
# The worktree lands under the main repo's <repo>-worktrees/<branch without
# prefix>, wherever <repo-path> sits (main repo or any worktree). Progress goes
# to stderr; stdout carries only the worktree path.
#
# A new branch starts from [base-branch] when given, otherwise from an
# up-to-date origin/main. The base is never inferred from the current branch.
#
# Usage: make-worktree.sh <repo-path> <branch> [base-branch]

set -u

repo="${1:-}"
branch="${2:-}"
base="${3:-}"

if [[ -z "$repo" || -z "$branch" ]]; then
    echo "Usage: make-worktree.sh <repo-path> <branch> [base-branch]" >&2
    exit 1
fi

if ! git -C "$repo" rev-parse --git-dir > /dev/null 2>&1; then
    echo "Error: $repo is not a git repository" >&2
    exit 1
fi

if ! git -C "$repo" diff --quiet || ! git -C "$repo" diff --cached --quiet; then
    echo "Error: Uncommitted changes in $repo. Commit or stash them first." >&2
    exit 1
fi

# --git-common-dir is the main repo's .git even from a worktree, so every
# worktree lands in one shared folder.
main_git_dir=$(git -C "$repo" rev-parse --path-format=absolute --git-common-dir)
repo_root=$(dirname "$main_git_dir")
worktree_dir="$(dirname "$repo_root")/$(basename "$repo_root")-worktrees/${branch#*/}"

if [[ -d "$worktree_dir" && "$(git -C "$worktree_dir" branch --show-current 2> /dev/null)" == "$branch" ]]; then
    echo "Reusing worktree at: $worktree_dir" >&2
elif git -C "$repo" show-ref --verify --quiet "refs/heads/$branch"; then
    echo "Using existing local branch '$branch'" >&2
    git -C "$repo" worktree add "$worktree_dir" "$branch" >&2 || exit 1
elif git -C "$repo" show-ref --verify --quiet "refs/remotes/origin/$branch"; then
    echo "Using existing remote branch 'origin/$branch'" >&2
    git -C "$repo" fetch origin "$branch" >&2
    git -C "$repo" worktree add "$worktree_dir" "$branch" >&2 || exit 1
else
    if [[ -z "$base" ]]; then
        echo "Fetching origin/main" >&2
        git -C "$repo" fetch origin main >&2 || exit 1
        base="origin/main"
    fi
    echo "Creating new branch '$branch' from '$base'" >&2
    git -C "$repo" worktree add --no-track -b "$branch" "$worktree_dir" "$base" >&2 || exit 1
fi

# Gitignored, so a new worktree would otherwise start without the main
# checkout's machine-local Claude settings (such as its env).
local_settings=".claude/settings.local.json"
if [[ -f "$repo_root/$local_settings" && ! -e "$worktree_dir/$local_settings" ]]; then
    mkdir -p "$worktree_dir/.claude"
    cp "$repo_root/$local_settings" "$worktree_dir/$local_settings"
fi

bash "$HOME/.claude/scripts/record-repo.sh" "$worktree_dir" >&2

echo "$worktree_dir"
