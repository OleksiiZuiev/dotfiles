#!/bin/bash
# Open a Windows Terminal tab running a Claude session in a given directory,
# with the given claude arguments: a prompt, `--resume <session-id>`, or none.
#
# The launching shell is usually a Bash call inside another Claude session, whose
# environment carries that session's markers. Inherited, CLAUDE_CODE_CHILD_SESSION
# turns the new session's transcript off and the messaging socket makes the new
# session advertise its parent's named pipe as its own address, so the whole set
# is dropped here and the tab starts as an ordinary top-level session.
#
# Usage: claude-tab.sh [--wsl] <title> <dir> [<claude-arg>...]
#   --wsl  <dir> is a path in the WSL distro, and the tab runs there. Without it
#          the tab is a Git Bash one, opened from Git Bash only.

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
    local wsl=""
    if [[ "$1" == "--wsl" ]]; then
        wsl=1
        shift
    fi
    local title="$1" dir="$2"
    local claude_args=("${@:3}")

    if [[ -z "$title" || -z "$dir" ]]; then
        echo "Usage: claude-tab.sh [--wsl] <title> <dir> [<claude-arg>...]" >&2
        return 1
    fi
    if [[ -z "$wsl" && -n "$WSL_DISTRO_NAME" ]]; then
        echo "claude-tab.sh: a Git Bash tab opens from Git Bash only" >&2
        return 1
    fi

    # `bash claude-tab.sh` does not read ~/.bashrc, so bash.d may not be loaded
    if [[ -z "$wsl" ]] && ! declare -F claude_bin > /dev/null; then
        source "$HOME/.bash.d/claude-bin.sh" 2> /dev/null || {
            echo "claude-tab.sh: cannot resolve the claude binary (~/.bash.d/claude-bin.sh missing)" >&2
            return 1
        }
    fi

    # The tab runs a launcher script rather than a `bash -c` command line:
    # wt.exe drops the double quotes inside the command it is given, splitting a
    # quoted prompt into words, and reads a `;` as its own subcommand separator.
    # A file carries the arguments with no command-line parsing in between.
    local launcher
    launcher=$(mktemp "${TMPDIR:-/tmp}/claude-tab.XXXXXX") || return 1
    {
        printf 'rm -f -- "$0"\n'
        # A WSL tab resolves claude on its own side: the Windows binary means nothing there.
        [[ -n "$wsl" ]] && printf 'source "$HOME/.bash.d/claude-bin.sh"\n'
        printf 'exec env'
        printf ' -u %q' "${CLAUDE_TAB_INHERITED_ENV[@]}"
        if [[ -n "$wsl" ]]; then
            printf ' "$(claude_bin)"'
        else
            printf ' %q' "$(claude_bin)"
        fi
        printf ' %q' "${claude_args[@]}"
        printf '\n'
    } > "$launcher"

    if [[ -n "$wsl" ]]; then
        local distro=() launcher_path="$launcher"
        if [[ -n "$WSL_DISTRO_NAME" ]]; then
            distro=(-d "$WSL_DISTRO_NAME")
        else
            # From Git Bash the launcher is on a Windows drive, which WSL reaches through /mnt.
            local windows_path drive
            windows_path=$(cygpath -m "$launcher")
            drive="${windows_path:0:1}"
            launcher_path="/mnt/${drive,,}${windows_path:2}"
        fi
        MSYS2_ARG_CONV_EXCL='*' \
        wt.exe -w 0 new-tab \
            --profile Ubuntu \
            --title "$title" \
            --suppressApplicationTitle \
            wsl.exe "${distro[@]}" --cd "$dir" -e bash -l "$launcher_path"
        return
    fi

    # Every path below is already in Windows form, and without this a title that
    # looks like a lone POSIX path is rewritten to C:/…/Git/… on the way into a
    # native .exe
    MSYS2_ARG_CONV_EXCL='*' \
    wt.exe -w 0 new-tab \
        --profile "Git Bash" \
        --title "$title" \
        --suppressApplicationTitle \
        --startingDirectory "$(cygpath -w "$dir")" \
        "$(cygpath -w /usr/bin/bash)" "$(cygpath -m "$launcher")"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    claude_tab "$@"
fi
