# Every Claude session, grouped by ticket, from the sessions index. See `sessions --help`.

_SESSIONS_SH="${BASH_SOURCE[0]}"

# Runs the sessions index script on the Windows node from either OS, as claude/hooks/session-index.sh
# does: the database lives on C:, and only Windows processes open it.
_sessions_db() {
    local script="$HOME/.claude/scripts/sessions-db.mjs" node_bin contexts
    contexts="${CLAUDE_TICKET_CONTEXTS_DIR:-/c/work/ticket-contexts}"
    local extra=()
    if [[ -n "$WSL_DISTRO_NAME" ]]; then
        node_bin="${CLAUDE_SESSIONS_NODE:-/mnt/c/Program Files/nodejs/node.exe}"
        script=$(wslpath -w "$script")
        contexts=$(wslpath -w "$contexts" 2>/dev/null)
        extra=(--wsl-distro "$WSL_DISTRO_NAME")
    else
        node_bin="${CLAUDE_SESSIONS_NODE:-node}"
        script=$(cygpath -w "$script")
        contexts=$(cygpath -w "$contexts" 2>/dev/null)
    fi
    if [[ "$1" == "list" ]]; then
        [[ -n "$contexts" ]] && extra+=(--ticket-contexts "$contexts")
        local width="${FZF_PREVIEW_COLUMNS:-$COLUMNS}"
        [[ -z "$width" && -t 1 ]] && width=$(tput cols 2>/dev/null)
        [[ -n "$width" ]] && extra+=(--width "$width")
    fi
    "$node_bin" --disable-warning=ExperimentalWarning "$script" "$@" "${extra[@]}"
}

_sessions_view() {
    local linear="https://linear.app/datasnipper-test/issue"
    local tickets ticket
    # fzf's pointer and marker take two columns in front of every row.
    local COLUMNS=$(( ${COLUMNS:-$(tput cols 2>/dev/null || echo 80)} - 2 ))
    tickets=$(_sessions_db list) || return 1
    while ticket=$(printf '%s\n' "$tickets" | fzf --reverse --header-lines=1 \
            --header='enter: sessions · ctrl-o: open in Linear · esc: quit' \
            --preview="bash '$_SESSIONS_SH' list {1}" --preview-window=down,50% \
            --bind="ctrl-o:execute-silent([[ {1} == — ]] || explorer.exe $linear/{1})" \
            | awk '{ print $1 }') && [[ -n "$ticket" ]]; do
        _sessions_db list "$ticket" | fzf --reverse --header-lines=1 \
            --header="$ticket · esc: back" \
            --preview="bash '$_SESSIONS_SH' show {1}" --preview-window=down,40% \
            --bind='enter:ignore' > /dev/null
        tickets=$(_sessions_db list) || return 1
    done
}

sessions() {
    if [[ "$1" == "-h" || "$1" == "--help" ]]; then
        cat <<'EOF'
Usage: sessions                         interactive view (fzf)
       sessions list [--json]           tickets, newest latest session first
       sessions list <ticket> [--json]  that ticket's sessions
       sessions show <session-id>       every recorded field of one session

Every Claude Code session on this machine, Windows and WSL, as recorded by the
SessionStart / SessionEnd hooks (claude/hooks/session-index.sh), grouped by the
ticket parsed from its branch. Sessions with no ticket are listed last under —;
pass — as <ticket> to list them. A session id may be given as any prefix.
Tables fit the terminal width, cutting the longest columns with an ellipsis.

  list            TICKET, TITLE, REPO, SESSIONS, LAST ACTIVE, and `open` when
                  any of the ticket's sessions has no end time — still running,
                  or killed before it could record one.
                  TITLE is the first line of the ticket context, else the
                  branch slug.
  list <ticket>   SESSION, REPO, BRANCH, DIRECTORY, STARTED, ENDED (or `open`).
                  DIRECTORY is marked (gone) when it no longer exists, and (?)
                  for a WSL session listed from Windows, where it is not checked.

The view: enter opens a ticket's sessions, esc goes back, then quits;
ctrl-o opens the ticket in Linear.

Environment:
  CLAUDE_SESSIONS_DB          database (default C:/work/claude-data/sessions.db)
  CLAUDE_SESSIONS_NODE        node binary that opens it (default: the Windows node)
  CLAUDE_TICKET_CONTEXTS_DIR  ticket contexts (default /c/work/ticket-contexts)

Options:
  --json        Print the rows as JSON
  -h, --help    Show this help and exit
EOF
        return 0
    fi

    case "$1" in
        list | show) _sessions_db "$@" ;;
        "")
            if command -v fzf > /dev/null 2>&1; then
                _sessions_view
            else
                _sessions_db list && echo "(install fzf for the interactive view)"
            fi
            ;;
        *) echo "sessions: unknown command '$1' (see sessions --help)" >&2; return 1 ;;
    esac
}

# Executed rather than sourced — fzf's preview runs it, since it cannot see shell functions.
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    sessions "$@"
fi
