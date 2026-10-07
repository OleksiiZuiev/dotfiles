# Sourced by session-index.sh and sessions.sh. The sessions database lives on C: and only Windows
# processes open it, because WSL writers over /mnt/c are not safe — so every caller, from either OS,
# runs the Windows node on a Windows path.

_sessions_native_path() { # $1 path; prints it as the Windows node reads it
    if [[ -n "$WSL_DISTRO_NAME" ]]; then wslpath -w "$1"; else cygpath -w "$1"; fi
}

_sessions_node() { # $1 script  $2... its arguments
    local node_bin script
    if [[ -n "$WSL_DISTRO_NAME" ]]; then
        node_bin="${CLAUDE_SESSIONS_NODE:-/mnt/c/Program Files/nodejs/node.exe}"
    else
        node_bin="${CLAUDE_SESSIONS_NODE:-node}"
    fi
    script=$(_sessions_native_path "$1" 2> /dev/null) || return 1
    "$node_bin" --disable-warning=ExperimentalWarning "$script" "${@:2}"
}
