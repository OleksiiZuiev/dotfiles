# Sourced by every script that touches the shared database or the vault. They live on C: and only
# Windows processes write them, because WSL writers over /mnt/c are not safe — so every caller, from
# either OS, runs the Windows node on a Windows path.

_native_path() { # $1 path; prints it as the Windows node reads it
    if [[ -n "$WSL_DISTRO_NAME" ]]; then wslpath -w "$1"; else cygpath -w "$1"; fi
}

_windows_node() { # $1 script  $2... its arguments
    local node_bin script
    if [[ -n "$WSL_DISTRO_NAME" ]]; then
        node_bin="${CLAUDE_WINDOWS_NODE:-/mnt/c/Program Files/nodejs/node.exe}"
    else
        node_bin="${CLAUDE_WINDOWS_NODE:-node}"
    fi
    script=$(_native_path "$1" 2> /dev/null) || return 1
    "$node_bin" --disable-warning=ExperimentalWarning "$script" "${@:2}"
}
