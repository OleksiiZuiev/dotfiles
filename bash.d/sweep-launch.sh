# Launch parallel /ds:refine Claude sessions — one Windows Terminal tab per
# ticket. See `sweep_launch --help`.

sweep_launch() {
    if [[ "$1" == "-h" || "$1" == "--help" ]]; then
        cat <<'EOF'
Usage: sweep_launch <ticket-id> [ticket-id ...]

Launch one Windows Terminal tab per ticket, each running
`claude "/ds:refine <ticket-id>"` (Git Bash profile) in the caller's current
directory. Tab titles are set to the ticket IDs.

Options:
  -h, --help    Show this help and exit
EOF
        return 0
    fi

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
