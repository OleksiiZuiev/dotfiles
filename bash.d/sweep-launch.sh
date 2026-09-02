# Launch parallel /ds:refine Claude sessions — one Windows Terminal tab per
# ticket. See `sweep_launch --help`.

sweep_launch() {
    if [[ "$1" == "-h" || "$1" == "--help" ]]; then
        cat <<'USAGE'
Usage: sweep_launch <ticket-id> [ticket-id ...]

Launch one Windows Terminal tab per ticket, each running
`claude "/ds:refine <ticket-id>"` (Git Bash profile) in the caller's current
directory. Tab titles are set to the ticket IDs.

Options:
  -h, --help    Show this help and exit
USAGE
        return 0
    fi

    if [ $# -eq 0 ]; then
        echo "Usage: sweep_launch <ticket-id> [ticket-id ...]"
        return 1
    fi

    for ticket_id in "$@"; do
        echo "Launching /ds:refine session for: $ticket_id"
        bash "$HOME/.claude/scripts/claude-tab.sh" "$ticket_id" "$PWD" "/ds:refine $ticket_id"
    done

    echo ""
    echo "Launched $# session(s). Switch tabs with Ctrl+Tab."
}
