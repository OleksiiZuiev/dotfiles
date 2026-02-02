# Smart Claude launcher with repository history
# Usage: lclaude [args...]
# - In a git repo: launches claude directly
# - Not in a git repo: shows fzf menu of recent projects

lclaude() {
    local HISTORY_FILE="$HOME/.claude_repos"
    local MAX_HISTORY=10
    local real_claude="$HOME/.local/bin/claude.exe"

    # Helper: Add current directory to history (if git repo)
    _lclaude_add_to_history() {
        local dir="$1"
        [[ ! -d "$dir/.git" ]] && return

        # Create history file if missing
        touch "$HISTORY_FILE"

        # Remove existing entry, add to top, keep only MAX_HISTORY entries
        local temp_file=$(mktemp)
        echo "$dir" > "$temp_file"
        grep -v "^${dir}$" "$HISTORY_FILE" 2>/dev/null | head -n $((MAX_HISTORY - 1)) >> "$temp_file"
        mv "$temp_file" "$HISTORY_FILE"
    }

    # If we're in a git repo, launch directly
    if git rev-parse --git-dir > /dev/null 2>&1; then
        _lclaude_add_to_history "$(pwd)"
        "$real_claude" "$@"
        return
    fi

    # Not in a git repo - offer selection
    if [[ ! -f "$HISTORY_FILE" ]] || [[ ! -s "$HISTORY_FILE" ]]; then
        echo "Not in a git repository. No history available."
        echo "Launching Claude in current directory..."
        "$real_claude" "$@"
        return
    fi

    # Filter history to only existing directories
    local valid_repos=()
    while IFS= read -r repo; do
        [[ -d "$repo" ]] && valid_repos+=("$repo")
    done < "$HISTORY_FILE"

    if [[ ${#valid_repos[@]} -eq 0 ]]; then
        echo "Not in a git repository. No valid history entries."
        "$real_claude" "$@"
        return
    fi

    # Build selection list with "Stay here" option
    local selection
    if command -v fzf > /dev/null 2>&1; then
        selection=$(printf '%s\n' "${valid_repos[@]}" "[Stay in current directory]" | \
            fzf --header="Not in a git repo. Select a project:" --height=40% --reverse)
    else
        # Fallback: numbered menu
        echo "Not in a git repository. Select a project:"
        local i=1
        for repo in "${valid_repos[@]}"; do
            echo "  $i) $repo"
            ((i++))
        done
        echo "  $i) [Stay in current directory]"
        echo -n "Choice [1-$i]: "
        read -r choice
        if [[ "$choice" =~ ^[0-9]+$ ]] && [[ "$choice" -ge 1 ]] && [[ "$choice" -lt "$i" ]]; then
            selection="${valid_repos[$((choice-1))]}"
        else
            selection="[Stay in current directory]"
        fi
    fi

    # Handle selection
    if [[ -z "$selection" ]]; then
        echo "Cancelled."
        return 1
    elif [[ "$selection" == "[Stay in current directory]" ]]; then
        "$real_claude" "$@"
    else
        echo "Changing to: $selection"
        cd "$selection" || return 1
        _lclaude_add_to_history "$selection"
        "$real_claude" "$@"
    fi
}
