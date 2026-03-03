# Quick directory switcher for recent git repos
# Usage: cd-repo [path]
# - Shows fzf menu of recent projects from ~/.claude_repos
# - Selects a repo and CDs there

cd-repo() {
    local HISTORY_FILE="$HOME/.claude_repos"
    local MAX_HISTORY=30

    # Helper: Add current directory to history (if git repo or worktree)
    _cd-repo_add_to_history() {
        local dir="$1"
        git -C "$dir" rev-parse --git-dir > /dev/null 2>&1 || return

        # Create history file if missing
        touch "$HISTORY_FILE"

        # Remove existing entry, add to top, keep only MAX_HISTORY entries
        local temp_file=$(mktemp)
        echo "$dir" > "$temp_file"
        grep -v "^${dir}$" "$HISTORY_FILE" 2>/dev/null | head -n $((MAX_HISTORY - 1)) >> "$temp_file"
        mv "$temp_file" "$HISTORY_FILE"
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

    # Check if we're in a git repo
    local in_git_repo=false
    local current_dir="$(pwd)"
    if git rev-parse --git-dir > /dev/null 2>&1; then
        in_git_repo=true
    fi

    # Build list of valid repos from history
    local valid_repos=()
    if [[ -f "$HISTORY_FILE" ]] && [[ -s "$HISTORY_FILE" ]]; then
        while IFS= read -r repo; do
            [[ -d "$repo" ]] && valid_repos+=("$repo")
        done < "$HISTORY_FILE"
    fi

    # If in git repo, prepend current directory (remove duplicate if exists)
    if [[ "$in_git_repo" == true ]]; then
        local filtered_repos=()
        for repo in "${valid_repos[@]}"; do
            [[ "$repo" != "$current_dir" ]] && filtered_repos+=("$repo")
        done
        valid_repos=("$current_dir" "${filtered_repos[@]}")
    fi

    # If no repos to show, nothing to do
    if [[ ${#valid_repos[@]} -eq 0 ]]; then
        echo "No repository history. Use lclaude to build history."
        return 1
    fi

    # If only current dir and we're in git repo, already there
    if [[ "$in_git_repo" == true ]] && [[ ${#valid_repos[@]} -eq 1 ]]; then
        _cd-repo_add_to_history "$current_dir"
        return
    fi

    # Build header
    local header
    if [[ "$in_git_repo" == true ]]; then
        header="Select a project (current: $(basename "$current_dir")):"
    else
        header="Select a project:"
    fi

    # Build selection list - add "Stay here" only if NOT in git repo
    local menu_items=("${valid_repos[@]}")
    if [[ "$in_git_repo" == false ]]; then
        menu_items+=("[Stay in current directory]")
    fi

    # Show selection
    local selection
    if command -v fzf > /dev/null 2>&1; then
        selection=$(printf '%s\n' "${menu_items[@]}" | \
            fzf --header="$header" --height=40% --reverse)
    else
        # Fallback: numbered menu (capped at 15 items)
        echo "$header"
        local i=1
        local max_display=15
        for item in "${menu_items[@]}"; do
            if [[ $i -le $max_display ]]; then
                echo "  $i) $item"
            fi
            ((i++))
        done
        local total=$((i - 1))
        if [[ $total -gt $max_display ]]; then
            echo "  ... $((total - max_display)) more repos available — install fzf for fuzzy search"
        fi
        echo -n "Choice [1-$total]: "
        read -r choice
        if [[ "$choice" =~ ^[0-9]+$ ]] && [[ "$choice" -ge 1 ]] && [[ "$choice" -lt "$i" ]]; then
            selection="${menu_items[$((choice-1))]}"
        fi
    fi

    # Handle selection
    if [[ -z "$selection" ]]; then
        echo "Cancelled."
        return 1
    elif [[ "$selection" == "[Stay in current directory]" ]]; then
        return
    elif [[ "$selection" == "$current_dir" ]]; then
        _cd-repo_add_to_history "$current_dir"
    else
        echo "Changing to: $selection"
        cd "$selection" || return 1
        _cd-repo_add_to_history "$selection"
    fi
}
