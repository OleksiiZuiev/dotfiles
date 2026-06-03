# Browse and resume named Claude Code sessions across all repos.
# See `resumex --help`. Requires named-sessions.json populated by /namex.

resumex() {
    if [[ "$1" == "-h" || "$1" == "--help" ]]; then
        cat <<'EOF'
Usage: resumex [search-query]

Browse named Claude Code sessions across all repos via fzf (numbered menu
without fzf), then resume the selected one: cd to its project directory and run
`claude --resume <session-id>`. An optional search-query pre-filters the list.

Requires sessions bookmarked with the /namex slash command. Index file:
${CLAUDE_NAMED_SESSIONS:-/c/work/claude-data/named-sessions.json}

Options:
  -h, --help    Show this help and exit
EOF
        return 0
    fi

    local INDEX_FILE="${CLAUDE_NAMED_SESSIONS:-/c/work/claude-data/named-sessions.json}"
    local real_claude="$HOME/.local/bin/claude.exe"
    local query="${1:-}"

    if [[ ! -f "$INDEX_FILE" ]]; then
        echo "No named sessions found. Use /namex <name> inside Claude to bookmark a session."
        return 1
    fi

    # Build display lines: "name | branch | project | age"
    # Also build parallel arrays for projectPath and sessionId
    local display_lines
    display_lines=$(node -e "
        const fs = require('fs');
        const entries = JSON.parse(fs.readFileSync('$INDEX_FILE', 'utf8'));
        const now = Date.now();
        const ago = (ms) => {
            const m = Math.floor(ms / 60000);
            if (m < 60) return m + 'm ago';
            const h = Math.floor(m / 60);
            if (h < 24) return h + 'h ago';
            const d = Math.floor(h / 24);
            return d + 'd ago';
        };
        entries
            .sort((a, b) => (b.namedAt || '').localeCompare(a.namedAt || ''))
            .slice(0, 30)
            .forEach(e => {
                const proj = e.projectPath.split(/[\\\\\/]/).pop();
                const age = ago(now - new Date(e.namedAt).getTime());
                console.log(e.name + ' | ' + (e.gitBranch || '-') + ' | ' + proj + ' | ' + age);
            });
    " 2>/dev/null)

    if [[ -z "$display_lines" ]]; then
        echo "No named sessions found or index is empty."
        return 1
    fi

    # Show selection
    local selection
    if command -v fzf > /dev/null 2>&1; then
        local fzf_args=(--header="Resume named session:" --height=40% --reverse)
        if [[ -n "$query" ]]; then
            fzf_args+=(--query="$query")
        fi
        selection=$(echo "$display_lines" | fzf "${fzf_args[@]}")
    else
        # Fallback: numbered menu
        echo "Resume named session:"
        local i=1
        while IFS= read -r line; do
            echo "  $i) $line"
            ((i++))
        done <<< "$display_lines"
        echo -n "Choice [1-$((i-1))]: "
        local choice
        read -r choice
        if [[ "$choice" =~ ^[0-9]+$ ]] && [[ "$choice" -ge 1 ]] && [[ "$choice" -lt "$i" ]]; then
            selection=$(echo "$display_lines" | sed -n "${choice}p")
        fi
    fi

    if [[ -z "$selection" ]]; then
        echo "Cancelled."
        return 1
    fi

    # Extract the name from the selection (first field before |)
    local selected_name
    selected_name=$(echo "$selection" | sed 's/ |.*//')

    # Look up projectPath and sessionId by name
    local session_info
    session_info=$(node -e "
        const fs = require('fs');
        const entries = JSON.parse(fs.readFileSync('$INDEX_FILE', 'utf8'));
        const name = '$selected_name';
        const entry = entries.find(e => e.name === name);
        if (entry) {
            console.log(entry.projectPath);
            console.log(entry.sessionId);
        }
    " 2>/dev/null)

    if [[ -z "$session_info" ]]; then
        echo "Error: could not find session '$selected_name' in index."
        return 1
    fi

    local project_path
    project_path=$(echo "$session_info" | head -1)
    local session_id
    session_id=$(echo "$session_info" | tail -1)

    # Convert Windows path to Unix path for cd
    local unix_path
    unix_path=$(cygpath -u "$project_path" 2>/dev/null || echo "$project_path")

    if [[ ! -d "$unix_path" ]]; then
        echo "Error: project directory no longer exists: $project_path"
        return 1
    fi

    echo "Resuming '$selected_name' in: $project_path"
    cd "$unix_path" || return 1
    clear
    "$real_claude" --resume "$session_id"
}
