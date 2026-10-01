# Recent-repo picker shared by lclaude, cd-repo and lcode.
#
# _repo_pick prints the chosen directory on stdout and returns 0, or returns 1
# when the menu is dismissed. Menu text goes to stderr so callers can capture
# the result with dir=$(_repo_pick). Resolves to $PWD without a menu when there
# is nothing else to pick.

_repo_pick() {
    local HISTORY_FILE="$HOME/.claude_repos"

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

    # Nothing to choose between: no history, or only the current repo
    if [[ ${#valid_repos[@]} -eq 0 ]] || \
       { [[ "$in_git_repo" == true ]] && [[ ${#valid_repos[@]} -eq 1 ]]; }; then
        echo "$current_dir"
        return 0
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
        echo "$header" >&2
        local i=1
        local max_display=15
        for item in "${menu_items[@]}"; do
            if [[ $i -le $max_display ]]; then
                echo "  $i) $item" >&2
            fi
            ((i++))
        done
        local total=$((i - 1))
        if [[ $total -gt $max_display ]]; then
            echo "  ... $((total - max_display)) more repos available — install fzf for fuzzy search" >&2
        fi
        echo -n "Choice [1-$total]: " >&2
        local choice
        read -r choice
        if [[ "$choice" =~ ^[0-9]+$ ]] && [[ "$choice" -ge 1 ]] && [[ "$choice" -lt "$i" ]]; then
            selection="${menu_items[$((choice-1))]}"
        fi
    fi

    if [[ -z "$selection" ]]; then
        echo "Cancelled." >&2
        return 1
    elif [[ "$selection" == "[Stay in current directory]" ]]; then
        echo "$current_dir"
    else
        echo "$selection"
    fi
}
