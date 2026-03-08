# Launch parallel /ds:refine Claude sessions — one Windows Terminal tab per ticket.
#
# Usage: sweep_launch TICKET-1 TICKET-2 ...
#
# For each ticket ID:
#   - Opens a new Windows Terminal tab (Git Bash profile)
#   - Sets tab title to the ticket ID
#   - Launches claude with /ds:refine <ticket-id>
#   - Working directory = caller's $PWD

sweep_launch() {
    if [ $# -eq 0 ]; then
        echo "Usage: sweep_launch <ticket-id> [ticket-id ...]"
        return 1
    fi

    local BASH_WIN
    BASH_WIN=$(cygpath -w /usr/bin/bash)
    local CWD_WIN
    CWD_WIN=$(cygpath -w "$PWD")
    local CLAUDE_PATH
    CLAUDE_PATH="$HOME/.local/bin/claude.exe"

    for ticket_id in "$@"; do
        echo "Launching /ds:refine session for: $ticket_id"

        wt.exe -w 0 new-tab \
            --profile "Git Bash" \
            --title "$ticket_id" \
            --suppressApplicationTitle \
            --startingDirectory "$CWD_WIN" \
            "$BASH_WIN" -c "\"$CLAUDE_PATH\" \"/ds:refine $ticket_id\""
    done

    echo ""
    echo "Launched $# session(s). Switch tabs with Ctrl+Tab."
}
