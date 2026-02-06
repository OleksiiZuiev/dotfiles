# Smart Claude launcher with repository history
# Usage: lclaude [args...]
# - Always shows fzf menu of recent projects
# - In a git repo: current directory is first option (pre-selected)
# - Not in a git repo: shows history with "[Stay in current directory]" option

lclaude() {
    local HISTORY_FILE="$HOME/.claude_repos"
    local MAX_HISTORY=10
    local real_claude="$HOME/.local/bin/claude.exe"

    # Helper: Add current directory to history (if git repo or worktree)
    _lclaude_add_to_history() {
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

    # If no repos to show, just launch
    if [[ ${#valid_repos[@]} -eq 0 ]]; then
        echo "No history available. Launching Claude in current directory..."
        "$real_claude" "$@"
        return
    fi

    # If only current dir and we're in git repo, launch directly (no need to prompt)
    if [[ "$in_git_repo" == true ]] && [[ ${#valid_repos[@]} -eq 1 ]]; then
        _lclaude_add_to_history "$current_dir"
        "$real_claude" "$@"
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
        # Fallback: numbered menu
        echo "$header"
        local i=1
        for item in "${menu_items[@]}"; do
            echo "  $i) $item"
            ((i++))
        done
        echo -n "Choice [1-$((i-1))]: "
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
        "$real_claude" "$@"
    elif [[ "$selection" == "$current_dir" ]]; then
        _lclaude_add_to_history "$current_dir"
        "$real_claude" "$@"
    else
        echo "Changing to: $selection"
        cd "$selection" || return 1
        _lclaude_add_to_history "$selection"
        "$real_claude" "$@"
    fi
}
