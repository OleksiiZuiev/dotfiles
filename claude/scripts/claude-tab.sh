#!/bin/bash
# Open a Windows Terminal tab running a Claude session on a prompt, in a given
# directory.
#
# The launching shell is usually a Bash call inside another Claude session, whose
# environment carries that session's markers. Inherited, CLAUDE_CODE_CHILD_SESSION
# turns the new session's transcript off and the messaging socket makes the new
# session advertise its parent's named pipe as its own address, so the whole set
# is dropped here and the tab starts as an ordinary top-level session.
#
# Usage: claude-tab.sh <title> <dir> <prompt>

# Injected by Claude Code into every Bash subprocess. CLAUDECODE and
# CLAUDE_CODE_ENTRYPOINT are left alone: claude sets both for itself.
CLAUDE_TAB_INHERITED_ENV=(
    CLAUDE_CODE_CHILD_SESSION
    CLAUDE_CODE_SESSION_ID
    CLAUDE_CODE_MESSAGING_SOCKET
    CLAUDE_CODE_MESSAGING_TOKEN
    CLAUDE_PID
    TRACEPARENT
    AI_AGENT
    CLAUDE_EFFORT
)

claude_tab() {
    local title="$1" dir="$2" prompt="$3"

    if [[ -z "$title" || -z "$dir" || -z "$prompt" ]]; then
        echo "Usage: claude-tab.sh <title> <dir> <prompt>" >&2
        return 1
    fi

    # `bash claude-tab.sh` does not read ~/.bashrc, so bash.d may not be loaded
    if ! declare -F claude_bin > /dev/null; then
        source "$HOME/.bash.d/claude-bin.sh" 2> /dev/null || {
            echo "claude-tab.sh: cannot resolve the claude binary (~/.bash.d/claude-bin.sh missing)" >&2
            return 1
        }
    fi

    # `env -u`, not `unset ...;` — Windows Terminal reads a `;` in the tab's
    # command line as its own subcommand separator
    local strip=()
    local var
    for var in "${CLAUDE_TAB_INHERITED_ENV[@]}"; do
        strip+=(-u "$var")
    done

    # Every path below is already in Windows form, and without this a prompt that
    # looks like a lone POSIX path ("/status") is rewritten to C:/…/Git/status on
    # the way into a native .exe
    MSYS2_ARG_CONV_EXCL='*' \
    wt.exe -w 0 new-tab \
        --profile "Git Bash" \
        --title "$title" \
        --suppressApplicationTitle \
        --startingDirectory "$(cygpath -w "$dir")" \
        "$(cygpath -w /usr/bin/bash)" -c "env ${strip[*]} \"$(claude_bin)\" \"$prompt\""
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    claude_tab "$@"
fi
