# Remove git worktrees whose branches have been merged via GitHub PR.
# See `clean-worktrees --help`.

clean-worktrees() {
    if [[ "$1" == "-h" || "$1" == "--help" ]]; then
        cat <<'EOF'
Usage: clean-worktrees

Remove git worktrees whose branches have been merged via a GitHub PR.

Prerequisites:
  - Run from the main repo (not from inside a worktree)
  - GitHub CLI (gh) installed and authenticated

Flow:
  1. List worktrees (skipping the main one)
  2. Check GitHub for a merged PR on each worktree's branch
  3. Show merged vs active worktrees
  4. Ask once to remove the merged worktrees, then once whether to also
     delete their remote branches
  5. Per worktree: remove it (long-path aware, forcing as a fallback) and
     delete its local branch; optionally delete its remote branch
  6. Prune stale worktree references

Options:
  -h, --help    Show this help and exit
EOF
        return 0
    fi

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

    # Confirm once for the whole set, then ask once about remote branches so the
    # removal loop runs unattended.
    read -r -p "Remove ${#merged_paths[@]} merged worktree(s)? (y/n) " confirm
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        echo "Aborted."
        return 0
    fi

    local delete_remotes=false
    read -r -p "Also delete their remote branches on origin? (y/n) " confirm_remotes
    if [[ "$confirm_remotes" == "y" || "$confirm_remotes" == "Y" ]]; then
        delete_remotes=true
    fi

    echo ""

    local removed=0
    local failed=0

    # Remove worktrees
    for i in "${!merged_paths[@]}"; do
        local path="${merged_paths[$i]}"
        local branch="${merged_branches[$i]}"

        echo "Removing worktree: $branch"

        # core.longpaths lets Windows git delete deeply nested files that would
        # otherwise fail with "Filename too long"; --force is the fallback for a
        # worktree git won't remove cleanly (e.g. uncommitted local changes).
        if ! git -c core.longpaths=true worktree remove "$path" 2>/dev/null \
            && ! git -c core.longpaths=true worktree remove --force "$path"; then
            echo "  Warning: Failed to remove worktree at $path (remove it manually)"
            failed=$((failed + 1))
            continue
        fi
        removed=$((removed + 1))

        # The worktree is gone; drop its local branch. Force-delete (-D) because
        # squash/rebase merges leave the branch looking unmerged to git even
        # though its PR merged.
        if git branch -D "$branch" > /dev/null 2>&1; then
            echo "  Deleted local branch."
        fi

        if $delete_remotes; then
            if git push origin --delete "$branch" 2>/dev/null; then
                echo "  Deleted remote branch."
            else
                echo "  Remote branch already gone."
            fi
        fi
    done

    # Clean up stale worktree references
    git worktree prune
    echo ""
    echo "Done. Removed $removed of ${#merged_paths[@]} merged worktree(s)."
    if [[ $failed -gt 0 ]]; then
        echo "$failed could not be removed — see warnings above."
    fi
}
