# Resolves the Claude Code binary for whichever OS the shell is on.

# Native install first, Windows binary second. Resolved by path rather than a
# PATH lookup: in WSL a bare `claude` can resolve to the Windows .exe over
# /mnt/c interop, which would then run against Windows paths in a Linux tree.
claude_bin() {
    local candidate="$HOME/.local/bin/claude"
    [ -x "$candidate" ] || candidate="$HOME/.local/bin/claude.exe"
    printf '%s\n' "$candidate"
}
