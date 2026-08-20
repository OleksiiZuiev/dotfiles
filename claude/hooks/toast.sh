#!/usr/bin/env bash
# Runs the toast script through powershell.exe from either Git Bash or WSL:
# resolves toast.ps1 next to this file, converts it to a Windows path, and hands
# the hook payload on to it via stdin.
# Usage: toast.sh <Stop|Notification>

# readlink -f resolves the ~/.claude/hooks symlink down to the dotfiles copy.
# Without it, WSL would hand PowerShell a \\wsl.localhost path whose target is a
# Linux symlink Windows cannot follow.
ps1="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/toast.ps1"

if command -v wslpath > /dev/null 2>&1; then
    ps1=$(wslpath -w "$ps1")
elif command -v cygpath > /dev/null 2>&1; then
    ps1=$(cygpath -w "$ps1")
fi

exec powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$ps1" -EventName "${1:-Stop}"
