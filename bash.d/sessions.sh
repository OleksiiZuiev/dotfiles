# Every Claude session, grouped by ticket, from the sessions index. See `sessions --help`.

_SESSIONS_SH="${BASH_SOURCE[0]}"
_SESSIONS_LINEAR="https://linear.app/datasnipper-test/issue"
_SESSIONS_TICKETS_PROMPT="tickets> "
_SESSIONS_TICKETS_HEADER="enter: sessions · ctrl-o: open in Linear · esc: quit"
_SESSIONS_SESSIONS_HEADER="ctrl-o: open the ticket in Linear · esc: back to tickets"

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
        # The view sets SESSIONS_WIDTH for its list and preview: fzf exports the FZF_* sizes to every
        # command it runs, so they cannot tell the list's width from the preview's.
        local width="${SESSIONS_WIDTH:-$COLUMNS}"
        [[ -z "$width" && -t 1 ]] && width=$(tput cols 2>/dev/null)
        [[ -n "$width" ]] && extra+=(--width "$width")
    fi
    "$node_bin" --disable-warning=ExperimentalWarning "$script" "$@" "${extra[@]}"
}

# One fzf in two modes, told apart by its prompt: the tickets, or one ticket's sessions. Every key
# that differs between them goes through `_view`, which prints the fzf actions for the current mode.
_sessions_view() {
    _sessions_db list > /dev/null || return 1
    local self="bash '$_SESSIONS_SH'"
    fzf --reverse --header-lines=1 --with-nth=1.. \
        --prompt="$_SESSIONS_TICKETS_PROMPT" --header="$_SESSIONS_TICKETS_HEADER" \
        --preview="SESSIONS_WIDTH=\$FZF_PREVIEW_COLUMNS $self _view preview {1}" --preview-window=down,50% \
        --bind="start,resize:transform($self _view reload)" \
        --bind="enter:transform($self _view enter {1})" \
        --bind="esc:transform($self _view esc)" \
        --bind="ctrl-o:transform($self _view open {1})" \
        < /dev/null > /dev/null
}

# $1 key (enter, esc, open, preview, reload)  $2 the first field of the row under the cursor
_sessions_view_key() {
    local key="$1" field="$2" mode=tickets ticket=""
    # fzf's pointer and marker take two columns in front of every row of its list, its scrollbar one after.
    local list="SESSIONS_WIDTH=\$((FZF_COLUMNS - 3)) bash '$_SESSIONS_SH' list"
    if [[ "$FZF_PROMPT" == *" sessions> " ]]; then
        mode=sessions
        ticket="${FZF_PROMPT% sessions> }"
    fi

    case "$mode:$key" in
        tickets:reload) printf "reload(%s)" "$list" ;;
        sessions:reload) printf "reload(%s '%s')" "$list" "$ticket" ;;
        tickets:enter)
            [[ -n "$field" ]] || return 0
            printf "reload(%s '%s')+change-prompt(%s sessions> )+change-with-nth(2..)+change-header(%s)+clear-query+first" \
                "$list" "$field" "$field" "$_SESSIONS_SESSIONS_HEADER" ;;
        sessions:esc)
            printf "reload(%s)+change-prompt(%s)+change-with-nth(1..)+change-header(%s)+clear-query+first" \
                "$list" "$_SESSIONS_TICKETS_PROMPT" "$_SESSIONS_TICKETS_HEADER" ;;
        tickets:esc) printf "abort" ;;
        tickets:open | sessions:open)
            local target="${ticket:-$field}"
            [[ -n "$target" && "$target" != "—" ]] && printf "execute-silent(explorer.exe %s/%s)" "$_SESSIONS_LINEAR" "$target" ;;
        tickets:preview) [[ -n "$field" ]] && sessions list "$field" ;;
        sessions:preview) [[ -n "$field" ]] && sessions show "$field" ;;
    esac
    return 0
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
  list <ticket>   SESSION, LAST ACTIVE, KIND, TITLE, DIRECTORY, and `open` when the
                  session has no end time. KIND is the command the session
                  began with (/ds:work-on); TITLE is its /rename title, else
                  Claude Code's own, else its first message — both read from
                  the transcript. DIRECTORY is marked (gone) when it no longer
                  exists, and (?) for a WSL session listed from Windows, whose
                  directory and transcript are not read from there.

The view: enter opens a ticket's sessions, esc goes back, then quits;
ctrl-o opens the ticket in Linear. The pane below shows the row under the
cursor: a ticket's sessions, or every field of a session.

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
        _view) _sessions_view_key "${@:2}" ;;
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

# Executed rather than sourced — fzf runs it for previews and keys, since it cannot see shell functions.
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    sessions "$@"
fi
