#!/bin/bash
# Register the daily Windows scheduled task that runs prune-worktrees.sh. See `register-prune-worktrees.sh --help`.

if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    cat <<'EOF'
Usage: register-prune-worktrees.sh

Register (or replace) the Windows scheduled task "prune-worktrees": daily at 12:00, or as soon as
the machine is next on after a missed run, it runs ~/.claude/scripts/prune-worktrees.sh in the Git
Bash home and then, when the WSL home has the script, in WSL. Each run appends its report to a log:
  Git Bash  /c/work/claude-data/prune-worktrees.log
  WSL       ~/.local/share/claude/prune-worktrees.log
Both run in a headless console, so no window opens. Run from Git Bash; elsewhere it prints a skip
line and does nothing.

Options:
  -h, --help    Show this help and exit
EOF
    exit 0
fi

if ! command -v cygpath > /dev/null 2>&1 || ! command -v powershell.exe > /dev/null 2>&1; then
    echo "  Skipped: the prune-worktrees scheduled task is registered from Git Bash on Windows"
    exit 0
fi

# Git's bin/bash.exe, unlike usr/bin/bash.exe, puts git and the mingw tools on PATH. The actions
# pass plain arguments, no shell string: Windows command-line parsing ignores single quotes, and
# these strings are embedded below as single-quoted PowerShell literals.
git_bash_args="\"$(cygpath -w /)bin\\bash.exe\" \"$(cygpath -m "$HOME")/.claude/scripts/prune-worktrees.sh\" --log C:/work/claude-data/prune-worktrees.log"
wsl_args="wsl.exe --cd ~ -e bash .claude/scripts/prune-worktrees.sh --log .local/share/claude/prune-worktrees.log"

with_wsl=false
command -v wsl.exe > /dev/null 2>&1 &&
    wsl.exe --cd ~ -e test -x .claude/scripts/prune-worktrees.sh > /dev/null 2>&1 &&
    with_wsl=true

ps1="$(mktemp -d)/register.ps1"
trap 'rm -rf "$(dirname "$ps1")"' EXIT
{
    echo "\$actions = @(New-ScheduledTaskAction -Execute 'conhost.exe' -Argument '--headless $git_bash_args')"
    $with_wsl && echo "\$actions += New-ScheduledTaskAction -Execute 'conhost.exe' -Argument '--headless $wsl_args'"
    cat <<'EOF'
$trigger = New-ScheduledTaskTrigger -Daily -At 12:00
$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
    -ExecutionTimeLimit (New-TimeSpan -Hours 2)
Register-ScheduledTask -TaskName 'prune-worktrees' -Action $actions -Trigger $trigger -Settings $settings -Force | Out-Null
EOF
} > "$ps1"

if powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$(cygpath -w "$ps1")"; then
    echo "  Registered scheduled task: prune-worktrees (daily 12:00, $($with_wsl && echo 'Git Bash and WSL' || echo 'Git Bash only'))"
else
    echo "  Warning: the prune-worktrees scheduled task was not registered"
    exit 1
fi
