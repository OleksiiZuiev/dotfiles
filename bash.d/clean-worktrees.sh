# Clean up git worktrees whose branches have been merged via GitHub PR
# Usage: clean-worktrees
#
# Prerequisites:
#   - Must be in a git repo
#   - Must NOT be inside a worktree (must be in main repo)
#   - GitHub CLI (gh) must be installed and authenticated
#
# Actions:
#   - Lists all worktrees (skips the main one)
#   - Checks GitHub for merged PRs on each worktree's branch
#   - Shows summary of merged vs active worktrees
#   - Prompts for confirmation before cleanup
#   - Removes merged worktrees and optionally deletes remote branches

clean-worktrees() {
    # Validation: must be in a git repo
    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        echo "Error: Not in a git repository"
        return 1
    fi

    # Validation: must not be inside a worktree
    local current_dir="$(pwd)"
    if [[ "$current_dir" == *"worktrees"* ]]; then
        echo "Error: You're inside a worktree. Run this from the main repository."
        return 1
    fi

    # Collect worktrees (skip the main one, which is listed first)
    local worktree_paths=()
    local worktree_branches=()
    local is_first=true

    while IFS= read -r line; do
        if [[ "$line" == "worktree "* ]]; then
            if $is_first; then
                continue
            fi
            worktree_paths+=("${line#worktree }")
        elif [[ "$line" == "branch "* ]]; then
            if $is_first; then
                is_first=false
                continue
            fi
            local ref="${line#branch }"
            worktree_branches+=("${ref#refs/heads/}")
        fi
    done < <(git worktree list --porcelain)

    if [[ ${#worktree_paths[@]} -eq 0 ]]; then
        echo "No worktrees found (besides the main one)."
        return 0
    fi

    # Check GitHub for merged PRs
    local merged_paths=()
    local merged_branches=()
    local active_paths=()
    local active_branches=()

    echo "Checking ${#worktree_paths[@]} worktree(s) against GitHub..."
    echo ""

    for i in "${!worktree_paths[@]}"; do
        local path="${worktree_paths[$i]}"
        local branch="${worktree_branches[$i]}"

        local result
        result=$(gh pr list --head "$branch" --state merged --json headRefName --limit 1 2>/dev/null)

        if [[ "$result" != "[]" && -n "$result" ]]; then
            merged_paths+=("$path")
            merged_branches+=("$branch")
        else
            active_paths+=("$path")
            active_branches+=("$branch")
        fi
    done

    # Show summary
    if [[ ${#active_paths[@]} -gt 0 ]]; then
        echo "Active (no merged PR):"
        for i in "${!active_paths[@]}"; do
            echo "  ${active_branches[$i]}  →  ${active_paths[$i]}"
        done
        echo ""
    fi

    if [[ ${#merged_paths[@]} -eq 0 ]]; then
        echo "No worktrees with merged PRs found."
        return 0
    fi

    echo "Merged (ready to clean up):"
    for i in "${!merged_paths[@]}"; do
        echo "  ${merged_branches[$i]}  →  ${merged_paths[$i]}"
    done
    echo ""

    # Prompt for confirmation
    read -p "Remove ${#merged_paths[@]} merged worktree(s)? (y/n) " confirm
    if [[ "$confirm" != "y" ]]; then
        echo "Aborted."
        return 0
    fi

    echo ""

    # Remove worktrees
    for i in "${!merged_paths[@]}"; do
        local path="${merged_paths[$i]}"
        local branch="${merged_branches[$i]}"

        echo "Removing worktree: $branch"
        if ! git worktree remove "$path"; then
            echo "  Warning: Failed to remove worktree at $path (try --force manually)"
            continue
        fi

        # Offer to delete remote branch
        read -p "  Delete remote branch 'origin/$branch'? (y/n) " delete_remote
        if [[ "$delete_remote" == "y" ]]; then
            if git push origin --delete "$branch" 2>/dev/null; then
                echo "  Deleted remote branch: $branch"
            else
                echo "  Remote branch already deleted or not found."
            fi
        fi
    done

    # Clean up stale worktree references
    git worktree prune
    echo ""
    echo "Done. Cleaned up ${#merged_paths[@]} worktree(s)."
}
