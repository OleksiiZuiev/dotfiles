# Every Claude session, grouped by ticket, from the sessions index. See `sessions --help`.

_SESSIONS_SH="${BASH_SOURCE[0]}"
source "$(dirname "$_SESSIONS_SH")/../lib/windows-node.sh"
_SESSIONS_LINEAR="https://linear.app/datasnipper-test/issue"
_SESSIONS_TICKETS_PROMPT="tickets> "
_SESSIONS_TICKETS_HEADER="enter: sessions · ctrl-n: new session in its worktree · ctrl-o: open in Linear · ctrl-r: refetch from Linear · esc: quit"
_SESSIONS_SESSIONS_HEADER="enter: resume in a new tab · ctrl-o: open the ticket in Linear · ctrl-r: refetch from Linear · esc: back to tickets"

# Runs sessions-db.mjs with the options only this side knows: the ticket contexts, the width, and
# from WSL the distro, through which a WSL session's files are read.
_sessions_db() {
    local contexts extra=()
    contexts=$(_native_path "${CLAUDE_TICKET_CONTEXTS_DIR:-/c/work/ticket-contexts}" 2> /dev/null)
    [[ -n "$WSL_DISTRO_NAME" ]] && extra=(--wsl-distro "$WSL_DISTRO_NAME")
    [[ "$1" == "list" || "$1" == "show" ]] && [[ -n "$contexts" ]] && extra+=(--ticket-contexts "$contexts")
    if [[ "$1" == "list" ]]; then
        # The view sets SESSIONS_WIDTH for its list and preview: fzf exports the FZF_* sizes to every
        # command it runs, so they cannot tell the list's width from the preview's.
        local width="${SESSIONS_WIDTH:-$COLUMNS}"
        [[ -z "$width" && -t 1 ]] && width=$(tput cols 2>/dev/null)
        [[ -n "$width" ]] && extra+=(--width "$width")
    fi
    _windows_node "$(dirname "$_SESSIONS_SH")/sessions-db.mjs" "$@" "${extra[@]}"
}

# Opens a tab running claude with the given arguments in a session's directory, on the OS the
# session ran on: a POSIX cwd marks a WSL session. The directory is checked on that OS first.
# $1 title  $2 cwd  $3 transcript (named when the directory is gone)  $4... claude arguments
_sessions_tab() {
    local title="$1" cwd="$2" transcript="$3" wsl=()
    if [[ "$cwd" == /* ]]; then
        wsl=(--wsl)
        if [[ -n "$WSL_DISTRO_NAME" ]]; then
            [[ -d "$cwd" ]]
        else
            MSYS2_ARG_CONV_EXCL='*' wsl.exe -e test -d "$cwd"
        fi
    elif [[ -n "$WSL_DISTRO_NAME" ]]; then
        echo "sessions: $title is a Windows session; open it from Git Bash" >&2
        return 1
    else
        [[ -n "$cwd" && -d "$(cygpath -u "$cwd")" ]]
    fi || {
        echo "sessions: $cwd no longer exists; transcript: $transcript" >&2
        return 1
    }

    if ! declare -F claude_tab > /dev/null; then
        source "$HOME/.claude/scripts/claude-tab.sh" || return 1
    fi
    claude_tab "${wsl[@]}" "$title" "$cwd" "${@:4}"
}

# Reopens a session, or a ticket's latest, in a new tab.
_sessions_resume() {
    if [[ -z "$1" ]]; then
        echo "Usage: sessions resume <session-id | ticket>" >&2
        return 1
    fi
    local located session_id cwd transcript ticket
    located=$(_sessions_db locate "$1") || return 1
    { read -r session_id; read -r cwd; read -r transcript; read -r ticket; } <<< "$located"
    _sessions_tab "${ticket:-${session_id:0:8}}" "$cwd" "$transcript" --resume "$session_id" || return 1
    echo "Resuming $session_id in a new tab."
}

# Starts a fresh claude in a new tab, in the ticket's worktree.
_sessions_new() {
    if [[ -z "$1" ]]; then
        echo "Usage: sessions new <ticket>" >&2
        return 1
    fi
    local located session_id cwd transcript ticket
    located=$(_sessions_db locate "$1" --worktree) || return 1
    { read -r session_id; read -r cwd; read -r transcript; read -r ticket; } <<< "$located"
    _sessions_tab "$ticket" "$cwd" "$transcript" || return 1
    echo "Starting a new session for $ticket in $cwd."
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
        --bind="ctrl-n:transform($self _view new {1})" \
        --bind="ctrl-o:transform($self _view open {1})" --bind="ctrl-r:transform($self _view refresh)" \
        < /dev/null > /dev/null
}

# $1 key (enter, esc, open, preview, refresh, reload)  $2 the first field of the row under the cursor
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
        # The list's stderr would land on fzf's screen.
        tickets:refresh) printf "reload(%s --refresh 2> /dev/null)" "$list" ;;
        sessions:refresh) printf "reload(%s --refresh > /dev/null 2>&1; %s '%s')" "$list" "$list" "$ticket" ;;
        tickets:enter)
            [[ -n "$field" ]] || return 0
            printf "reload(%s '%s')+change-prompt(%s sessions> )+change-with-nth(2..)+change-header(%s)+clear-query+first" \
                "$list" "$field" "$field" "$_SESSIONS_SESSIONS_HEADER" ;;
        sessions:esc)
            printf "reload(%s)+change-prompt(%s)+change-with-nth(1..)+change-header(%s)+clear-query+first" \
                "$list" "$_SESSIONS_TICKETS_PROMPT" "$_SESSIONS_TICKETS_HEADER" ;;
        tickets:esc) printf "abort" ;;
        sessions:enter)
            [[ -n "$field" ]] || return 0
            # The colon form takes the rest of the line, so a `)` in the reason cannot end the action.
            local reason
            reason=$(sessions resume "$field" 2>&1 > /dev/null) || printf "change-header:%s" "$reason" ;;
        tickets:new)
            [[ -n "$field" && "$field" != "—" ]] || return 0
            local reason
            reason=$(sessions new "$field" 2>&1 > /dev/null) || printf "change-header:%s" "$reason" ;;
        tickets:open | sessions:open)
            local target="${ticket:-$field}"
            [[ -n "$target" && "$target" != "—" ]] && printf "execute-silent(explorer.exe %s/%s)" "$_SESSIONS_LINEAR" "$target" ;;
        tickets:preview) [[ -n "$field" ]] && sessions show "$field" && echo && sessions list "$field" ;;
        sessions:preview) [[ -n "$field" ]] && sessions show "$field" ;;
    esac
    return 0
}

sessions() {
    if [[ "$1" == "-h" || "$1" == "--help" ]]; then
        cat <<'EOF'
Usage: sessions                              interactive view (fzf)
       sessions list [--json] [--refresh]    tickets, newest latest session first
       sessions list <ticket> [--json]       that ticket's sessions
       sessions show <session-id | ticket>   every field of one session, or of one ticket
       sessions resume <session-id | ticket> reopen a session, or a ticket's latest, in a new tab
       sessions new <ticket>                 start a new session in the ticket's worktree, in a new tab

Every Claude Code session on this machine, Windows and WSL, as recorded by the
SessionStart / SessionEnd / UserPromptSubmit hooks (session-index.sh), grouped
by the ticket parsed from its branch, or for a branchless session from a first
/ds:refine <ticket>. Sessions with no ticket are listed last under —;
pass — as <ticket> to list them. A session id may be given as any prefix.
Tables fit the terminal width, cutting the longest columns with an ellipsis.

  list            TICKET, TITLE, REPO, SESSIONS, LAST ACTIVE, and `open` when
                  any of the ticket's sessions has no end time — still running,
                  or killed before it could record one.
                  TITLE is the ticket's Linear title, else the first line of
                  the ticket context, else the branch slug.
  list <ticket>   SESSION, LAST ACTIVE, KIND, TITLE, DIRECTORY, and `open` when the
                  session has no end time. KIND is the command the session
                  began with (/ds:work-on); TITLE is its /rename title, else
                  Claude Code's own, else its first message — both read from
                  the transcript; /rename inside a session sets it.
                  DIRECTORY is marked (gone) when it no longer exists, and (?)
                  for a WSL session listed from Windows, whose directory and
                  transcript are not read from there.

  resume          Opens a Windows Terminal tab in the session's directory running
                  claude --resume <session-id>: a Git Bash tab for a Windows
                  session, a WSL tab for a WSL one. Refuses, naming the
                  transcript, when the directory no longer exists. A Windows
                  session resumes from Git Bash only.
  new             Opens a tab the same way, running plain claude in the
                  ticket's worktree: the directory of its latest session whose
                  branch names the ticket — not a /ds:refine session in the
                  repo checkout. Refuses when there is none, or it is gone.

Linear titles and projects are cached in the sessions database. `list` fetches
the tickets missing from the cache or fetched over a day ago, with the API key
in ~/.config/linear/api-key (Windows home, from either OS); with no key, or
Linear unreachable, it lists with what it has. --refresh refetches every listed
ticket and says when Linear cannot be reached.

The view: enter opens a ticket's sessions, and on a session resumes it in a
new tab, the view staying open — when it cannot, the header says why;
esc goes back, then quits; ctrl-n on a ticket starts a new session in its
worktree, the same way; ctrl-o opens the ticket in Linear; ctrl-r refetches from Linear and reloads.
The pane below shows the row under the cursor: a ticket's fields and its
sessions, or every field of a session.

Environment:
  CLAUDE_DATA_DB             database (default C:/work/claude-data/claude-data.db)
  CLAUDE_WINDOWS_NODE        node binary that opens it (default: the Windows node)
  CLAUDE_TICKET_CONTEXTS_DIR  ticket contexts (default /c/work/ticket-contexts)
  CLAUDE_LINEAR_KEY_FILE      Linear API key (default ~/.config/linear/api-key)
  CLAUDE_LINEAR_API           Linear GraphQL endpoint (default https://api.linear.app/graphql)

Options:
  --json        Print the rows as JSON
  --refresh     Refetch every listed ticket from Linear
  -h, --help    Show this help and exit
EOF
        return 0
    fi

    case "$1" in
        list | show) _sessions_db "$@" ;;
        resume) _sessions_resume "${@:2}" ;;
        new) _sessions_new "${@:2}" ;;
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
